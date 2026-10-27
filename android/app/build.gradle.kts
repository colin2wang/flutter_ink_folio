plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.inkscreen.reader"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // 墨水屏阅读器应用 ID
        applicationId = "com.inkscreen.reader"
        // 墨水屏设备普遍 Android 7~11；minSdk 跟随 Flutter 引擎下限（3.41 为 24）
        minSdk = flutter.minSdkVersion
        // targetSdk 保持 34，避开 Android 13+ 细粒度媒体权限对电子书文件读取的影响
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // 先用 debug 签名方便自测；上架前换正式签名
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}
