package com.pwdlock.android.util

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Handler
import android.os.Looper

/**
 * 剪贴板工具：复制后 30 秒自动清空，避免敏感凭据长期驻留剪贴板。
 */
object ClipboardUtil {
    private const val CLEAR_DELAY_MS = 30_000L
    private val handler = Handler(Looper.getMainLooper())

    fun copy(context: Context, text: String) {
        val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.setPrimaryClip(ClipData.newPlainText("pwdlock", text))
        handler.removeCallbacksAndMessages(null)
        handler.postDelayed({
            cm.setPrimaryClip(ClipData.newPlainText("pwdlock", ""))
        }, CLEAR_DELAY_MS)
    }
}
