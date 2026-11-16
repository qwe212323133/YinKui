package cn.profitlook.yinkui.core

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray
import org.json.JSONObject

data class Prefs(
    val hideAmounts: Boolean = false,
    val showHold: Boolean = true,
    val scheme: String = "cn",
    val autoRefreshSecs: Int = 0,
    val heroShowsCum: Boolean = false,
)

/**
 * 数据仓库：SharedPreferences + org.json，零第三方依赖。
 * key 与 iOS 封版一致（pl_*），便于日后跨平台迁移。
 * 用 StateFlow 驱动 Compose，避免引入 Room / DataStore / ViewModel 之外的额外依赖。
 */
object FundStore {
    private const val FILE = "profitlook"
    private const val K_FUNDS = "pl_funds"
    private const val K_HOLD = "pl_hold"
    private const val K_SCHEME = "pl_scheme"
    private const val K_AUTO = "pl_autoRefresh"
    private const val K_HIDE = "pl_hide_amounts"
    private const val K_HERO_CUM = "pl_hero_cum"

    private lateinit var sp: SharedPreferences
    private var ready = false

    private val _funds = MutableStateFlow<List<Fund>>(emptyList())
    val funds: StateFlow<List<Fund>> = _funds.asStateFlow()

    private val _prefs = MutableStateFlow(Prefs())
    val prefs: StateFlow<Prefs> = _prefs.asStateFlow()

    fun init(context: Context) {
        if (ready) return
        sp = context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        _funds.value = readFunds()
        _prefs.value = readPrefs()
        ready = true
    }

    private fun readPrefs() = Prefs(
        hideAmounts = sp.getBoolean(K_HIDE, false),
        showHold = sp.getString(K_HOLD, "1") != "0",
        scheme = if (sp.getString(K_SCHEME, "cn") == "us") "us" else "cn",
        autoRefreshSecs = sp.getInt(K_AUTO, 0),
        heroShowsCum = sp.getBoolean(K_HERO_CUM, false),
    )

    private fun updatePrefs(change: Prefs.() -> Prefs) {
        val next = _prefs.value.change()
        _prefs.value = next
    }

    fun setHideAmounts(v: Boolean) {
        sp.edit().putBoolean(K_HIDE, v).apply()
        updatePrefs { copy(hideAmounts = v) }
    }

    fun setShowHold(v: Boolean) {
        sp.edit().putString(K_HOLD, if (v) "1" else "0").apply()
        updatePrefs { copy(showHold = v) }
    }

    fun setScheme(v: String) {
        val s = if (v == "us") "us" else "cn"
        sp.edit().putString(K_SCHEME, s).apply()
        updatePrefs { copy(scheme = s) }
    }

    fun setAutoRefreshSecs(v: Int) {
        sp.edit().putInt(K_AUTO, maxOf(0, v)).apply()
        updatePrefs { copy(autoRefreshSecs = maxOf(0, v)) }
    }

    fun setHeroShowsCum(v: Boolean) {
        sp.edit().putBoolean(K_HERO_CUM, v).apply()
        updatePrefs { copy(heroShowsCum = v) }
    }

    /** null = 首次启动（示例）；"[]" = 用户主动清空（必须尊重，不能回退示例）。 */
    private fun readFunds(): List<Fund> {
        val raw = sp.getString(K_FUNDS, null) ?: return seed()
        if (raw == "[]") return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { i ->
                val o = arr.getJSONObject(i)
                Fund(
                    code = o.optString("code"),
                    name = o.optString("name"),
                    estNav = o.optDouble("estNav", 1.0),
                    estPct = o.optDouble("estPct", 0.0),
                    amount = o.optDouble("amount", 0.0),
                    mv = o.optDouble("mv", 0.0),
                    shares = o.optDouble("shares", 0.0),
                    time = o.optString("time", "--:--"),
                )
            }
        } catch (e: Exception) {
            seed()
        }
    }

    private fun persist() {
        val arr = JSONArray()
        _funds.value.forEach { f ->
            arr.put(JSONObject().apply {
                put("code", f.code)
                put("name", f.name)
                put("estNav", f.estNav)
                put("estPct", f.estPct)
                put("amount", f.amount)
                put("mv", f.mv)
                put("shares", f.shares)
                put("time", f.time)
            })
        }
        sp.edit().putString(K_FUNDS, arr.toString()).apply()
    }

    fun add(fund: Fund) {
        if (_funds.value.any { it.code == fund.code }) return
        _funds.value = _funds.value + fund
        persist()
    }

    fun update(code: String, change: Fund.() -> Fund) {
        _funds.value = _funds.value.map { if (it.code == code) it.change().recomputed() else it }
        persist()
    }

    fun remove(code: String) {
        _funds.value = _funds.value.filterNot { it.code == code }
        persist()
    }

    fun clear() {
        _funds.value = emptyList()
        sp.edit().putString(K_FUNDS, "[]").apply()
    }

    /** 刷新成功后落地：更新净值 / 涨跌 / 净值日，并按份额重算市值。 */
    fun applyQuotes(quotes: Map<String, Quote>) {
        if (quotes.isEmpty()) return
        _funds.value = _funds.value.map { f ->
            val q = quotes[f.code] ?: return@map f
            f.copy(estNav = q.nav, estPct = q.pct, time = q.date).recomputed()
        }
        persist()
    }

    fun seed() = listOf(
        Fund(code = "000001", name = "华夏成长混合", estNav = 1.2345, estPct = 1.50, time = "15:00"),
        Fund(code = "161725", name = "招商中证白酒", estNav = 0.9876, estPct = -2.00, time = "15:00"),
        Fund(code = "110011", name = "易方达中小盘", estNav = 3.4567, estPct = 0.33, time = "15:00"),
    )
}
