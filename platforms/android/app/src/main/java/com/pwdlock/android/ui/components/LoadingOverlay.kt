package com.pwdlock.android.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.pwdlock.android.ui.theme.PwdlockColors
import com.pwdlock.android.ui.theme.SpaceMD

/**
 * 半透明遮罩 + 居中加载指示器，用于「处理中」场景（如导入、合并）。
 * 覆盖在父容器之上，阻止误触。
 */
@Composable
fun LoadingOverlay(text: String) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.45f)),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            CircularProgressIndicator(
                modifier = Modifier.size(46.dp),
                color = PwdlockColors.Brand,
                strokeWidth = 4.dp,
            )
            androidx.compose.foundation.layout.Spacer(modifier = Modifier.height(SpaceMD))
            Text(
                text = text,
                style = MaterialTheme.typography.bodyLarge,
                color = Color.White,
            )
        }
    }
}
