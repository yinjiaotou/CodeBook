package com.pwdlock.android.screen

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import com.pwdlock.android.ui.components.PwdlockButton
import com.pwdlock.android.ui.components.PwdlockTopBar
import com.pwdlock.android.ui.theme.PwdlockColors
import com.pwdlock.android.ui.theme.RadiusLG
import com.pwdlock.android.ui.theme.RadiusMD
import com.pwdlock.android.ui.theme.ScreenHMargin
import com.pwdlock.android.ui.theme.SpaceLG
import com.pwdlock.android.ui.theme.SpaceMD
import com.pwdlock.android.ui.theme.SpaceXL
import com.pwdlock.android.ui.theme.SpaceSM

private val GenPool = mapOf(
    'L' to "abcdefghijkmnpqrstuvwxyz",
    'U' to "ABCDEFGHJKMNPQRSTUVWXYZ",
    'D' to "23456789",
    'S' to "!@#\$%^&*",
)

private fun genPassword(len: Int, useUpper: Boolean, useLower: Boolean, useDigit: Boolean, useSymbol: Boolean): String {
    val pools = buildList {
        if (useLower) add(GenPool['L']!!)
        if (useUpper) add(GenPool['U']!!)
        if (useDigit) add(GenPool['D']!!)
        if (useSymbol) add(GenPool['S']!!)
    }
    if (pools.isEmpty()) return ""
    val all = pools.joinToString("")
    return (1..len).joinToString("") { all.random().toString() }
}

@Composable
fun PasswordGeneratorScreen(navController: NavHostController) {
    var length by remember { mutableFloatStateOf(16f) }
    var upper by remember { mutableStateOf(true) }
    var lower by remember { mutableStateOf(true) }
    var digit by remember { mutableStateOf(true) }
    var symbol by remember { mutableStateOf(true) }
    var password by remember { mutableStateOf(genPassword(16, true, true, true, true)) }

    val clipboard = LocalClipboardManager.current

    fun regenerate() {
        password = genPassword(length.toInt(), upper, lower, digit, symbol)
    }

    Scaffold(
        topBar = { PwdlockTopBar(title = "密码生成器", onBack = { navController.popBackStack() }) },
    ) { inner ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(inner)
                .padding(horizontal = ScreenHMargin, vertical = SpaceXL),
            verticalArrangement = Arrangement.spacedBy(SpaceLG),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(RadiusLG))
                    .background(MaterialTheme.colorScheme.surfaceVariant)
                    .padding(SpaceLG),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = password,
                        style = MaterialTheme.typography.titleMedium.copy(fontFamily = FontFamily.Monospace),
                        color = MaterialTheme.colorScheme.onSurface,
                        textAlign = TextAlign.Start,
                        modifier = Modifier.weight(1f),
                    )
                    IconButton(onClick = { regenerate() }) {
                        Icon(Icons.Filled.Refresh, contentDescription = "重新生成")
                    }
                    IconButton(onClick = { clipboard.setText(AnnotatedString(password)) }) {
                        Icon(Icons.Filled.ContentCopy, contentDescription = "复制")
                    }
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(SpaceSM)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text("长度", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurface)
                    Text("${length.toInt()}", style = MaterialTheme.typography.bodyLarge, color = PwdlockColors.Brand)
                }
                Slider(
                    value = length,
                    onValueChange = {
                        length = it
                        regenerate()
                    },
                    valueRange = 8f..32f,
                    steps = 23,
                )
            }

            ToggleRow("大写字母 (A-Z)", upper) { upper = it; regenerate() }
            ToggleRow("小写字母 (a-z)", lower) { lower = it; regenerate() }
            ToggleRow("数字 (0-9)", digit) { digit = it; regenerate() }
            ToggleRow("符号 (!@#\$%^&*)", symbol) { symbol = it; regenerate() }

            Spacer(modifier = Modifier.weight(1f))
            PwdlockButton(
                text = "复制密码",
                onClick = { clipboard.setText(AnnotatedString(password)) },
                enabled = password.isNotEmpty(),
            )
        }
    }
}

@Composable
private fun ToggleRow(label: String, checked: Boolean, onToggle: (Boolean) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurface)
        Switch(checked = checked, onCheckedChange = onToggle)
    }
}
