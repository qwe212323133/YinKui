package cn.profitlook.yinkui

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import cn.profitlook.yinkui.core.AppTheme
import cn.profitlook.yinkui.core.FundStore
import cn.profitlook.yinkui.ui.AppRoot

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        FundStore.init(applicationContext)
        setContent {
            AppTheme { AppRoot() }
        }
    }
}
