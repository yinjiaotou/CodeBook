package com.pwdlock.android.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val LightColors = lightColorScheme(
    primary = PwdlockColors.Brand,
    onPrimary = Color.White,
    primaryContainer = PwdlockColors.BrandContainer,
    onPrimaryContainer = PwdlockColors.OnBrandContainer,
    secondary = PwdlockColors.Ink700,
    background = PwdlockColors.SurfaceBG,
    onBackground = PwdlockColors.Ink900,
    surface = PwdlockColors.Surface,
    onSurface = PwdlockColors.Ink900,
    surfaceVariant = PwdlockColors.SurfaceVariant,
    onSurfaceVariant = PwdlockColors.Ink700,
    outline = PwdlockColors.Divider,
    error = PwdlockColors.Danger,
    onError = Color.White,
    tertiary = PwdlockColors.Success,
)

private val DarkColors = darkColorScheme(
    primary = PwdlockColors.BrandDark,
    onPrimary = Color.White,
    primaryContainer = PwdlockColors.Brand,
    onPrimaryContainer = Color.White,
    secondary = PwdlockColors.Ink300,
    background = Color(0xFF0E1116),
    onBackground = Color.White,
    surface = Color(0xFF161B22),
    onSurface = Color.White,
    surfaceVariant = Color(0xFF1F2630),
    onSurfaceVariant = PwdlockColors.Ink300,
    outline = Color(0xFF2A313C),
    error = PwdlockColors.Danger,
    onError = Color.White,
    tertiary = PwdlockColors.Success,
)

@Composable
fun PwdlockTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        typography = Typography,
        content = content,
    )
}
