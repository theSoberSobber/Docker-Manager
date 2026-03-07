import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.pavit.docker"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.pavit.docker"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            val keystorePropertiesFile = rootProject.file("keystore.properties")
            if (keystorePropertiesFile.exists()) {
                println("✅ Found keystore.properties file")
                val keystoreProperties = Properties().apply {
                    load(FileInputStream(keystorePropertiesFile))
                }

                val storeFilePath = keystoreProperties["storeFile"] as String
                val storeFileObj = file(storeFilePath)
                println("🔍 Looking for keystore at: ${storeFileObj.absolutePath}")
                println("🔍 Keystore exists: ${storeFileObj.exists()}")
                
                storeFile = storeFileObj
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                
                println("✅ Release signing config created successfully")
            } else {
                println("❌ keystore.properties file not found")
            }
        }
    }

    buildTypes {
        release {
            // Disable code shrinking and obfuscation to prevent Play Store optimization issues
            isMinifyEnabled = false
            isShrinkResources = false
            
            // Use release keystore if available, otherwise fall back to debug
            val keystorePropertiesFile = rootProject.file("keystore.properties")
            println("🔍 Looking for keystore.properties at: ${keystorePropertiesFile.absolutePath}")
            println("🔍 Root project directory: ${rootProject.projectDir.absolutePath}")
            val keystoreExists = keystorePropertiesFile.exists()
            println("🔍 Keystore properties exists: $keystoreExists")
            
            signingConfig = if (keystoreExists) {
                println("✅ Using release signing config")
                signingConfigs.getByName("release")
            } else {
                println("⚠️ Falling back to debug signing config")
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
}
