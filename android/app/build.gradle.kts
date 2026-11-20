import java.util.Properties
import groovy.json.JsonSlurper

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val videoAppBuild = providers.environmentVariable("VIDEO_MUSIC_BUILD").orNull == "1"
val videoVersion = if (videoAppBuild) {
    JsonSlurper().parse(rootProject.file("../ik-version.json")) as Map<*, *>
} else emptyMap<String, Any>()
val videoSigning = Properties().apply {
    if (videoAppBuild) {
        val propertiesPath = providers.environmentVariable("VIDEO_MUSIC_SIGNING_PROPERTIES").orNull
            ?: error("VIDEO_MUSIC_SIGNING_PROPERTIES must point to the video app signing configuration")
        file(propertiesPath).inputStream().use { load(it) }
    }
}

android {
    namespace = "com.mconnect.mconnect"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = if (videoAppBuild) "app.videomusic.player" else "com.mconnect.mconnect"
        manifestPlaceholders["appLabel"] = if (videoAppBuild) videoVersion["name"] as String else "Mconnect"
        manifestPlaceholders["flutterDeepLinkingEnabled"] = !videoAppBuild
        manifestPlaceholders["roundIcon"] = if (videoAppBuild) {
            "@mipmap/ic_launcher_round"
        } else {
            "@mipmap/ic_launcher"
        }
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = if (videoAppBuild) (videoVersion["build"] as Number).toInt() else flutter.versionCode
        versionName = if (videoAppBuild) videoVersion["version"] as String else flutter.versionName
    }

    if (videoAppBuild) {
        listOf("debug", "profile", "release").forEach { variant ->
            sourceSets.maybeCreate(variant).res.srcDir("src/yueyin/res")
        }
    }

    if (videoAppBuild) {
        signingConfigs.create("videoRelease") {
            storeFile = file(videoSigning.getProperty("storeFile"))
            storePassword = videoSigning.getProperty("storePassword")
            keyAlias = videoSigning.getProperty("keyAlias")
            keyPassword = videoSigning.getProperty("keyPassword")
            storeType = "PKCS12"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (videoAppBuild) "videoRelease" else "debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.documentfile:documentfile:1.0.1")
    implementation("androidx.javascriptengine:javascriptengine:1.1.1")
}
