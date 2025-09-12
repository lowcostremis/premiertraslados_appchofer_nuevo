// Contenido del archivo build.gradle.kts para el módulo 'app'

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.premiertraslados_appchofer_nuevo"
    compileSdk = 36 // Se actualiza el SDK a 36 para compatibilidad con los plugins.

    defaultConfig {
        applicationId = "com.example.premiertraslados_appchofer_nuevo"
        minSdk = flutter.minSdkVersion
        targetSdk = 36 // Se actualiza el targetSdk a 36.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
        // Habilita el desugaring para compatibilidad con las APIs de Java 8.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Se agrega esta línea para soportar el desugaring en dispositivos antiguos.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation(project(":flutter_local_notifications"))
}