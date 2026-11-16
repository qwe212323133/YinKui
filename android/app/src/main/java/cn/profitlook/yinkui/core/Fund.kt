package cn.profitlook.yinkui.core

import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.math.abs

/**
 * 与 iOS 封版一致的基金模型。
 * shares > 0 且 estNav > 0 时，市值 = 份额 × 最新净值，随刷新自动重算；
 * 未填份额维持手填市值（向后兼容旧数据）。
 */
data class Fund(
    val code: String = "",
    val name: String = "",
    val estNav: Double = 1.0,
    val estPct: Double = 0.0,
    val amount: Double = 0.0,
    val mv: Double = 0.0,
    val shares: Double = 0.0,
    val time: String = "--:--",
) {
    fun recomputed(): Fund =
        if (shares > 0 && estNav > 0) copy(mv = Fmt.round2(shares * estNav)) else this
}

object Fmt {
    const val MASKED = "••••••"

    private val moneyFormat = DecimalFormat("#,##0.00", DecimalFormatSymbols(Locale.CHINA))
    private val dateFormat = SimpleDateFormat("MM-dd", Locale.CHINA).apply {
        timeZone = TimeZone.getTimeZone("Asia/Shanghai")
    }

    /** 金额唯一出口：隐私态在这里统一打码，输入框走原始 Double 不受影响。 */
    @Synchronized
    fun money(n: Double, hidden: Boolean): String =
        if (hidden) MASKED else "¥" + moneyFormat.format(n)

    /** 涨跌幅：零值不带符号（方向色只承载确有方向的信息）。 */
    fun pct(p: Double): String {
        val v = if (abs(p) < 0.005) 0.0 else p
        return String.format(Locale.CHINA, "%s%.2f%%", if (v > 0) "+" else "", v)
    }

    fun nav(v: Double): String = String.format(Locale.CHINA, "%.4f", v)

    fun num(v: Double, digits: Int = 2): String =
        String.format(Locale.CHINA, "%.${digits}f", v)

    fun round2(v: Double): Double = Math.round(v * 100.0) / 100.0

    fun todayStr(): String = dateFormat.format(Date())

    fun dateFromMillis(ms: Long): String = dateFormat.format(Date(ms))
}

/** 收益口径统计：只统计有市值的持仓，没有任何可统计持仓时返回 null。 */
data class Stats(val profit: Double, val pct: Double)

fun List<Fund>.totalMv(): Double = sumOf { it.mv }

/** 当日 / 净值日收益：市值加权涨跌幅。 */
fun List<Fund>.todayStats(): Stats? {
    val held = filter { it.mv > 0 }
    val base = held.sumOf { it.mv }
    if (held.isEmpty() || base <= 0) return null
    val profit = held.sumOf { it.mv * it.estPct / 100.0 }
    return Stats(profit, profit / base * 100.0)
}

/** 累计收益：市值 − 持有成本，涨跌幅基数为成本。 */
fun List<Fund>.cumStats(): Stats? {
    val held = filter { it.mv > 0 && it.amount > 0 }
    val cost = held.sumOf { it.amount }
    if (held.isEmpty() || cost <= 0) return null
    val profit = held.sumOf { it.mv } - cost
    return Stats(profit, profit / cost * 100.0)
}

/** 头卡洞察句：真实持仓涨跌分布，不编造基准、不预测收益。 */
fun List<Fund>.insightLine(): String? {
    val held = filter { it.mv > 0 }
    if (held.isEmpty()) return null
    val n = held.size
    val up = held.count { it.estPct > 0.005 }
    val down = held.count { it.estPct < -0.005 }
    return when {
        up == n -> "$n 只全部上涨"
        down == n -> "$n 只全部下跌"
        up > 0 -> "$n 只中 $up 只上涨"
        down > 0 -> "$n 只中 $down 只下跌"
        else -> "$n 只持仓基本持平"
    }
}

/** 净值日 ≠ 今天时如实叫「净值日收益」，不谎称今日。 */
fun List<Fund>.dayLabel(): String {
    val stamps = map { it.time }.filter { Regex("\\d{2}-\\d{2}").matches(it) }
    return if (stamps.isNotEmpty() && stamps.maxOrNull() == Fmt.todayStr()) "今日收益" else "净值日收益"
}
