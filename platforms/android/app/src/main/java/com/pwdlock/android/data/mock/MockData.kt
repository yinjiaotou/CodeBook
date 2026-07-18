package com.pwdlock.android.data.mock

import com.pwdlock.android.data.model.ConflictGroup
import com.pwdlock.android.data.model.ConflictVariant
import com.pwdlock.android.data.model.ImportSummary
import com.pwdlock.android.data.model.VaultItem

/**
 * 静态阶段示例数据。仅用于 UI 展示，不含任何真实凭据。
 */
object MockData {
    val categories = listOf("工作", "金融", "社交", "生活", "开发", "其他")

    val items = listOf(
        VaultItem(
            id = "i1", title = "GitHub", username = "octocat@me.com",
            password = "Tv7#kP9!mQ2x", url = "https://github.com",
            category = "开发", note = "个人开源账号", updatedAt = "2026-07-15",
        ),
        VaultItem(
            id = "i2", title = "招商银行", username = "6225 **** **** 8841",
            password = "Boc@2026!sec", url = "https://cmbchina.com",
            category = "金融", note = "网银登录", updatedAt = "2026-07-14",
        ),
        VaultItem(
            id = "i3", title = "微博", username = "weibo_cn_88",
            password = "We1bo#pass9", url = "https://weibo.com",
            category = "社交", note = "", updatedAt = "2026-07-11",
        ),
        VaultItem(
            id = "i4", title = "公司内网 VPN", username = "yin.teng",
            password = "Vpn@Cogmait#77", url = "https://vpn.cogmait.com",
            category = "工作", note = "仅办公网络", updatedAt = "2026-07-10",
        ),
        VaultItem(
            id = "i5", title = "Netflix", username = "stream_me@me.com",
            password = "Fl!x2026WATCH", url = "https://netflix.com",
            category = "生活", note = "", updatedAt = "2026-07-08",
        ),
        VaultItem(
            id = "i6", title = "AWS 控制台", username = "root+cogmait",
            password = "Aw5${'$'}Ro0tKluc", url = "https://console.aws.amazon.com",
            category = "开发", note = "MFA 已开启", updatedAt = "2026-07-05",
        ),
    )

    val conflictGroups = listOf(
        ConflictGroup(
            id = "c1", title = "GitHub",
            variants = listOf(
                ConflictVariant(
                    kind = "record", sourceVaultId = "v-local",
                    sourceLabel = "本机", title = "GitHub",
                    subtitle = "octocat@me.com", updatedAt = "2026-07-15 10:22",
                ),
                ConflictVariant(
                    kind = "record", sourceVaultId = "v-pixel",
                    sourceLabel = "Pixel 7", title = "GitHub",
                    subtitle = "octocat.work@me.com", updatedAt = "2026-07-15 09:10",
                ),
            ),
        ),
        ConflictGroup(
            id = "c2", title = "公司内网 VPN",
            variants = listOf(
                ConflictVariant(
                    kind = "record", sourceVaultId = "v-local",
                    sourceLabel = "本机", title = "公司内网 VPN",
                    subtitle = "yin.teng", updatedAt = "2026-07-10 18:40",
                ),
                ConflictVariant(
                    kind = "tombstone", sourceVaultId = "v-pixel",
                    sourceLabel = "Pixel 7", title = "公司内网 VPN",
                    subtitle = "已删除", updatedAt = "2026-07-12 21:05",
                ),
            ),
        ),
    )

    /** 导入预览摘要（静态展示用） */
    val importSummary = ImportSummary(
        added = 3,
        skipped = 18,
        conflict = conflictGroups.size,
        tombstone = 1,
        rejected = 0,
        totalRecords = 22,
    )
}
