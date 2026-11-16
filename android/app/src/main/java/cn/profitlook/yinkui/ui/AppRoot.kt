package cn.profitlook.yinkui.ui

import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.VisibilityThreshold
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.IntOffset
import cn.profitlook.yinkui.core.FundStore
import cn.profitlook.yinkui.core.QuoteService
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

sealed interface Screen {
    data object Home : Screen
    data object Add : Screen
    data class Edit(val code: String) : Screen
    data class Detail(val code: String) : Screen
    data object Settings : Screen
}

/** 导航方向：决定转场是「前进」还是「后退」，从而给出相反的滑动方向。 */
private enum class NavDirection { Forward, Back }

@Composable
fun AppRoot() {
    var stack by remember { mutableStateOf<List<Screen>>(listOf(Screen.Home)) }
    var direction by remember { mutableStateOf(NavDirection.Forward) }
    val current = stack.last()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val prefs by FundStore.prefs.collectAsState()
    var refreshing by remember { mutableStateOf(false) }

    suspend fun doRefresh() {
        val codes = FundStore.funds.value.map { it.code }
        if (codes.isEmpty()) {
            Toast.makeText(context, "还没有基金可刷新", Toast.LENGTH_SHORT).show()
            return
        }
        refreshing = true
        val quotes = QuoteService.refresh(codes)
        FundStore.applyQuotes(quotes)
        refreshing = false
        Toast.makeText(
            context,
            if (quotes.isEmpty()) "刷新失败，请检查网络" else "已更新 ${quotes.size} 只基金净值",
            Toast.LENGTH_SHORT,
        ).show()
    }

    LaunchedEffect(prefs.autoRefreshSecs) {
        val secs = prefs.autoRefreshSecs
        if (secs <= 0) return@LaunchedEffect
        while (true) {
            delay(secs * 1000L)
            doRefresh()
        }
    }

    fun push(screen: Screen) {
        direction = NavDirection.Forward
        stack = stack + screen
    }

    fun pop() {
        if (stack.size > 1) {
            direction = NavDirection.Back
            stack = stack.dropLast(1)
        }
    }

    BackHandler(enabled = stack.size > 1) { pop() }

    AnimatedContent(
        targetState = current,
        transitionSpec = {
            val slideSpec = spring<IntOffset>(
                stiffness = Spring.StiffnessMediumLow,
                dampingRatio = Spring.DampingRatioNoBouncy,
                visibilityThreshold = IntOffset.VisibilityThreshold,
            )
            val fadeSpec = tween<Float>(durationMillis = 140)
            if (direction == NavDirection.Forward) {
                // 前进：新页从右侧整屏滑入，旧页向左小幅退出（视差）
                (slideInHorizontally(animationSpec = slideSpec) { fullWidth -> fullWidth } + fadeIn(fadeSpec))
                    .togetherWith(
                        slideOutHorizontally(animationSpec = slideSpec) { fullWidth -> -fullWidth / 3 } + fadeOut(fadeSpec),
                    )
            } else {
                // 后退：新页从左侧小幅滑入，旧页向右整屏退出
                (slideInHorizontally(animationSpec = slideSpec) { fullWidth -> -fullWidth / 3 } + fadeIn(fadeSpec))
                    .togetherWith(
                        slideOutHorizontally(animationSpec = slideSpec) { fullWidth -> fullWidth } + fadeOut(fadeSpec),
                    )
            }
        },
        label = "screen-transition",
    ) { screen ->
        when (screen) {
            Screen.Home -> HomeScreen(
                refreshing = refreshing,
                onRefresh = { scope.launch { doRefresh() } },
                onAdd = { push(Screen.Add) },
                onSettings = { push(Screen.Settings) },
                onDetail = { push(Screen.Detail(it)) },
                onEdit = { push(Screen.Edit(it)) },
            )

            Screen.Add -> EditorScreen(
                code = null,
                onClose = { pop() },
                onOpenExisting = { existing ->
                    direction = NavDirection.Forward
                    stack = stack.dropLast(1) + Screen.Detail(existing)
                },
            )

            is Screen.Edit -> EditorScreen(
                code = screen.code,
                onClose = { pop() },
            )

            is Screen.Detail -> DetailScreen(
                code = screen.code,
                onBack = { pop() },
                onEdit = { push(Screen.Edit(screen.code)) },
            )

            Screen.Settings -> SettingsScreen(onBack = { pop() })
        }
    }
}
