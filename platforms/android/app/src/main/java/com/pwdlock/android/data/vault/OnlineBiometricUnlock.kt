package com.pwdlock.android.data.vault

import android.content.Context
import android.os.Build
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.util.Base64
import androidx.annotation.RequiresApi
import com.pwdlock.android.crypto.BiometricKeystore
import com.pwdlock.android.data.network.ApiException
import com.pwdlock.android.data.online.OnlineAccountStore
import com.pwdlock.android.util.BiometricAuth
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * 在线模式指纹解锁编排：与本地 [BiometricUnlock] 同构、但**完全隔离**——
 * - 独立 Keystore alias（[BiometricKeystore.ALIAS_ONLINE]）；
 * - 独立密文存储（[OnlineAccountStore]，加密 EncryptedSharedPreferences）；
 * - 独立在线解锁入口（[VaultSession.unlockOnlineWithVaultKey]：跳过主密码解 envelope，
 *   直接以解出的 vaultKey 进在线会话并后台同步）。
 *
 * 本地/在线主密码本质都是「解出同一把 32 字节 vaultKey 的口令」，故指纹机制同构：
 * 用 Keystore 硬件密钥（要求指纹认证）加密 vaultKey 存盘，解锁时指纹认证解出 vaultKey 进会话。
 * 登出时在线 bio 字段随 [OnlineAccountStore.clear] 一并清除。
 */
object OnlineBiometricUnlock {
    // 解锁入口是 suspend（VaultSession.unlockOnlineWithVaultKey 内部做 IO 同步），
    // 而 BiometricAuth 回调在主线程，故用一个 IO 作用域桥接。
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** 设备支持指纹且系统 API 满足。 */
    fun deviceSupported(context: Context): Boolean = BiometricAuth.isAvailable(context)

    /** 已启用且存在可用密文、云端已有保险库时，可在解锁页提供指纹入口。 */
    fun canOfferUnlock(context: Context): Boolean =
        !OnlineAccountStore.vaultId(context).isBlank() &&
            OnlineAccountStore.hasBiometric(context) &&
            deviceSupported(context)

    fun isEnabled(context: Context): Boolean = OnlineAccountStore.bioEnabled(context)

    /**
     * 启用在线指纹解锁：要求当前已在线解锁（内存有 vaultKey 且 onlineMode=true）。
     * 指纹认证后用独立 Keystore 密钥加密 vaultKey，密文存于 [OnlineAccountStore]。
     */
    @RequiresApi(Build.VERSION_CODES.P)
    fun enable(
        context: Context,
        onDone: () -> Unit,
        onError: (String) -> Unit,
        onCancel: () -> Unit,
    ) {
        val vaultKey = VaultSession.vaultKey
        if (vaultKey == null || !VaultSession.onlineMode) {
            onError("请先解锁在线密码库再开启指纹")
            return
        }
        val cipher = try {
            BiometricKeystore.encryptCipher(BiometricKeystore.ALIAS_ONLINE)
        } catch (e: Exception) {
            onError("无法创建安全密钥：${e.message}")
            return
        }
        BiometricAuth.authenticate(
            context = context,
            title = "开启指纹解锁",
            subtitle = "用指纹保护你的在线密码库",
            cipher = cipher,
            onSuccess = { authed ->
                try {
                    val ciphertext = authed.doFinal(vaultKey)
                    OnlineAccountStore.saveBiometric(
                        context,
                        Base64.encodeToString(ciphertext, Base64.NO_WRAP),
                        Base64.encodeToString(authed.iv, Base64.NO_WRAP),
                    )
                    onDone()
                } catch (e: Exception) {
                    onError("保存失败：${e.message}")
                }
            },
            onError = onError,
            onCancel = onCancel,
        )
    }

    /** 关闭在线指纹解锁：删除独立 Keystore 密钥并清在线密文。 */
    fun disable(context: Context) {
        BiometricKeystore.deleteKey(BiometricKeystore.ALIAS_ONLINE)
        OnlineAccountStore.clearBiometric(context)
    }

    /**
     * 在线指纹解锁：认证后解出 vaultKey，调 [VaultSession.unlockOnlineWithVaultKey] 进在线会话。
     * 指纹变更导致密钥失效时自动关闭指纹并提示改用主密码。
     */
    @RequiresApi(Build.VERSION_CODES.P)
    fun unlock(
        context: Context,
        onSuccess: () -> Unit,
        onError: (String) -> Unit,
        onCancel: () -> Unit,
        onAuthExpired: () -> Unit = {},
    ) {
        if (OnlineAccountStore.vaultId(context).isBlank()) {
            onError("无在线保险库，请用主密码解锁")
            return
        }
        val ctB64 = OnlineAccountStore.bioCiphertext(context)
        val ivB64 = OnlineAccountStore.bioIv(context)
        if (ctB64.isNullOrBlank() || ivB64.isNullOrBlank()) {
            onError("尚未开启指纹解锁")
            return
        }
        val iv = Base64.decode(ivB64, Base64.NO_WRAP)
        val ciphertext = Base64.decode(ctB64, Base64.NO_WRAP)
        val cipher = try {
            BiometricKeystore.decryptCipher(iv, BiometricKeystore.ALIAS_ONLINE)
        } catch (_: KeyPermanentlyInvalidatedException) {
            disable(context)
            onError("检测到指纹变更，请用主密码解锁")
            return
        } catch (e: Exception) {
            onError("指纹密钥不可用：${e.message}")
            return
        }
        BiometricAuth.authenticate(
            context = context,
            title = "指纹解锁",
            subtitle = "验证指纹以解锁在线密码库",
            cipher = cipher,
            onSuccess = { authed ->
                scope.launch {
                    try {
                        val vaultKey = authed.doFinal(ciphertext)
                        // 进入在线会话（内部含 ensureDevice + 后台全量同步），不抛异常即视为成功。
                        VaultSession.unlockOnlineWithVaultKey(context, vaultKey)
                        withContext(Dispatchers.Main) { onSuccess() }
                    } catch (e: ApiException.TokenExpired) {
                        // 登录已过期：会话已在内部清账户态，交由调用方跳登录页。
                        withContext(Dispatchers.Main) { onAuthExpired() }
                    } catch (e: Exception) {
                        // 其他异常（含 vaultKey 解出但后续会话初始化/同步抛错）：自动关闭指纹回退主密码。
                        runCatching { disable(context) }
                        withContext(Dispatchers.Main) {
                            onError("指纹解锁失败：${e.message ?: e.javaClass.simpleName}")
                        }
                    }
                }
            },
            onError = onError,
            onCancel = onCancel,
        )
    }
}
