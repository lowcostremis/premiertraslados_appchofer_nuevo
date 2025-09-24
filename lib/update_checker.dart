import 'package:flutter/material.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UpdateCheckWrapper extends StatefulWidget {
  final Widget child;
  const UpdateCheckWrapper({super.key, required this.child});

  @override
  State<UpdateCheckWrapper> createState() => _UpdateCheckWrapperState();
}

class _UpdateCheckWrapperState extends State<UpdateCheckWrapper> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdate();
    });
  }

  Future<int> _getStoredVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('installed_version') ?? 0; // Valor por defecto 0
  }

  Future<void> _setStoredVersion(int version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('installed_version', version);
  }

  Future<void> _checkForUpdate() async {
    final remoteConfig = FirebaseRemoteConfig.instance;

    try {
      await remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: Duration.zero, // Para forzar fetch en desarrollo
      ));
      await remoteConfig.fetchAndActivate();

      final int latestVersion = remoteConfig.getInt('latest_version_code');
      final bool isMandatory = remoteConfig.getBool('is_update_mandatory');

      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final int currentVersion = int.parse(packageInfo.buildNumber);

      final int localVersion = await _getStoredVersion();

      // Solo si la versión remota es mayor que la instalada localmente
      if (latestVersion > localVersion &&
          latestVersion > currentVersion &&
          isMandatory) {
        // Guardamos la versión como instalada
        await _setStoredVersion(latestVersion);
        // Mostramos la opción de actualizar
        _showUpdateDialog();
      } else {
        // No hay actualización o ya se tiene la última versión instalada
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error al verificar actualización: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showUpdateDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Actualización Requerida'),
        content: const Text(
            'Hay una nueva versión de la aplicación disponible. Debes actualizar para poder continuar.'),
        actions: [
          TextButton(
            onPressed: () async {
              const String apkUrl =
                  'https://firebasestorage.googleapis.com/v0/b/premiertraslados-31ee2.firebasestorage.app/o/app-release.apk?alt=media&token=9f5c355f-687b-4636-9471-306400e0b3f0'; // TU URL REAL
              final Uri url = Uri.parse(apkUrl);
              if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
                print('No se pudo lanzar la URL de descarga');
              }
            },
            child: const Text('Actualizar Ahora'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.amber),
                  SizedBox(height: 20),
                  Text('Verificando actualizaciones...'),
                ],
              ),
            ),
          )
        : widget.child;
  }
}
