package cn.profitlook.yinkui.ui

import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import cn.profitlook.yinkui.core.AppCard
import cn.profitlook.yinkui.core.CardGap
import cn.profitlook.yinkui.core.Fmt
import cn.profitlook.yinkui.core.Fund
import cn.profitlook.yinkui.core.FundStore
import cn.profitlook.yinkui.core.HoldingRow
import cn.profitlook.yinkui.core.HoldingsResult
import cn.profitlook.yinkui.core.HoldingsService
import cn.profitlook.yinkui.core.MoneyText
import cn.profitlook.yinkui.core.ScreenPadding
import cn.profitlook.yinkui.core.SecondaryText
import cn.profitlook.yinkui.core.pctColor
import cn.profitlook.yinkui.core.tabular
import cn.profitlook.yinkui.core.tierSecondary

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DetailScreen(code: String, onBack: () -> Unit, onEdit: () -> Unit) {
    val funds by FundStore.funds.collectAsState()
    val fund = funds.find { it.code == code }
    var holdings by remember { mutableStateOf(HoldingsResult()) }
    var loading by remember { mutableStateOf(true) }

    LaunchedEffect(code) {
        loading = true
        holdings = HoldingsService.fetch(code)
        loading = false
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text(fund?.name ?: "基金详情", maxLines = 1) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                    }
                },
                actions = {
                    if (fund != null) {
                        TextButton(onClick = onEdit) { Text("编辑") }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(
                start = ScreenPadding, end = ScreenPadding, top = 8.dp, bottom = 40.dp,
            ),
            verticalArrangement = Arrangement.spacedBy(CardGap),
        ) {
            if (fund == null) {
                item {
                    AppCard { SecondaryText("该基金已被删除") }
                }
            } else {
                item { DetailSummaryCard(fund) }
            }

            item { HoldingsHeader(holdings, loading) }

            items(holdings.rows, key = { it.code }) { row ->
                HoldingRowCard(row)
            }

            item {
                SecondaryText(
                    "重仓股来自天天基金 F10 公开披露，按报告期列示，非实时持仓。",
                    modifier = Modifier.padding(horizontal = 4.dp),
                    style = MaterialTheme.typography.labelSmall,
                )
            }
        }
    }
}

@Composable
private fun DetailSummaryCard(fund: Fund) {
    val profit = fund.mv - fund.amount
    val profitPct = if (fund.amount > 0) profit / fund.amount * 100.0 else 0.0
    val hasCost = fund.amount > 0

    AppCard(padding = PaddingValues(horizontal = 20.dp, vertical = 18.dp)) {
        Text(
            fund.name,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurface,
        )
        Spacer(Modifier.height(2.dp))
        SecondaryText(fund.code, style = MaterialTheme.typography.labelLarge)

        Spacer(Modifier.height(16.dp))
        MoneyText(
            value = fund.mv,
            style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.SemiBold),
            color = MaterialTheme.colorScheme.onSurface,
        )
        Spacer(Modifier.height(4.dp))
        Text(
            text = "持有市值  ·  ${Fmt.pct(fund.estPct)}（${fund.time} 净值日）",
            style = MaterialTheme.typography.bodySmall.tabular(),
            color = pctColor(fund.estPct),
        )

        Spacer(Modifier.height(16.dp))
        HorizontalDivider(
            thickness = 0.5.dp,
            color = MaterialTheme.colorScheme.outline.copy(alpha = 0.55f),
        )
        Spacer(Modifier.height(6.dp))

        DataRow("最新单位净值", Fmt.nav(fund.estNav))
        DataRow("持有份额", if (fund.shares > 0) Fmt.num(fund.shares, 2) else "未填写")
        DataRow("持有成本", Fmt.money(fund.amount, false))
        if (hasCost) {
            DataRow("累计收益", "${Fmt.money(profit, false)}  (${Fmt.pct(profitPct)})", pctColor(profitPct))
        }

        if (fund.mv <= 0 && fund.amount <= 0) {
            Spacer(Modifier.height(8.dp))
            SecondaryText("还没填写持仓，点右上角「编辑」录入成本或市值。")
        }
    }
}

@Composable
private fun DataRow(label: String, value: String, valueColor: androidx.compose.ui.graphics.Color? = null) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SecondaryText(label, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium.tabular(),
            color = valueColor ?: MaterialTheme.colorScheme.onSurface,
        )
    }
}

@Composable
private fun HoldingsHeader(result: HoldingsResult, loading: Boolean) {
    AppCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(
                    "重仓股",
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Spacer(Modifier.height(3.dp))
                SecondaryText(
                    when {
                        loading -> "正在获取公开披露数据…"
                        result.ok -> listOfNotNull(
                            result.period.takeIf { it.isNotEmpty() },
                            result.deadline.takeIf { it.isNotEmpty() }?.let { "截止 $it" },
                        ).joinToString(" · ")
                        else -> "暂无重仓股数据"
                    },
                    style = MaterialTheme.typography.labelMedium,
                )
            }
            if (loading) {
                CircularProgressIndicator(
                    modifier = Modifier.padding(4.dp),
                    strokeWidth = 2.dp,
                )
            }
        }
    }
}

@Composable
private fun HoldingRowCard(row: HoldingRow) {
    AppCard(padding = PaddingValues(horizontal = 16.dp, vertical = 13.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(
                    row.name,
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                )
                Spacer(Modifier.height(2.dp))
                SecondaryText(row.code, style = MaterialTheme.typography.labelSmall)
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    "占净值 ${Fmt.num(row.pct)}%",
                    style = MaterialTheme.typography.bodyMedium.tabular(),
                    color = tierSecondary(),
                )
                row.chg?.let { chg ->
                    Spacer(Modifier.height(2.dp))
                    Text(
                        Fmt.pct(chg),
                        style = MaterialTheme.typography.bodyMedium.tabular(),
                        color = pctColor(chg),
                    )
                }
            }
        }
    }
}
