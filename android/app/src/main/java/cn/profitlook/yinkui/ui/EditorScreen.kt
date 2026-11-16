package cn.profitlook.yinkui.ui

import android.widget.Toast
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import cn.profitlook.yinkui.core.AppCard
import cn.profitlook.yinkui.core.CardGap
import cn.profitlook.yinkui.core.Fmt
import cn.profitlook.yinkui.core.Fund
import cn.profitlook.yinkui.core.FundDB
import cn.profitlook.yinkui.core.FundStore
import cn.profitlook.yinkui.core.ScreenPadding
import cn.profitlook.yinkui.core.SecondaryText
import cn.profitlook.yinkui.core.tierSecondary

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditorScreen(
    code: String?,
    onClose: () -> Unit,
    onOpenExisting: ((String) -> Unit)? = null,
) {
    val context = LocalContext.current
    val funds by FundStore.funds.collectAsState()
    val existing = code?.let { c -> funds.find { it.code == c } }

    var codeText by remember { mutableStateOf(code ?: "") }
    var nameText by remember { mutableStateOf(existing?.name ?: "") }
    var costText by remember { mutableStateOf(existing?.amount?.takeIf { it > 0 }?.let { Fmt.num(it) } ?: "") }
    var mvText by remember { mutableStateOf(existing?.mv?.takeIf { it > 0 }?.let { Fmt.num(it) } ?: "") }
    var sharesText by remember { mutableStateOf(existing?.shares?.takeIf { it > 0 }?.let { Fmt.num(it) } ?: "") }
    var nameTouched by remember { mutableStateOf(false) }
    var hint by remember { mutableStateOf("输入 6 位代码，自动识别基金名称") }
    var hintOk by remember { mutableStateOf(false) }
    var showDelete by remember { mutableStateOf(false) }

    // 添加模式：输满 6 位离线查名；编辑模式保留用户自定义名称不覆盖。
    LaunchedEffect(codeText) {
        if (code != null || nameTouched) return@LaunchedEffect
        if (codeText.length == 6 && codeText.all { it.isDigit() }) {
            val found = FundDB.name(context, codeText)
            if (found != null) {
                nameText = found
                hint = "已识别：$found"
                hintOk = true
            } else {
                hint = "未收录该代码，请手动填写名称"
                hintOk = false
            }
        } else {
            hint = "输入 6 位代码，自动识别基金名称"
            hintOk = false
        }
    }

    fun save() {
        val c = codeText.trim()
        if (c.length != 6 || !c.all { it.isDigit() }) {
            Toast.makeText(context, "请输入 6 位基金代码", Toast.LENGTH_SHORT).show()
            return
        }
        val name = nameText.trim().ifEmpty { "未命名基金" }
        val cost = costText.toDoubleOrNull() ?: 0.0
        val mv = mvText.toDoubleOrNull() ?: 0.0
        val shares = sharesText.toDoubleOrNull() ?: 0.0

        if (existing == null) {
            if (funds.any { it.code == c }) {
                onOpenExisting?.invoke(c) ?: run {
                    Toast.makeText(context, "该基金已在列表中", Toast.LENGTH_SHORT).show()
                }
                return
            }
            FundStore.add(
                Fund(
                    code = c, name = name, estNav = 1.0, estPct = 0.0,
                    amount = cost, mv = mv, shares = shares, time = "--:--",
                )
            )
        } else {
            FundStore.update(c) {
                copy(name = name, amount = cost, mv = mv, shares = shares)
            }
        }
        onClose()
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text(if (existing == null) "添加基金" else "编辑基金") },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(Icons.Default.Close, contentDescription = "关闭")
                    }
                },
                actions = {
                    TextButton(onClick = { save() }) { Text("保存") }
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
            verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(CardGap),
        ) {
            item {
                FieldCard(
                    label = "基金代码",
                    value = codeText,
                    onValueChange = { codeText = it },
                    placeholder = "如 161725",
                    keyboardType = KeyboardType.Number,
                    enabled = existing == null,
                    digitsOnly = true,
                )
            }
            item {
                FieldCard(
                    label = "基金名称",
                    value = nameText,
                    onValueChange = { nameText = it; nameTouched = true },
                    placeholder = "自动识别，也可手动填写",
                )
            }
            item {
                FieldCard(
                    label = "持有金额（成本）",
                    value = costText,
                    onValueChange = { costText = it },
                    placeholder = "选填，0.00",
                    keyboardType = KeyboardType.Decimal,
                    decimalOnly = true,
                )
            }
            item {
                FieldCard(
                    label = "持有市值（当前）",
                    value = mvText,
                    onValueChange = { mvText = it },
                    placeholder = "选填，0.00",
                    keyboardType = KeyboardType.Decimal,
                    decimalOnly = true,
                )
            }
            item {
                FieldCard(
                    label = "持有份额",
                    value = sharesText,
                    onValueChange = { sharesText = it },
                    placeholder = "选填，填后市值自动按净值重算",
                    keyboardType = KeyboardType.Decimal,
                    decimalOnly = true,
                )
            }
            item {
                Text(
                    text = if (existing == null) hint
                    else "填了份额且有最新净值时，市值 = 份额 × 最新净值，随刷新自动重算。",
                    modifier = Modifier.padding(horizontal = 4.dp),
                    style = MaterialTheme.typography.bodySmall,
                    color = if (existing == null && hintOk) MaterialTheme.colorScheme.primary else tierSecondary(),
                )
            }
            if (existing != null) {
                item {
                    AppCard {
                        TextButton(onClick = { showDelete = true }) {
                            Text("删除此基金", color = MaterialTheme.colorScheme.error)
                        }
                    }
                }
            }
        }
    }

    if (showDelete && existing != null) {
        AlertDialog(
            onDismissRequest = { showDelete = false },
            title = { Text("删除此基金？") },
            text = { Text("将移除「${existing.name}」及其持仓记录，此操作不可撤销。") },
            confirmButton = {
                TextButton(onClick = {
                    FundStore.remove(existing.code)
                    showDelete = false
                    Toast.makeText(context, "已删除", Toast.LENGTH_SHORT).show()
                    onClose()
                }) { Text("删除", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { showDelete = false }) { Text("取消") }
            },
        )
    }
}

