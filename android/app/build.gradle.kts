<<<<<<< HEAD
plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
=======
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
>>>>>>> 2a3181c248f6d927db3e7a11e30e69ab60aa8f44
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.premiertraslados_appchofer_nuevo"
<<<<<<< HEAD
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.premiertraslados_appchofer_nuevo"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
=======
    // <<< RECOMENDACIÓN APLICADA AQUÍ >>>
    // Se ajusta a 34 para coincidir con la versión de destino (targetSdk)
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
        
        // <<< CORRECCIÓN PRINCIPAL APLICADA AQUÍ >>>
        // Se usa la variable de Flutter para determinar la versión mínima necesaria.
        minSdk = flutter.minSdkVersion
        
        targetSdk = 34
        versionCode = getVersionCode()
        versionName = getVersionName()
    }

    buildTypes {
        getByName("release") {
            // Aquí va la configuración para firmar tu app de producción.
>>>>>>> 2a3181c248f6d927db3e7a11e30e69ab60aa8f44
        }
    }
}

<<<<<<< HEAD
flutter {
    source = "../.."
=======
dependencies {
    // Puedes agregar dependencias específicas de Android aquí si es necesario.
>>>>>>> 2a3181c248f6d927db3e7a11e30e69ab60aa8f44
}
