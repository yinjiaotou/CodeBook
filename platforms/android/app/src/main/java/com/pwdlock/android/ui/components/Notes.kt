package com.pwdlock.android.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Info
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.pwdlock.android.ui.theme.PwdlockColors
import com.pwdlock.android.ui.theme.RadiusMD
import com.pwdlock.android.ui.theme.SpaceLG
import com.pwdlock.android.ui.theme.SpaceMD

enum class NoteTone { Info, Warning, Danger }

@Composable
fun AccentNote(
    icon: ImageVector,
    tone: NoteTone,
    title: String,
    text: String,
) {
    val container = when (tone) {
        NoteTone.Info -> PwdlockColors.BrandContainer
        NoteTone.Warning -> PwdlockColors.WarningContainer
        NoteTone.Danger -> PwdlockColors.DangerContainer
    }
    val content = when (tone) {
        NoteTone.Info -> PwdlockColors.OnBrandContainer
        NoteTone.Warning -> PwdlockColors.Warning
        NoteTone.Danger -> PwdlockColors.Danger
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(RadiusMD))
            .background(container)
            .padding(SpaceLG),
        verticalAlignment = Alignment.Top,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = content,
            modifier = Modifier.size(20.dp),
        )
        Column(modifier = Modifier.padding(start = SpaceMD)) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge,
                color = content,
            )
            Text(
                text = text,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** 便捷调用：信息类提示 */
@Composable
fun InfoNote(title: String, text: String) {
    AccentNote(Icons.Filled.Info, NoteTone.Info, title, text)
}
