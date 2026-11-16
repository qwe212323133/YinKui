package cn.profitlook.yinkui.ui

import android.widget.Toast
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import cn.profitlook.yinkui.core.AppCard
import cn.profitlook.yinkui.core.AppCardRadius
import cn.profitlook.yinkui.core.CardGap
import cn.profitlook.yinkui.core.Fmt
import cn.profitlook.yinkui.core.Fund
import cn.profitlook.yinkui.core.FundStore
import cn.profitlook.yinkui.core.MoneyText
import cn.profitlook.yinkui.core.Prefs
import cn.profitlook.yinkui.core.ScreenPadding
import cn.profitlook.yinkui.core.SecondaryText
import cn.profitlook.yinkui.core.cumStats
import cn.profitlook.yinkui.core.dayLabel
import cn.profitlook.yinkui.core.insightLine
import cn.profitlook.yinkui.core.pctColor
import cn.profitlook.yinkui.core.tabular
import cn.profitlook.yinkui.core.tierSecondary
import cn.profitlook.yinkui.core.todayStats
import cn.profitlook.yinkui.core.totalMv

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    refreshing: Boolean,
    onRefresh: () -> Unit,
    onAdd: () -> Unit,
    onSettings: () -> Unit,
    onDetail: (String) -> Unit,
    onEdit: (String) -> Unit,
) {
    val funds by FundStore.funds.collectAsState()
    val prefs by FundStore.prefs.collectAsState()
    val context = LocalContext.current
    val listState = rememberLazyListState()

    val compact by remember(funds.size) {
        derivedStateOf {
            funds.size >= 3 &&
                (listState.firstVisibleItemIndex > 0 || listState.firstVisibleItemScrollOffset > 260)
        }
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text("盈亏一眼", fontWeight = FontWeight.SemiBold) },
                actions = {
                    TextButton(onClick = { FundStore.setHideAmounts(!prefs.hideAmounts) }) {
                        Text(if (prefs.hideAmounts) "显示" else "隐藏")
                    }
                    IconButton(onClick = onRefresh) {
                        Icon(Icons.Default.Refresh, contentDescription = "刷新净值")
                    }
                    IconButton(onClick = onSettings) {
                        Icon(Icons.Default.Settings, contentDescription = "设置")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
        floatingActionButton = {
            FloatingActionButton(onClick = onAdd) {
                Icon(Icons.Default.Add, contentDescription = "添加基金")
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            PullToRefreshBox(
                isRefreshing = refreshing,
                onRefresh = onRefresh,
                modifier = Modifier.fillMaxSize(),
            ) {
                LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(
                        start = ScreenPadding,
                        end = ScreenPadding,
                        top = 8.dp,
                        bottom = 100.dp,
                    ),
                    verticalArrangement = Arrangement.spacedBy(CardGap),
                ) {
                    item { HeroCard(funds, prefs) }

                    if (funds.isEmpty()) {
                        item { EmptyCard(onAdd) }
                    } else {
                        items(funds, key = { it.code }) { fund ->
                            FundRowCard(
                                fund = fund,
                                showHold = prefs.showHold,
                                onDetail = { onDetail(fund.code) },
                                onEdit = { onEdit(fund.code) },
                                onDelete = {
                                    FundStore.remove(fund.code)
                                    Toast.makeText(context, "已删除 ${fund.name}", Toast.LENGTH_SHORT).show()
                                },
                            )
                        }
                    }

                    item { SourceNote() }
                }
            }

            AnimatedVisibility(
                visible = compact,
                enter = fadeIn() + slideInVertically { -it / 2 },
                exit = fadeOut() + slideOutVertically { -it / 2 },
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(start = ScreenPadding, end = ScreenPadding, top = 8.dp),
            ) {
                CompactSummary(funds, prefs)
            }
        }
    }
}

@Composable
private fun HeroCard(funds: List<Fund>, prefs: Prefs) {
    val stats = if (prefs.heroShowsCum) funds.cumStats() else funds.todayStats()
    val pct = stats?.pct ?: 0.0
    val color = if (stats == null) tierSecondary() else pctColor(pct)

    AppCard(padding = PaddingValues(horizontal = 20.dp, vertical = 18.dp)) {
        SecondaryText("总市值", style = MaterialTheme.typography.labelLarge)
        Spacer(Modifier.height(4.dp))
        MoneyText(
            value = funds.totalMv(),
            style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.SemiBold),
            color = MaterialTheme.colorScheme.onSurface,
        )

        Spacer(Modifier.height(16.dp))
        HorizontalDivider(
            thickness = 0.5.dp,
            color = MaterialTheme.colorScheme.outline.copy(alpha = 0.55f),
        )
        Spacer(Modifier.height(14.dp))

        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                SecondaryText(
                    if (prefs.heroShowsCum) "累计收益" else funds.dayLabel(),
                    style = MaterialTheme.typography.labelLarge,
                )
                Spacer(Modifier.height(4.dp))
                MoneyText(
                    value = stats?.profit ?: 0.0,
                    style = MaterialTheme.typography.titleLarge.tabular(),
                    color = color,
                )
                Text(
                    text = Fmt.pct(pct),
                    style = MaterialTheme.typography.bodyMedium.tabular(),
                    color = color,
                )
            }
            Row(
                modifier = Modifier
                    .clip(RoundedCornerShape(9.dp))
                    .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f))
                    .padding(3.dp),
            ) {
                MiniSeg("今日", !prefs.heroShowsCum) { FundStore.setHeroShowsCum(false) }
                MiniSeg("累计", prefs.heroShowsCum) { FundStore.setHeroShowsCum(true) }
            }
        }

        Spacer(Modifier.height(14.dp))
        SecondaryText(
            funds.insightLine() ?: "还没有持仓市值，添加基金并填写市值后显示洞察",
            style = MaterialTheme.typography.bodySmall,
        )
    }
}

