package cn.profitlook.yinkui.core

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

data class Quote(val nav: Double, val pct: Double, val date: String)

data class HoldingRow(
    val code: String,
    val name: String,
    val pct: Double,
    val chg: Double? = null,
)

data class HoldingsResult(
    val ok: Boolean = false,
    val period: String = "",
    val deadline: String = "",
    val rows: List<HoldingRow> = emptyList(),
)

private const val UA =
    "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Mobile Safari/537.36"

/** 只用 HttpURLConnection：无 OkHttp / Retrofit，和 iOS 版一样零第三方依赖。 */
private fun httpGet(url: String, referer: String? = null, timeout: Int = 15000): String? {
    val conn = (URL(url).openConnection() as HttpURLConnection).apply {
        connectTimeout = timeout
        readTimeout = timeout
        requestMethod = "GET"
        instanceFollowRedirects = true
        setRequestProperty("User-Agent", UA)
        if (referer != null) setRequestProperty("Referer", referer)
    }
    return try {
        if (conn.responseCode !in 200..299) {
            conn.disconnect()
            null
        } else {
            // 成功时不 disconnect：让 JVM keep-alive 池复用连接，省掉后续请求的 TCP+TLS 握手。
            conn.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
        }
    } catch (e: Exception) {
        try { conn.disconnect() } catch (_: Exception) {}
        null
    }
}

/**
 * 最新单位净值与日涨跌：天天基金 F10 历史净值接口（pageSize=1，仅几百字节）。
 * DWJZ=单位净值、JZZZL=日增长率(%)、FSRQ=净值日，与 iOS 封版的 pingzhongdata 口径一致，
 * 但数据量缩小约 2000 倍，刷新明显更快。
 */
object QuoteService {
    /** 并发限流：基金很多时避免同时开满连接触发限流。 */
    private val limiter = Semaphore(8)

    suspend fun refresh(codes: List<String>): Map<String, Quote> = withContext(Dispatchers.IO) {
        if (codes.isEmpty()) return@withContext emptyMap()
        coroutineScope {
            codes.distinct().map { code -> async { code to fetchOne(code) } }
                .awaitAll()
                .mapNotNull { (code, quote) -> quote?.let { code to it } }
                .toMap()
        }
    }

    private suspend fun fetchOne(code: String): Quote? = limiter.withPermit {
        val raw = httpGet(
            "https://api.fund.eastmoney.com/f10/lsjz?fundCode=$code&pageIndex=1&pageSize=1",
            "https://fundf10.eastmoney.com/jjjz_$code.html",
        ) ?: return@withPermit null
        try {
            val item = JSONObject(raw)
                .optJSONObject("Data")
                ?.optJSONArray("LSJZList")
                ?.optJSONObject(0) ?: return@withPermit null
            val nav = item.optDouble("DWJZ", Double.NaN)
            val pct = item.optDouble("JZZZL", Double.NaN)
            if (nav.isNaN() || nav <= 0 || pct.isNaN()) return@withPermit null
            val date = item.optString("FSRQ")
            Quote(nav, pct, if (date.length >= 10) date.substring(5) else "--:--")
        } catch (e: Exception) {
            null
        }
    }
}

/** 真实重仓股：F10 jjcc 页面 + push2 批量行情合并当日涨跌幅。 */
object HoldingsService {
    suspend fun fetch(code: String): HoldingsResult = withContext(Dispatchers.IO) {
        val url = "https://fundf10.eastmoney.com/FundArchivesDatas.aspx" +
            "?type=jjcc&code=$code&topline=10&year=&month="
        val raw = httpGet(url, "https://fundf10.eastmoney.com/ccmx_$code.html")
            ?: return@withContext HoldingsResult()
        val parsed = parse(raw) ?: return@withContext HoldingsResult()
        HoldingsResult(
            ok = parsed.rows.isNotEmpty(),
            period = parsed.period,
            deadline = parsed.deadline,
            rows = mergeQuotes(parsed.rows),
        )
    }

