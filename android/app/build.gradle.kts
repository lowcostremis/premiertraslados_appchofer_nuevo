// Se agregan funciones para leer la versión directamente desde pubspec.yaml
// Esto evita inconsistencias entre tu máquina y GitHub.
import java.util.regex.Pattern

fun getVersionName(): String {
    val pubspecFile = rootProject.file("../pubspec.yaml")
    if (!pubspecFile.exists()) {
        return "1.0.0"
    }
    val pubspecContent = pubspecFile.readText()
    val matcher = Pattern.compile("version: (.*)").matcher(pubspecContent)
    if (matcher.find()) {
        return matcher.group(1).split("+")[0]
    }
    return "1.0.0"
}

fun getVersionCode(): Int {
    val pubspecFile = rootProject.file("../pubspec.yaml")
    if (!pubspecFile.exists()) {
        return 1
    }
    val pubspecContent = pubspecFile.readText()
    val matcher = Pattern.compile("version: (.*)").matcher(pubspecContent)
    if (matcher.find()) {
        val versionString = matcher.group(1)
        val parts = versionString.split("+")
        if (parts.size > 1) {
            return parts[1].toInt()
        }
    }
    return 1
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.premiertraslados_appchofer_nuevo"
    compileSdk = 36

    lintOptions {
        disable += "Instantiatable"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    defaultConfig {
        applicationId = "com.example.premiertraslados_appchofer_nuevo"
        // --- ESTA ES LA LÍNEA CORREGIDA ---
        minSdk = 23
        targetSdk = 34

        versionCode = getVersionCode()
        versionName = getVersionName()
    }

    buildTypes {
        getByName("release") {
            // Aquí va la configuración para firmar tu app de producción.
        }
    }
}

dependencies {
    // Puedes agregar dependencias específicas de Android aquí si es necesario.
}