@Composable
private fun MiniSeg(text: String, selected: Boolean, onClick: () -> Unit) {
    Surface(
        shape = RoundedCornerShape(7.dp),
        color = if (selected) MaterialTheme.colorScheme.surfaceContainer else Color.Transparent,
        modifier = Modifier.clip(RoundedCornerShape(7.dp)).clickable(onClick = onClick),
    ) {
        Text(
            text = text,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 5.dp),
            style = MaterialTheme.typography.labelLarge,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
            color = if (selected) MaterialTheme.colorScheme.onSurface else tierSecondary(),
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FundRowCard(
    fund: Fund,
    showHold: Boolean,
    onDetail: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
) {
    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            when (value) {
                SwipeToDismissBoxValue.StartToEnd -> { onEdit(); false }
                SwipeToDismissBoxValue.EndToStart -> { onDelete(); false }
                else -> false
            }
        },
    )

    SwipeToDismissBox(
        state = dismissState,
        modifier = Modifier.clip(RoundedCornerShape(AppCardRadius)),
        enableDismissFromStartToEnd = true,
        enableDismissFromEndToStart = true,
        backgroundContent = {
            val dir = dismissState.dismissDirection
            val bg = when (dir) {
                SwipeToDismissBoxValue.StartToEnd -> MaterialTheme.colorScheme.primary
                SwipeToDismissBoxValue.EndToStart -> Color(0xFFD70015)
                else -> Color.Transparent
            }
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .clip(RoundedCornerShape(AppCardRadius))
                    .background(bg)
                    .padding(horizontal = 24.dp),
                contentAlignment = if (dir == SwipeToDismissBoxValue.StartToEnd)
                    Alignment.CenterStart else Alignment.CenterEnd,
            ) {
                if (dir != SwipeToDismissBoxValue.Settled) {
                    Icon(
                        imageVector = if (dir == SwipeToDismissBoxValue.StartToEnd)
                            Icons.Default.Edit else Icons.Default.Delete,
                        contentDescription = null,
                        tint = Color.White,
                    )
                }
            }
        },
    ) {
        AppCard(onClick = onDetail) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(
                        text = fund.name,
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 1,
                    )
                    Spacer(Modifier.height(3.dp))
                    SecondaryText(
                        fund.code + if (fund.time != "--:--") "  ·  净值日 ${fund.time}" else "",
                        style = MaterialTheme.typography.labelMedium,
                    )
                }
                Column(horizontalAlignment = Alignment.End) {
                    if (showHold) {
                        MoneyText(
                            value = fund.mv,
                            style = MaterialTheme.typography.titleMedium.tabular(),
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                    }
                    Spacer(Modifier.height(3.dp))
                    Text(
                        text = Fmt.pct(fund.estPct),
                        style = MaterialTheme.typography.bodyMedium.tabular(),
                        color = pctColor(fund.estPct),
                    )
                }
            }
        }
    }
}

/** 滚动收纳：与列表同宽、同圆角、同边距的悬浮小计。 */
@Composable
private fun CompactSummary(funds: List<Fund>, prefs: Prefs) {
    val stats = if (prefs.heroShowsCum) funds.cumStats() else funds.todayStats()
    val pct = stats?.pct ?: 0.0
    AppCard(padding = PaddingValues(horizontal = 16.dp, vertical = 10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                SecondaryText("总市值", style = MaterialTheme.typography.labelSmall)
                MoneyText(
                    value = funds.totalMv(),
                    style = MaterialTheme.typography.titleMedium.tabular(),
                    color = MaterialTheme.colorScheme.onSurface,
                )
            }
            Column(horizontalAlignment = Alignment.End) {
                SecondaryText(
                    if (prefs.heroShowsCum) "累计" else "净值日",
                    style = MaterialTheme.typography.labelSmall,
                )
                Text(
                    text = Fmt.pct(pct),
                    style = MaterialTheme.typography.titleSmall.tabular(),
                    color = if (stats == null) tierSecondary() else pctColor(pct),
                )
            }
        }
    }
}

@Composable
private fun EmptyCard(onAdd: () -> Unit) {
    AppCard {
        Text(
            "还没有基金",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurface,
        )
        Spacer(Modifier.height(6.dp))
        SecondaryText("点右下角 + 添加第一只基金，输入 6 位代码即可离线识别名称。")
        Spacer(Modifier.height(12.dp))
        Text(
            "添加基金",
            modifier = Modifier.clickable(onClick = onAdd),
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.primary,
        )
    }
}

@Composable
private fun SourceNote() {
    SecondaryText(
        "净值来自天天基金公开数据 · 仅供个人记账参考，不构成投资建议",
        modifier = Modifier.padding(horizontal = 4.dp, vertical = 4.dp),
        style = MaterialTheme.typography.labelSmall,
    )
}
