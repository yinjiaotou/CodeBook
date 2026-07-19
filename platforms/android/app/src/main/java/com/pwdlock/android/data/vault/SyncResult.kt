package com.pwdlock.android.data.vault

/**
 * 远端同步结果。
 *
 * - [SUCCESS]：同步成功（含「无变更」与「仅网络抖动、保持游标重试」）。
 * - [AUTH_EXPIRED]：登录令牌已失效（HTTP 401）。调用方应清账户态并跳回登录页重新登录。
 * - [TRANSPORT_ERROR]：网络 / 服务端临时错误，游标不变、下次重试，不影响已解锁会话。
 */
enum class OnlineSyncResult {
    SUCCESS,
    AUTH_EXPIRED,
    TRANSPORT_ERROR,
}
