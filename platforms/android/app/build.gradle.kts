plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.pwdlock.android"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.pwdlock.android"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    // Compose BOM 锁定 Material3 / UI 版本
    implementation(platform("androidx.compose:compose-bom:2024.09.00"))

    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.4")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.4")
    // 前后台切换监听（自动锁定：切后台立即锁）。ProcessLifecycleOwner 所在包。
    implementation("androidx.lifecycle:lifecycle-process:2.8.4")
    implementation("androidx.activity:activity-compose:1.9.2")

    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.material3:material3-window-size-class")

    implementation("androidx.navigation:navigation-compose:2.8.0")

    // 加密核心：Argon2id（与 macOS phc-crypto 逐字节兼容）。
    // argon2kt 是 Android 专用 AAR，自带 bionic 原生库（libargon2jni.so），无桌面 glibc 依赖。
    // 以文件依赖引入，避免解析其 pom 中冗余的 appcompat 传递依赖；core-ktx 已在上方声明。
    implementation(files("libs/argon2kt-1.6.0.aar"))

    // 在线模式端到端加密所需的受审计密码学原语（minSdk 26 平台不提供）：
    // - Ed25519 设备签名密钥的生成 / 签名 / 验签
    // - HKDF-SHA256（从 Vault Key 派生变更加密密钥）
    implementation("org.bouncycastle:bcprov-jdk18on:1.78.1")

    // 在线账户态（访问令牌、设备签名私钥等）的本地加密存储，由 Android Keystore 主密钥保护。
    implementation("androidx.security:security-crypto:1.1.0-alpha06")

    debugImplementation("androidx.compose.ui:ui-tooling")
}