@Composable
private fun FieldCard(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    keyboardType: KeyboardType = KeyboardType.Text,
    enabled: Boolean = true,
    digitsOnly: Boolean = false,
    decimalOnly: Boolean = false,
) {
    AppCard(padding = PaddingValues(horizontal = 16.dp, vertical = 13.dp)) {
        SecondaryText(label, style = MaterialTheme.typography.labelMedium)
        Spacer(Modifier.height(8.dp))
        BasicTextField(
            value = value,
            onValueChange = { raw ->
                var v = raw
                if (digitsOnly) {
                    v = v.filter { it.isDigit() }.take(6)
                } else if (decimalOnly) {
                    v = v.filter { it.isDigit() || it == '.' }
                    val first = v.indexOf('.')
                    if (first >= 0) {
                        val second = v.indexOf('.', first + 1)
                        if (second >= 0) v = v.substring(0, second) + v.substring(second + 1).replace(".", "")
                    }
                }
                onValueChange(v)
            },
            enabled = enabled,
            modifier = Modifier.fillMaxWidth(),
            textStyle = MaterialTheme.typography.bodyLarge.copy(
                color = if (enabled) MaterialTheme.colorScheme.onSurface else tierSecondary(),
            ),
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
            cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
            decorationBox = { inner ->
                Box(contentAlignment = Alignment.CenterStart) {
                    if (value.isEmpty()) {
                        SecondaryText(placeholder, style = MaterialTheme.typography.bodyLarge)
                    }
                    inner()
                }
            },
        )
    }
}
