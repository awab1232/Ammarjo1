plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // يجب تطبيق google-services بعد إضافة Android (مع Flutter) حتى يُعالَج `google-services.json`.
    id("com.google.gms.google-services")
}

import java.io.FileInputStream
import java.util.Properties

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
var releaseKeystoreReady = false
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    val storeFileName = keystoreProperties["storeFile"] as String?
    if (storeFileName != null) {
        val storeFile = rootProject.file(storeFileName)
        releaseKeystoreReady = storeFile.exists()
    }
}

android {
    namespace = "com.ammarjo.store"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // يجب أن يطابق package_name في android/app/google-services.json (حمّل الملف من Firebase بعد تسجيل التطبيق).
        // Phone Auth / Dynamic Links / بعض OAuth: أضف SHA-1 و SHA-256 لكل من:
        // debug keystore، release keystore (Play)، و Play App Signing في Firebase Console → Project settings → Your apps.
        applicationId = "com.ammarjo.store"
        minSdk = maxOf(flutter.minSdkVersion, 21)
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (releaseKeystoreReady) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storePassword = keystoreProperties["storePassword"] as String
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
            }
        }
    }

    buildTypes {
        release {
            // موقّع بمفتاح الإصدار عند وجود android/key.properties و upload-keystore.jks؛ وإلا يبقى debug للتطوير المحلي فقط.
            signingConfig = if (releaseKeystoreReady) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    implementation("com.google.android.material:material:1.12.0")

    // Firebase (رسمي): BoM يثبّت إصدارات مكتبات Firebase المتسقة مع بعضها.
    // حزم Flutter (firebase_core، firebase_auth، …) تضيف تعريفاتها؛ هذا يضمن طبقة أندرويد الأصلية متوافقة مع Console.
    implementation(platform("com.google.firebase:firebase-bom:34.12.0"))
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-analytics")
    // إشعارات FCM على مستوى الخدمة الأصلية (مع firebase_messaging من pubspec)
    implementation("com.google.firebase:firebase-messaging")
}
