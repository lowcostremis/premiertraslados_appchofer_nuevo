<<<<<<< HEAD
import Flutter
import UIKit

@main
=======
import UIKit
import Flutter
import GoogleMaps // <-- Asegúrate de que esta línea esté

@UIApplicationMain
>>>>>>> 2a3181c248f6d927db3e7a11e30e69ab60aa8f44
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
<<<<<<< HEAD
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
=======
    GMSServices.provideAPIKey("AIzaSyB5-exa4BdMxkmR5OF02X64dXOo91Aktng") // <-- Línea agregada
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
>>>>>>> 2a3181c248f6d927db3e7a11e30e69ab60aa8f44