    private fun mergeQuotes(rows: List<HoldingRow>): List<HoldingRow> {
        if (rows.isEmpty()) return rows
        val secids = rows.joinToString(",") { row ->
            val prefix = if (row.code.startsWith("6") || row.code.startsWith("9")) "1" else "0"
            "$prefix.${row.code}"
        }
        val raw = httpGet(
            "https://push2.eastmoney.com/api/qt/ulist.np/get?secids=$secids&fields=f12,f3",
            timeout = 8000,
        ) ?: return rows
        return try {
            val diff = JSONObject(raw).optJSONObject("data")?.optJSONArray("diff")
                ?: return rows
            val changes = HashMap<String, Double>()
            for (i in 0 until diff.length()) {
                val item = diff.optJSONObject(i) ?: continue
                val c = item.optString("f12")
                if (c.isNotEmpty()) changes[c] = item.optDouble("f3", Double.NaN) / 100.0
            }
            if (changes.isEmpty()) rows
            else rows.map { row ->
                val chg = changes[row.code]
                if (chg == null || chg.isNaN()) row else row.copy(chg = chg)
            }
        } catch (e: Exception) {
            rows
        }
    }

    private fun parse(raw: String): HoldingsResult? {
        val content = extractContent(raw) ?: return null
        val period = Regex("(\\d{4}年\\d季度股票投资明细)").find(content)?.groupValues?.get(1) ?: ""
        val deadline = Regex("截止至：<font[^>]*>(\\d{4}-\\d{2}-\\d{2})")
            .find(content)?.groupValues?.get(1) ?: ""
        val rows = ArrayList<HoldingRow>()
        val seen = HashSet<String>()
        val trRe = Regex("<tr[^>]*>(.*?)</tr>", RegexOption.DOT_MATCHES_ALL)
        val tdRe = Regex("<td[^>]*>(.*?)</td>", RegexOption.DOT_MATCHES_ALL)
        val codeRe = Regex(">(\\d{6})<")
        val pctRe = Regex("([\\d.]+)%")
        for (tr in trRe.findAll(content)) {
            val tds = tdRe.findAll(tr.groupValues[1]).map { it.groupValues[1] }.toList()
            if (tds.size < 5) continue
            val code = codeRe.find(tds[1])?.groupValues?.get(1) ?: continue
            val name = stripTags(tds[2]).trim()
            val pct = pctRe.find(tds[4])?.groupValues?.get(1)?.toDoubleOrNull() ?: continue
            if (name.isEmpty() || !seen.add(code)) continue
            rows.add(HoldingRow(code, name, pct))
            if (rows.size >= 10) break
        }
        return HoldingsResult(period = period, deadline = deadline, rows = rows)
    }

    /** 从 `content:"..."` 里取出被引号包住的 HTML（处理常见反斜杠转义）。 */
    private fun extractContent(raw: String): String? {
        val key = "content:\""
        val start = raw.indexOf(key).takeIf { it >= 0 } ?: return null
        var i = start + key.length
        var escaped = false
        val sb = StringBuilder()
        while (i < raw.length) {
            val ch = raw[i]
            when {
                escaped -> {
                    sb.append(
                        when (ch) {
                            'n' -> '\n'
                            'r' -> '\r'
                            't' -> '\t'
                            else -> ch
                        }
                    )
                    escaped = false
                }
                ch == '\\' -> escaped = true
                ch == '"' -> return sb.toString()
                else -> sb.append(ch)
            }
            i++
        }
        return null
    }

    private fun stripTags(html: String): String {
        val sb = StringBuilder()
        var inTag = false
        for (ch in html) {
            when {
                ch == '<' -> inTag = true
                ch == '>' -> inTag = false
                !inTag -> sb.append(ch)
            }
        }
        return sb.toString().replace("&nbsp;", " ").replace("&amp;", "&")
    }
}
