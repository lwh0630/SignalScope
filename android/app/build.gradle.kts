import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing material. It is never committed:
//  - CI provides it through environment variables (restored from GitHub Secrets);
//  - local builds can use `android/key.properties` (git-ignored), see README.
// Environment variables win over key.properties. Values are never printed.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.isFile) file.inputStream().use { load(it) }
}

fun signingValue(envName: String, propertyName: String): String? =
    System.getenv(envName)?.takeIf { it.isNotBlank() }
        ?: keyProperties.getProperty(propertyName)?.takeIf { it.isNotBlank() }

val releaseStoreFile: File? =
    signingValue("ANDROID_KEYSTORE_PATH", "storeFile")?.let { rootProject.file(it) }
val releaseStorePassword = signingValue("ANDROID_STORE_PASSWORD", "storePassword")
val releaseKeyPassword = signingValue("ANDROID_KEY_PASSWORD", "keyPassword")
val releaseKeyAlias = signingValue("ANDROID_KEY_ALIAS", "keyAlias")
val hasReleaseSigning =
    releaseStoreFile?.isFile == true &&
        releaseStorePassword != null &&
        releaseKeyPassword != null &&
        releaseKeyAlias != null

android {
    namespace = "com.signalscope.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.signalscope.app"
        // Android 10 (API 29) is the minimum: it is the first release with
        // requestCellInfoUpdate / CellIdentityNr / CellSignalStrengthNr.
        // compileSdk / targetSdk follow the Flutter default (currently API 36 / Android 16).
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // The `debug` config is created by AGP and left untouched.
        create("release") {
            if (hasReleaseSigning) {
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
                keyPassword = releaseKeyPassword
                keyAlias = releaseKeyAlias
            }
        }
    }

    buildTypes {
        release {
            // Release builds are always signed with the release key. There is
            // deliberately no fallback to the debug key (see the check below).
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

// Fail fast, with a clear message, when a release task is requested without
// complete signing material. Debug builds, tests and analysis are unaffected.
gradle.taskGraph.whenReady {
    val buildsRelease = allTasks.any { it.project == project && it.name.contains("Release") }
    if (buildsRelease && !hasReleaseSigning) {
        throw GradleException(
            "Release signing is not configured. Provide android/key.properties " +
                "(storeFile, storePassword, keyPassword, keyAlias) or the environment " +
                "variables ANDROID_KEYSTORE_PATH, ANDROID_STORE_PASSWORD, " +
                "ANDROID_KEY_PASSWORD and ANDROID_KEY_ALIAS, and make sure the keystore " +
                "file exists. Release builds never fall back to the debug key."
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
