package cn.profitlook.yinkui.ui

import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import cn.profitlook.yinkui.core.AppCard
import cn.profitlook.yinkui.core.CardGap
import cn.profitlook.yinkui.core.FundStore
import cn.profitlook.yinkui.core.ScreenPadding
import cn.profitlook.yinkui.core.SecondaryText
import cn.profitlook.yinkui.core.tierSecondary

private val intervals = listOf(
    0 to "关闭",
    30 to "每 30 秒",
    60 to "每 1 分钟",
    300 to "每 5 分钟",
    900 to "每 15 分钟",
    1800 to "每 30 分钟",
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(onBack: () -> Unit) {
    val prefs by FundStore.prefs.collectAsState()
    var showInterval by remember { mutableStateOf(false) }
    var showClear by remember { mutableStateOf(false) }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text("设置") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
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
            item { SectionLabel("外观与数值") }
            item {
                AppCard {
                    ChoiceRow(
                        title = "涨跌配色",
                        options = listOf("cn" to "红涨绿跌", "us" to "绿涨红跌"),
                        selected = prefs.scheme,
                        onSelect = { FundStore.setScheme(it) },
                    )
                    SoftDivider()
                    SwitchRow(
                        title = "显示持有金额",
                        subtitle = "关闭后列表只显示名称与涨跌幅",
                        checked = prefs.showHold,
                        onChange = { FundStore.setShowHold(it) },
                    )
                    SoftDivider()
                    SwitchRow(
                        title = "隐藏所有金额",
                        subtitle = "隐私模式，金额统一打码、百分比保留",
                        checked = prefs.hideAmounts,
                        onChange = { FundStore.setHideAmounts(it) },
                    )
                }
            }

            item { SectionLabel("收益口径") }
            item {
                AppCard {
                    ChoiceRow(
                        title = "头卡默认展示",
                        options = listOf("today" to "今日 / 净值日", "cum" to "累计"),
                        selected = if (prefs.heroShowsCum) "cum" else "today",
                        onSelect = { FundStore.setHeroShowsCum(it == "cum") },
                    )
                }
            }

            item { SectionLabel("自动刷新") }
            item {
                AppCard {
                    ClickRow(
                        title = "刷新间隔",
                        trailing = intervals.firstOrNull { it.first == prefs.autoRefreshSecs }?.second ?: "关闭",
                        onClick = { showInterval = true },
                    )
                    SoftDivider()
                    SecondaryText(
                        "App 在前台时按此间隔自动获取最新净值；也可在主页手动下拉或点刷新按钮。",
                        style = MaterialTheme.typography.labelSmall,
                    )
                }
            }

            item { SectionLabel("数据") }
            item {
                AppCard {
                    ClickRow(
                        title = "清空所有基金",
                        trailing = "",
                        titleColor = MaterialTheme.colorScheme.error,
                        onClick = { showClear = true },
                    )
                }
            }

            item {
                AppCard {
                    Text(
                        "盈亏一眼 · Android 1.0.0",
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    Spacer(Modifier.height(6.dp))
                    SecondaryText(
                        "净值、重仓股来自天天基金公开数据，仅用于个人记账参考，不构成投资建议。" +
                            "所有持仓数据只保存在本机，无账号体系、无数据上传。",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
        }
    }

    if (showInterval) {
        AlertDialog(
            onDismissRequest = { showInterval = false },
            title = { Text("刷新间隔") },
            text = {
                Column {
                    intervals.forEach { (secs, label) ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(8.dp))
                                .clickable {
                                    FundStore.setAutoRefreshSecs(secs)
                                    showInterval = false
                                }
                                .padding(horizontal = 8.dp, vertical = 11.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                label,
                                modifier = Modifier.weight(1f),
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurface,
                            )
                            if (secs == prefs.autoRefreshSecs) {
                                Text("✓", color = MaterialTheme.colorScheme.primary)
                            }
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { showInterval = false }) { Text("取消") }
            },
        )
    }

    if (showClear) {
        AlertDialog(
            onDismissRequest = { showClear = false },
            title = { Text("清空所有基金？") },
            text = { Text("将移除全部持仓记录，此操作不可撤销。清空后列表保持为空，不会重新放入示例基金。") },
            confirmButton = {
                TextButton(onClick = {
                    FundStore.clear()
                    showClear = false
                }) { Text("清空", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { showClear = false }) { Text("取消") }
            },
        )
    }
}

@Composable
private fun SectionLabel(text: String) {
    SecondaryText(
        text,
        modifier = Modifier.padding(start = 4.dp, top = 4.dp),
        style = MaterialTheme.typography.labelLarge,
    )
}

@Composable
private fun SoftDivider() {
    Spacer(Modifier.height(12.dp))
    HorizontalDivider(
        thickness = 0.5.dp,
        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.45f),
    )
    Spacer(Modifier.height(12.dp))
}

@Composable
private fun SwitchRow(
    title: String,
    subtitle: String? = null,
    checked: Boolean,
    onChange: (Boolean) -> Unit,
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurface)
            if (subtitle != null) {
                Spacer(Modifier.height(2.dp))
                SecondaryText(subtitle, style = MaterialTheme.typography.labelSmall)
            }
        }
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

@Composable
private fun ChoiceRow(
    title: String,
    options: List<Pair<String, String>>,
    selected: String,
    onSelect: (String) -> Unit,
) {
    Column {
        Text(title, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurface)
        Spacer(Modifier.height(10.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            options.forEach { (key, label) ->
                val active = key == selected
                Surface(
                    shape = RoundedCornerShape(9.dp),
                    color = if (active) MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
                    else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f),
                    modifier = Modifier
                        .clip(RoundedCornerShape(9.dp))
                        .clickable { onSelect(key) },
                ) {
                    Text(
                        label,
                        modifier = Modifier.padding(horizontal = 14.dp, vertical = 7.dp),
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = if (active) FontWeight.SemiBold else FontWeight.Normal,
                        color = if (active) MaterialTheme.colorScheme.primary else tierSecondary(),
                    )
                }
            }
        }
    }
}

@Composable
private fun ClickRow(
    title: String,
    trailing: String,
    titleColor: Color = Color.Unspecified,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            title,
            modifier = Modifier.weight(1f),
            style = MaterialTheme.typography.bodyLarge,
            color = titleColor,
        )
        if (trailing.isNotEmpty()) {
            SecondaryText(trailing, style = MaterialTheme.typography.bodyMedium)
        }
    }
}
