plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// --- INICIO DE LA ADAPTACIÓN INTELIGENTE ---
// Estas líneas determinan qué sintaxis usar (con o sin paréntesis)
// dependiendo de tu versión de Flutter. Funcionará en ambos entornos.
val flutterVersionCode = try {
    flutter.versionCode()
} catch (e: Exception) {
    flutter.versionCode
}

val flutterVersionName = try {
    flutter.versionName()
} catch (e: Exception) {
    flutter.versionName
}
// --- FIN DE LA ADAPTACIÓN INTELIGENTE ---

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
        minSdk = flutter.minSdkVersion
        targetSdk = 34
        
        // Usamos las variables inteligentes que definimos arriba
        versionCode = flutterVersionCode
        versionName = flutterVersionName
    }

    buildTypes {
        release {
            [cite_start]// TODO: Add your own signing config for the release build. [cite: 3]
            [cite_start]// Signing with the debug keys for now, so `flutter run --release` works. [cite: 4]
            [cite_start]signingConfig = signingConfigs.getByName("debug") [cite: 5]
        }
    }
}

flutter {
    source = "../.."
}