package com.pwdlock.android.util

import android.content.Context
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.hardware.fingerprint.FingerprintManager
import android.os.Build
import android.os.CancellationSignal
import androidx.annotation.RequiresApi
import com.pwdlock.android.crypto.BiometricKeystore
import javax.crypto.Cipher

/**
 * 系统生物识别（指纹）认证封装。使用框架 `android.hardware.biometrics.BiometricPrompt`
 * （API 28+），无需 androidx.biometric 依赖，也无需 FragmentActivity。
 */
object BiometricAuth {

    /** 设备是否可用指纹（硬件存在 + 已录入 + 系统支持）。 */
    fun isAvailable(context: Context): Boolean {
        if (!BiometricKeystore.isSupportedApi()) return false
        return try {
            when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.R -> {
                    val bm = context.getSystemService(BiometricManager::class.java)
                    bm != null && bm.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG) ==
                        BiometricManager.BIOMETRIC_SUCCESS
                }
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q -> {
                    val bm = context.getSystemService(BiometricManager::class.java)
                    @Suppress("DEPRECATION")
                    bm != null && bm.canAuthenticate() == BiometricManager.BIOMETRIC_SUCCESS
                }
                else -> {
                    @Suppress("DEPRECATION")
                    val fm = context.getSystemService(FingerprintManager::class.java)
                    @Suppress("DEPRECATION")
                    fm != null && fm.isHardwareDetected && fm.hasEnrolledFingerprints()
                }
            }
        } catch (_: Exception) {
            false
        }
    }

    /**
     * 弹出系统指纹认证，绑定 [cipher]（CryptoObject）。
     * 认证成功后回调已授权的 Cipher，可直接 doFinal。
     */
    @RequiresApi(Build.VERSION_CODES.P)
    fun authenticate(
        context: Context,
        title: String,
        subtitle: String,
        cipher: Cipher,
        onSuccess: (Cipher) -> Unit,
        onError: (String) -> Unit,
        onCancel: () -> Unit,
    ) {
        val executor = context.mainExecutor
        val prompt = BiometricPrompt.Builder(context)
            .setTitle(title)
            .setSubtitle(subtitle)
            .setNegativeButton("取消", executor) { _, _ -> onCancel() }
            .build()

        val cancellationSignal = CancellationSignal()
        prompt.authenticate(
            BiometricPrompt.CryptoObject(cipher),
            cancellationSignal,
            executor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    val authed = result.cryptoObject?.cipher
                    if (authed != null) onSuccess(authed) else onError("认证结果无效")
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    // 取消（负按钮）已由 setNegativeButton 回调处理；此处只区分用户取消与真实错误。
                    when (errorCode) {
                        BiometricPrompt.BIOMETRIC_ERROR_USER_CANCELED,
                        BiometricPrompt.BIOMETRIC_ERROR_CANCELED -> onCancel()
                        else -> onError(errString.toString())
                    }
                }

                override fun onAuthenticationFailed() {
                    // 单次不匹配，系统会提示重试，这里不终止
                }
            },
        )
    }
}
