package com.pwdlock.android.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.pwdlock.android.data.model.ConflictGroup
import com.pwdlock.android.data.model.VaultItem
import com.pwdlock.android.ui.theme.AvatarSize
import com.pwdlock.android.ui.theme.PwdlockColors
import com.pwdlock.android.ui.theme.RadiusMD
import com.pwdlock.android.ui.theme.SpaceLG
import com.pwdlock.android.ui.theme.SpaceMD
import com.pwdlock.android.ui.theme.SpaceSM

private val AvatarPalette = listOf(
    PwdlockColors.Brand,
    PwdlockColors.Success,
    PwdlockColors.Warning,
    Color(0xFF9B6BF6),
    Color(0xFF39C5BB),
    Color(0xFFE579B0),
)

fun avatarColorFor(title: String): Color {
    val h = title.hashCode().let { if (it == Int.MIN_VALUE) 0 else kotlin.math.abs(it) }
    return AvatarPalette[h % AvatarPalette.size]
}

@Composable
fun ItemAvatar(title: String, size: androidx.compose.ui.unit.Dp = AvatarSize) {
    val char = title.firstOrNull()?.uppercase() ?: "#"
    Box(
        modifier = Modifier
            .size(size)
            .clip(RoundedCornerShape(14.dp))
            .background(avatarColorFor(title)),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = char,
            style = MaterialTheme.typography.titleMedium,
            color = Color.White,
        )
    }
}

@Composable
fun VaultItemRow(
    item: VaultItem,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    trailing: (@Composable () -> Unit)? = null,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = SpaceLG, vertical = SpaceMD),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ItemAvatar(title = item.title)
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(start = SpaceMD),
            verticalArrangement = Arrangement.Center,
        ) {
            Text(
                text = item.title,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (item.username.isNotBlank()) {
                Text(
                    text = item.username,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        trailing?.invoke()
    }
}

@Composable
fun SettingRow(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    trailing: (@Composable () -> Unit)? = null,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = SpaceLG, vertical = SpaceMD),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.Center,
        ) {
            Text(
                text = label,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurface,
            )
            if (!subtitle.isNullOrBlank()) {
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        trailing?.invoke()
    }
}

@Composable
fun SummaryRow(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    highlight: Boolean = false,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = SpaceLG, vertical = SpaceSM),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.weight(1f),
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyLarge,
            color = if (highlight) PwdlockColors.Danger else MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
fun ConflictCard(
    group: ConflictGroup,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(RadiusMD),
        color = MaterialTheme.colorScheme.surface,
        tonalElevation = 0.dp,
        shadowElevation = 0.dp,
    ) {
        Column(modifier = Modifier.padding(SpaceLG)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = group.title,
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.weight(1f),
                )
                Surface(
                    shape = RoundedCornerShape(999.dp),
                    color = PwdlockColors.WarningContainer,
                ) {
                    Text(
                        text = "${group.variants.size} 个版本",
                        style = MaterialTheme.typography.labelMedium,
                        color = PwdlockColors.Warning,
                        modifier = Modifier.padding(horizontal = SpaceSM, vertical = 2.dp),
                    )
                }
            }
            group.variants.forEach { v ->
                Row(
                    modifier = Modifier.padding(top = SpaceSM),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = if (v.kind == "tombstone") "删除" else "保留",
                        style = MaterialTheme.typography.labelMedium,
                        color = if (v.kind == "tombstone") PwdlockColors.Danger else PwdlockColors.Success,
                        modifier = Modifier.padding(end = SpaceSM),
                    )
                    Text(
                        text = "${v.sourceLabel} · ${v.subtitle}",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}
