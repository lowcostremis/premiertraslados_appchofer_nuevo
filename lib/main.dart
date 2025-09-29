// main.dart - CÓDIGO COMPLETO Y CORREGIDO

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:location/location.dart' as loc;
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'firebase_options.dart';
import 'login_screen.dart';
import 'trip_detail_screen.dart';
import 'update_checker.dart';
import 'notifications_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// =======================================================================
// ▼▼▼ PASO 1: AÑADE ESTA FUNCIÓN COMPLETA (FUERA DE CUALQUIER CLASE) ▼▼▼
// =======================================================================
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Es muy importante inicializar Firebase aquí para que el handler funcione correctamente.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print("¡Notificación recibida en SEGUNDO PLANO!: ${message.data}");

  // Aquí es donde puedes agregar lógica personalizada en el futuro.
  // Por ejemplo, podrías forzar una sincronización de datos o
  // mostrar una segunda notificación local si fuera una alerta crítica.
}
// =======================================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await initializeDateFormatting('es_ES', null);
  await NotificationService().initNotifications();

  // =======================================================================
  // ▼▼▼ PASO 2: AÑADE ESTA LÍNEA PARA REGISTRAR EL MANEJADOR ▼▼▼
  // =======================================================================
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Remis Premier App',
      theme: ThemeData(
        primarySwatch: Colors.amber,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const UpdateCheckWrapper(child: AuthWrapper()),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          return const MainScreen();
        }
        return const LoginScreen();
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final loc.Location _location = loc.Location();

  User? _user;
  String _choferDocId = '';
  bool _estaEnLinea = false;
  StreamSubscription<DocumentSnapshot>? _userDocSubscription;
  StreamSubscription<loc.LocationData>? _locationSubscription;

  List<Map<String, dynamic>> _viajesActivos = [];
  bool _isGpsEnabled = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _user = _auth.currentUser;
    _inicializarApp();
    // Listener para notificaciones con la app abierta
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('¡Recibida una notificación en PRIMER PLANO!');
      print('Datos del mensaje: ${message.notification?.title}');
      _refrescarViajesActivos(); // Forzamos la actualización de la lista de viajes.
      NotificationService().showNotification(message);
    });
  }

  @override
  void dispose() {
    _userDocSubscription?.cancel();
    _locationSubscription?.cancel();
    _location.enableBackgroundMode(enable: false);
    super.dispose();
  }

  Future<void> _inicializarApp() async {
    if (_user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    bool permissionsGranted = await _requestPermissions();
    if (!permissionsGranted) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    bool serviceEnabled = await _location.serviceEnabled();
    if (mounted) {
      setState(() => _isGpsEnabled = serviceEnabled);
    }
    await _obtenerIdDeChofer();
    _escucharViajesActivos();
    if (_isGpsEnabled) {
      await _activarServicioDeUbicacion();
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<bool> _requestPermissions() async {
    // 1. Solicita el permiso de ubicación mientras la app está en uso.
    var status = await Permission.locationWhenInUse.request();

    if (status.isGranted) {
      print("Permiso de ubicación 'en uso' concedido.");

      // 2. Si se concede, solicita el permiso para ejecutarse siempre (segundo plano).
      // Esto es crucial para que la app funcione cuando no está en pantalla.
      var backgroundStatus = await Permission.locationAlways.request();

      if (backgroundStatus.isGranted) {
        print("Permiso de ubicación 'siempre' concedido.");
        return true; // Ambos permisos concedidos, ¡éxito!
      } else {
        print("Permiso de ubicación 'siempre' DENEGADO.");
        // Aunque el de segundo plano falle, podemos continuar si el básico fue concedido.
        return true;
      }
    } else {
      print("Permiso de ubicación 'en uso' DENEGADO.");
      // Aquí podrías mostrar un diálogo al usuario explicando por qué es necesario.
      return false;
    }
  }

  Future<void> _obtenerIdDeChofer() async {
    if (_user == null) return;
    final userId = _user!.uid;
    try {
      final querySnapshot = await _firestore
          .collection('choferes')
          .where('auth_uid', isEqualTo: userId)
          .limit(1)
          .get();
      if (querySnapshot.docs.isNotEmpty) {
        final choferDoc = querySnapshot.docs.first;
        if (mounted) {
          _choferDocId = choferDoc.id;
          String? fcmToken = await FirebaseMessaging.instance.getToken();
          if (fcmToken != null) {
            // Guardar o actualizar el token en el documento del chofer
            await _firestore.collection('choferes').doc(_choferDocId).update({
              'fcm_token': fcmToken,
            });
            print('✅ Token FCM guardado en Firestore para el chofer: $_choferDocId');
          }
        }
        final packageInfo = await PackageInfo.fromPlatform();
        final String version =
            '${packageInfo.version}+${packageInfo.buildNumber}';
        await _firestore.collection('choferes').doc(choferDoc.id).update({
          'app_version': version,
        });
      }
    } catch (e) {
      print("Error al obtener ID u actualizar versión del chofer: $e");
    }
  }

  Future<void> _refrescarViajesActivos() async {
    if (_choferDocId.isEmpty) return;
    final doc = await _firestore.collection('choferes').doc(_choferDocId).get();
    if (!doc.exists || !mounted) return;
    final data = doc.data() as Map<String, dynamic>;
    final List<dynamic> newViajeIds = data['viajes_activos'] ?? [];
    if (newViajeIds.isEmpty) {
      setState(() => _viajesActivos = []);
      return;
    }
    final List<Map<String, dynamic>> viajes = [];
    for (String id in newViajeIds.cast<String>()) {
      try {
        final docSnapshot = await _firestore
            .collection('reservas')
            .doc(id)
            .get();
        if (docSnapshot.exists) {
          viajes.add({
            'id': docSnapshot.id,
            ...docSnapshot.data() as Map<String, dynamic>,
          });
        }
      } catch (e) {
        print("Error al obtener el viaje con ID $id: $e");
      }
    }
    viajes.sort((a, b) {
      Timestamp? fechaA = _getSortableDate(a);
      Timestamp? fechaB = _getSortableDate(b);
      if (fechaA == null && fechaB == null) return 0;
      if (fechaA == null) return 1;
      if (fechaB == null) return -1;
      return fechaA.compareTo(fechaB);
    });
    if (mounted) {
      setState(() {
        _viajesActivos = viajes;
      });
    }
  }

  Timestamp? _getSortableDate(Map<String, dynamic> viaje) {
    final String? fechaTurnoStr = viaje['fecha_turno'];
    if (fechaTurnoStr == null || fechaTurnoStr.isEmpty) return null;
    final String? horaPickupStr = viaje['hora_pickup'];
    if (horaPickupStr != null && horaPickupStr.isNotEmpty) {
      try {
        return Timestamp.fromDate(
          DateTime.parse('${fechaTurnoStr}T${horaPickupStr}'),
        );
      } catch (e) {}
    }
    final String? horaTurnoStr = viaje['hora_turno'];
    if (horaTurnoStr != null && horaTurnoStr.isNotEmpty) {
      try {
        return Timestamp.fromDate(
          DateTime.parse('${fechaTurnoStr}T${horaTurnoStr}'),
        );
      } catch (e) {}
    }
    return null;
  }

  void _escucharViajesActivos() {
    if (_choferDocId.isEmpty) return;
    _userDocSubscription = _firestore
        .collection('choferes')
        .doc(_choferDocId)
        .snapshots()
        .listen((DocumentSnapshot snapshot) async {
          if (!mounted || !snapshot.exists) return;
          final data = snapshot.data() as Map<String, dynamic>;
          final bool enLineaDB = data['esta_en_linea'] ?? false;
          if (_estaEnLinea != enLineaDB) {
            setState(() => _estaEnLinea = enLineaDB);
          }
          final List<dynamic> newViajeIds = data['viajes_activos'] ?? [];
          if (newViajeIds.isNotEmpty) {
            final List<Map<String, dynamic>> viajes = [];
            for (String id in newViajeIds.cast<String>()) {
              try {
                final docSnapshot = await _firestore
                    .collection('reservas')
                    .doc(id)
                    .get();
                if (docSnapshot.exists) {
                  viajes.add({
                    'id': docSnapshot.id,
                    ...docSnapshot.data() as Map<String, dynamic>,
                  });
                }
              } catch (e) {
                print("Error al obtener el viaje con ID $id: $e");
              }
            }
            viajes.sort((a, b) {
              Timestamp? fechaA = _getSortableDate(a);
              Timestamp? fechaB = _getSortableDate(b);
              if (fechaA == null && fechaB == null) return 0;
              if (fechaA == null) return 1;
              if (fechaB == null) return -1;
              return fechaA.compareTo(fechaB);
            });
            if (mounted) setState(() => _viajesActivos = viajes);
          } else {
            if (mounted) setState(() => _viajesActivos = []);
          }
        });
  }

  Future<void> _toggleEnLinea(bool value) async {
    if (_choferDocId.isEmpty) return;
    if (value) {
      bool serviceEnabled = await _location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
        if (!serviceEnabled) {
          if (mounted) setState(() => _isGpsEnabled = false);
          return;
        }
      }
      if (mounted) setState(() => _isGpsEnabled = true);
    }
    await _firestore.collection('choferes').doc(_choferDocId).update({
      'esta_en_linea': value,
    });
  }

  Future<void> _activarServicioDeUbicacion() async {
    if (_locationSubscription != null) return;
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      if (mounted) setState(() => _isGpsEnabled = false);
      return;
    }
    try {
      await _location.enableBackgroundMode(enable: true);
      await _location.changeSettings(
        accuracy: loc.LocationAccuracy.high,
        interval: 5000,
        distanceFilter: 10,
      );
      _locationSubscription = _location.onLocationChanged.listen((
        loc.LocationData currentLocation,
      ) {
        print(
          '📍 Ubicación recibida del GPS: Lat ${currentLocation.latitude}, Long ${currentLocation.longitude}',
        );
        if (mounted &&
            _choferDocId.isNotEmpty &&
            currentLocation.latitude != null &&
            currentLocation.longitude != null) {
          _firestore.collection('choferes').doc(_choferDocId).update({
            'coordenadas': GeoPoint(
              currentLocation.latitude!,
              currentLocation.longitude!,
            ),
            'ultima_actualizacion': FieldValue.serverTimestamp(),
          });
        }
      });
    } catch (e) {
      print('Error al activar servicio de ubicación: $e');
    }
  }

  Widget _buildEstadoIcon(Map<String, dynamic> estado) {
    final String principal = estado['principal'] ?? 'pendiente';
    final String detalle = estado['detalle'] ?? '';
    if (principal == 'Asignado') {
      if (detalle == 'Aceptada') {
        return const Icon(
          Icons.check_circle_outline,
          color: Colors.greenAccent,
          size: 40,
        );
      } else {
        return const Icon(
          Icons.help_outline,
          color: Colors.redAccent,
          size: 40,
        );
      }
    }
    if (principal == 'En Origen' || principal == 'Viaje Iniciado') {
      return const Icon(
        Icons.check_circle,
        color: Colors.greenAccent,
        size: 40,
      );
    }
    return const Icon(Icons.hourglass_empty, color: Colors.orange, size: 40);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Viajes Asignados')),
      body: Stack(
        children: [
          Column(
            children: [
              SwitchListTile(
                title: Text(_estaEnLinea ? 'En Línea' : 'Fuera de Línea'),
                value: _estaEnLinea,
                onChanged: _toggleEnLinea,
                secondary: Icon(
                  _estaEnLinea ? Icons.location_on : Icons.location_off,
                  color: _estaEnLinea ? Colors.green : Colors.red,
                ),
              ),
              Expanded(
                child: _viajesActivos.isEmpty
                    ? const Center(child: Text('No hay viajes asignados.'))
                    : ListView.builder(
                        itemCount: _viajesActivos.length,
                        itemBuilder: (context, index) {
                          final viaje = _viajesActivos[index];
                          Timestamp? fechaMostrada = _getSortableDate(viaje);
                          final String fechaFormateada = fechaMostrada != null
                              ? DateFormat(
                                  'dd MMM',
                                  'es_ES',
                                ).format(fechaMostrada.toDate())
                              : 'N/A';
                          final String horaFormateada = fechaMostrada != null
                              ? DateFormat(
                                  'HH:mm',
                                  'es_ES',
                                ).format(fechaMostrada.toDate())
                              : 'N/A';
                          final bool esExclusivo =
                              viaje['es_exclusivo'] ?? false;
                          final estadoMap =
                              viaje['estado'] as Map<String, dynamic>? ?? {};

                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                              vertical: 4.0,
                            ),
                            child: ListTile(
                              leading: _buildEstadoIcon(estadoMap),
                              title: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      viaje['nombre_pasajero'] ?? 'Sin nombre',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        fechaFormateada,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodyLarge,
                                      ),
                                      Text(
                                        horaFormateada,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (esExclusivo)
                                    const Text(
                                      'VIAJE EXCLUSIVO',
                                      style: TextStyle(
                                        color: Color(0xFF51ED8D),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  Text('Origen: ${viaje['origen'] ?? 'N/A'}'),
                                  Text('Destino: ${viaje['destino'] ?? 'N/A'}'),
                                ],
                              ),
                              isThreeLine: esExclusivo,
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => TripDetailScreen(
                                      reservaId: viaje['id'],
                                      onStateChanged: _refrescarViajesActivos,
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
          if (!_isGpsEnabled)
            GpsDisabledOverlay(
              onPressed: () async {
                bool serviceRequested = await _location.requestService();
                if (serviceRequested && mounted) {
                  setState(() => _isGpsEnabled = true);
                }
              },
            ),
        ],
      ),
    );
  }
}

class GpsDisabledOverlay extends StatelessWidget {
  final VoidCallback onPressed;
  const GpsDisabledOverlay({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.7),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.gps_off, color: Colors.red, size: 50),
                const SizedBox(height: 16),
                const Text(
                  'GPS Desactivado',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Necesitas activar el GPS para usar la aplicación.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: onPressed,
                  child: const Text('Activar GPS'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
