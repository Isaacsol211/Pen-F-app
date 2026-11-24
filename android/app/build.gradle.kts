plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.apexcommerce.shutterlink"
    compileSdk = 36
    buildToolsVersion = "36.0.0"

    defaultConfig {
        // Same identifier as the iOS app.
        applicationId = "com.apexcommerce.shutterlink"
        // Android 10: WifiNetworkSpecifier (joining the camera's Wi-Fi from the app) and
        // MediaStore saving without a storage permission.
        minSdk = 29
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            // OkHttp ships its own consumer rules; nothing app-specific is reflected on.
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2025.12.01")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    // Frozen at 1.7.8 (no longer in the BOM); vectors only.
    implementation("androidx.compose.material:material-icons-extended:1.7.8")

    implementation("androidx.core:core-ktx:1.17.0")
    implementation("androidx.activity:activity-compose:1.12.2")
    implementation("androidx.lifecycle:lifecycle-process:2.9.4")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")

    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    // Scene suggestions: Google's on-device image labeling with the model bundled in the app
    // (about 5.7 MB; no Google Play services, nothing leaves the phone).
    implementation("com.google.mlkit:image-labeling:17.0.9")

    // Scanning the camera's Wi-Fi QR code: Google's code scanner, which runs in Google Play services
    // (its own camera screen, so the app needs no camera permission). Without Play services the
    // network name and password are typed instead.
    implementation("com.google.android.gms:play-services-code-scanner:16.1.0")
}
