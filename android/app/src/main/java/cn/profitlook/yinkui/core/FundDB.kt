package cn.profitlook.yinkui.core

import android.content.Context

/** 内嵌 28330 条「基金代码 → 名称」映射，本地查表、零网络。 */
object FundDB {
    @Volatile
    private var map: Map<String, String>? = null

    private fun ensure(context: Context): Map<String, String> {
        map?.let { return it }
        val loaded = try {
            context.applicationContext.assets.open("funddb.txt")
                .bufferedReader(Charsets.UTF_8).useLines { lines ->
                    lines.mapNotNull { line ->
                        val i = line.indexOf('|')
                        if (i <= 0 || i == line.length - 1) null
                        else line.substring(0, i) to line.substring(i + 1)
                    }.toMap()
                }
        } catch (e: Exception) {
            emptyMap()
        }
        map = loaded
        return loaded
    }

    fun name(context: Context, code: String): String? = ensure(context)[code]
}
