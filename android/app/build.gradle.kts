plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.premiertraslados_appchofer_nuevo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
          applicationId = "com.example.premiertraslados_appchofer_nuevo"
        minSdk = 23 // Asegúrate que este número sea el correcto para tu proyecto
        targetSdk = 34 // Asegúrate que este número sea el correcto para tu proyecto
        versionCode = flutter.versionCode()
        versionName = flutter.versionName()
    }

    buildTypes {
        release {
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
