import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties (NOT committed, see .gitignore and
// docs/ANDROID.md). Without it a release build fails, unless
// -PallowDebugSigningForRelease=true is passed for a local release check.
val keyProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKey = keyProperties.getProperty("storeFile") != null
// Passwords are normally NOT stored on disk: tool/android/build_release.ps1
// asks for them and passes DET_STORE_PASSWORD to this build only.
val releaseStorePassword: String? =
    keyProperties.getProperty("storePassword") ?: System.getenv("DET_STORE_PASSWORD")
val releaseKeyPassword: String? =
    keyProperties.getProperty("keyPassword") ?: System.getenv("DET_KEY_PASSWORD") ?: releaseStorePassword
val allowDebugSigning =
    (project.findProperty("allowDebugSigningForRelease") as String?) == "true"

android {
    namespace = "com.bcr.dailyexpense"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Permanent product id. Updates must keep this id AND the signing key.
        applicationId = "com.bcr.dailyexpense"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = releaseStorePassword
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = when {
                hasReleaseKey -> signingConfigs.getByName("release")
                allowDebugSigning -> signingConfigs.getByName("debug")
                else -> null
            }
        }
    }
}

gradle.taskGraph.whenReady {
    val wantsRelease = allTasks.any { it.name.contains("Release") && it.project == project }
    if (wantsRelease && hasReleaseKey && releaseStorePassword.isNullOrEmpty()) {
        throw GradleException(
            "Keystore password not provided: build with tool/android/build_release.ps1 " +
                "(it asks for the password) or set DET_STORE_PASSWORD for this build.",
        )
    }
    if (wantsRelease && !hasReleaseKey && !allowDebugSigning) {
        throw GradleException(
            "Release signing key missing: create android/key.properties (see docs/ANDROID.md). " +
                "For a local, NOT-for-distribution release check pass -PallowDebugSigningForRelease=true.",
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Theme.AppCompat for local_auth on Android 8 and below (Google Maven, stable).
    implementation("androidx.appcompat:appcompat:1.8.0")
}

flutter {
    source = "../.."
}
