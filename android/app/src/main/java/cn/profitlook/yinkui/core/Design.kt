package cn.profitlook.yinkui.core

import android.provider.Settings
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.abs

/** 与 iOS 封版一致：全 App 容器卡统一 14dp 圆角、16dp 外边距。 */
val AppCardRadius = 14.dp
val ScreenPadding = 16.dp
val CardGap = 12.dp

private val RedLight = Color(0xFFFF3B30)
private val RedDark = Color(0xFFFF453A)
private val GreenLight = Color(0xFF34C759)
private val GreenDark = Color(0xFF30D158)

private val LightScheme = lightColorScheme(
    primary = Color(0xFF0A84FF),
    onPrimary = Color.White,
    background = Color(0xFFF2F2F7),
    onBackground = Color(0xFF1C1C1E),
    surface = Color.White,
    onSurface = Color(0xFF1C1C1E),
    surfaceContainer = Color.White,
    surfaceContainerLow = Color(0xFFF7F7F9),
    surfaceVariant = Color(0xFFE9E9ED),
    onSurfaceVariant = Color(0xFF6E6E73),
    outline = Color(0xFFD1D1D6),
    error = Color(0xFFD70015),
)

private val DarkScheme = darkColorScheme(
    primary = Color(0xFF0A84FF),
    onPrimary = Color.White,
    background = Color(0xFF000000),
    onBackground = Color(0xFFF2F2F7),
    surface = Color(0xFF1C1C1E),
    onSurface = Color(0xFFF2F2F7),
    surfaceContainer = Color(0xFF1C1C1E),
    surfaceContainerLow = Color(0xFF141416),
    surfaceVariant = Color(0xFF2C2C2E),
    onSurfaceVariant = Color(0xFF98989F),
    outline = Color(0xFF48484A),
    error = Color(0xFFFF453A),
)

data class AppUi(
    val dark: Boolean = false,
    val highContrast: Boolean = false,
    val scheme: String = "cn",
    val hidden: Boolean = false,
)

/** 收紧的全局排版：只压行高（M3 默认 1.33~1.5 倍 → 约 1.2~1.3 倍），字号/字重/字距全部保持 M3 默认。 */
private val CompactTypography: Typography = run {
    val d = Typography()
    d.copy(
        headlineMedium = d.headlineMedium.copy(lineHeight = 34.sp),
        headlineSmall = d.headlineSmall.copy(lineHeight = 29.sp),
        titleLarge = d.titleLarge.copy(lineHeight = 26.sp),
        titleMedium = d.titleMedium.copy(lineHeight = 20.sp),
        titleSmall = d.titleSmall.copy(lineHeight = 18.sp),
        bodyLarge = d.bodyLarge.copy(lineHeight = 20.sp),
        bodyMedium = d.bodyMedium.copy(lineHeight = 18.sp),
        bodySmall = d.bodySmall.copy(lineHeight = 15.sp),
        labelLarge = d.labelLarge.copy(lineHeight = 18.sp),
        labelMedium = d.labelMedium.copy(lineHeight = 15.sp),
        labelSmall = d.labelSmall.copy(lineHeight = 14.sp),
    )
}

val LocalAppUi = staticCompositionLocalOf { AppUi() }

@Composable
private fun rememberHighContrast(): Boolean {
    val ctx = LocalContext.current
    return remember(ctx) {
        try {
            Settings.Secure.getInt(ctx.contentResolver, "high_text_contrast_enabled", 0) == 1
        } catch (e: Exception) {
            false
        }
    }
}

@Composable
fun AppTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val high = rememberHighContrast()
    val prefs by FundStore.prefs.collectAsState()
    val ui = AppUi(dark, high, prefs.scheme, prefs.hideAmounts)
    CompositionLocalProvider(LocalAppUi provides ui) {
        MaterialTheme(
            colorScheme = if (dark) DarkScheme else LightScheme,
            typography = CompactTypography,
            content = content,
        )
    }
}

/** 次级文字四上下文：默认浅 / 增强对比浅 / 默认深 / 增强对比深，均达 WCAG AA。 */
@Composable
fun tierSecondary(): Color {
    val ui = LocalAppUi.current
    return when {
        ui.dark && ui.highContrast -> Color(0xFFB0B0B5)
        ui.dark -> Color(0xFF98989F)
        ui.highContrast -> Color(0xFF5A5A5F)
        else -> Color(0xFF6E6E73)
    }
}

/** 涨跌色保持系统语义原色（与 iOS 封版一致），只随深浅外观切换。 */
@Composable
fun upColor(): Color {
    val ui = LocalAppUi.current
    val red = if (ui.dark) RedDark else RedLight
    val green = if (ui.dark) GreenDark else GreenLight
    return if (ui.scheme == "cn") red else green
}

@Composable
fun downColor(): Color {
    val ui = LocalAppUi.current
    val red = if (ui.dark) RedDark else RedLight
    val green = if (ui.dark) GreenDark else GreenLight
    return if (ui.scheme == "cn") green else red
}

@Composable
fun pctColor(p: Double): Color = when {
    abs(p) < 0.005 -> tierSecondary()
    p > 0 -> upColor()
    else -> downColor()
}

/** 等宽数字（tabular figures）：刷新时金额不左右跳动。 */
fun TextStyle.tabular(): TextStyle = copy(
    fontFamily = FontFamily.Default,
    fontFeatureSettings = "tnum",
)

/** 全 App 唯一卡片容器：宽、圆角、底色全部统一，杜绝头卡与列表对不齐。 */
@Composable
fun AppCard(
    modifier: Modifier = Modifier,
    padding: PaddingValues = PaddingValues(16.dp),
    onClick: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val shape = RoundedCornerShape(AppCardRadius)
    val base = Modifier
        .fillMaxWidth()
        .clip(shape)
        .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
    Surface(
        modifier = modifier.then(base),
        shape = shape,
        color = MaterialTheme.colorScheme.surfaceContainer,
        tonalElevation = 0.dp,
        shadowElevation = 0.dp,
    ) {
        Column(Modifier.padding(padding), content = content)
    }
}

/** 金额唯一展示出口：隐私态自动打码。 */
@Composable
fun MoneyText(
    value: Double,
    modifier: Modifier = Modifier,
    style: TextStyle = MaterialTheme.typography.bodyLarge,
    color: Color = Color.Unspecified,
    textAlign: TextAlign? = null,
) {
    val hidden = LocalAppUi.current.hidden
    Text(
        text = Fmt.money(value, hidden),
        modifier = modifier,
        style = style.tabular(),
        color = color,
        textAlign = textAlign,
        maxLines = 1,
    )
}

@Composable
fun SecondaryText(
    text: String,
    modifier: Modifier = Modifier,
    style: TextStyle = MaterialTheme.typography.bodySmall,
    textAlign: TextAlign? = null,
) {
    Text(
        text = text,
        modifier = modifier,
        style = style,
        color = tierSecondary(),
        textAlign = textAlign,
    )
}
