package cn.profitlook.yinkui

import android.app.Application
import cn.profitlook.yinkui.core.FundStore

class App : Application() {
    override fun onCreate() {
        super.onCreate()
        FundStore.init(this)
    }
}
