// main.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:location/location.dart' as loc;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:premiertraslados_appchofer_nuevo/login_screen.dart';
import 'package:premiertraslados_appchofer_nuevo/trip_detail_screen.dart';
import 'package:premiertraslados_appchofer_nuevo/firebase_options.dart';
import 'package:premiertraslados_appchofer_nuevo/update_checker.dart';

// --- ADAPTACIÓN 1: GlobalKey para Navegación ---
// Permite navegar desde cualquier parte de la app, incluso desde el callback de notificaciones.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

int _notificationIdCounter = 0;

const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'high_importance_channel',
  'Notificaciones de Viajes',
  description: 'Este canal se usa para notificaciones de nuevos viajes.',
  importance: Importance.max,
  playSound: true,
  sound: RawResourceAndroidNotificationSound('reserva_sound'),
);

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print("Manejando un mensaje en segundo plano: ${message.messageId}");

  final String? tipoNotificacion = message.data['tipo_notificacion'];
  final String? tripId = message.data['tripId'];

  if (tripId != null) {
    // --- ADAPTACIÓN 2: Lógica robusta con switch ---
    switch (tipoNotificacion) {
      case 'NUEVO_VIAJE':
        showNewTripNotification(tripId);
        break;
      case 'VIAJE_CANCELADO': // Suponiendo que el backend envía este tipo
        showTripCancelledNotification(tripId);
        break;
      default:
        print('Tipo de notificación desconocido: $tipoNotificacion');
        break;
    }
  }
}

// --- ADAPTACIÓN 3: Refactorización de Notificaciones ---
// Función genérica para mostrar notificaciones locales.
Future<void> _showLocalNotification({
  required String title,
  required String body,
  required String payload,
  String sound = 'reserva_sound',
}) async {
  final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    channel.id,
    channel.name,
    channelDescription: channel.description,
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    sound: RawResourceAndroidNotificationSound(sound),
    styleInformation: const BigTextStyleInformation(''),
  );

  final NotificationDetails platformDetails =
      NotificationDetails(android: androidDetails);

  await flutterLocalNotificationsPlugin.show(
    _notificationIdCounter++,
    title,
    body,
    platformDetails,
    payload: payload,
  );
}

// Funciones específicas que ahora usan la función genérica.
Future<void> showNewTripNotification(String tripId) async {
  await _showLocalNotification(
    title: '¡Nuevo Viaje Asignado!',
    body: 'Tienes una nueva reserva pendiente.',
    payload: tripId,
  );
}

Future<void> showTripCancelledNotification(String tripId) async {
  await _showLocalNotification(
    title: 'Reserva Cancelada por el Operador',
    body: 'Una de tus reservas fue anulada o reasignada.',
    payload: tripId,
    // Podrías usar un sonido diferente si lo tuvieras, ej: sound: 'cancel_sound'
  );
}
// --- FIN DE LA ADAPTACIÓN 3 ---

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );

  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    // --- ADAPTACIÓN 4: Navegación al tocar notificación ---
    onDidReceiveNotificationResponse: (NotificationResponse response) async {
      final String? payload = response.payload;
      if (payload != null) {
        print('Payload de notificación recibido: $payload');
        // Usamos la GlobalKey para navegar a la pantalla de detalles.
        navigatorKey.currentState?.push(MaterialPageRoute(
          builder: (context) => TripDetailScreen(reservaId: payload),
        ));
      }
    },
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // --- ADAPTACIÓN 1 (continuación): Asignamos la GlobalKey ---
      navigatorKey: navigatorKey,
      title: 'Premier Traslados Chofer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.amber,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
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
          return const UpdateCheckWrapper(child: MainScreen());
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
  StreamSubscription<QuerySnapshot>? _userDocSubscription;
  StreamSubscription<QuerySnapshot>? _reservasSubscription;
  StreamSubscription<loc.LocationData>? _locationSubscription;
  String? _userId;
  String? _choferDocId;
  List<DocumentSnapshot> _viajesActivos = [];
  bool _isOnline = true;
  Timer? _gpsCheckTimer;
  bool _isGpsDisabled = false;

  @override
  void initState() {
    super.initState();
    _userId = _auth.currentUser?.uid;
    _inicializarConfiguracionChofer();

    _gpsCheckTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      final serviceEnabled = await _location.serviceEnabled();
      if (serviceEnabled != !_isGpsDisabled) {
        if (mounted) {
          setState(() {
            _isGpsDisabled = !serviceEnabled;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _userDocSubscription?.cancel();
    _reservasSubscription?.cancel();
    _locationSubscription?.cancel();
    _gpsCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _inicializarConfiguracionChofer() async {
    await Permission.notification.request();
    await _obtenerIdDeChoferYConfigurarFCM();
    if (_isOnline) {
      _iniciarRastreoUbicacion();
    }
    _escucharViajesActivos();
  }

  Future<void> _obtenerIdDeChoferYConfigurarFCM() async {
    if (_userId == null) return;

    final querySnapshot = await _firestore
        .collection('choferes')
        .where('auth_uid', isEqualTo: _userId)
        .limit(1)
        .get();

    if (querySnapshot.docs.isNotEmpty) {
      _choferDocId = querySnapshot.docs.first.id;
      print('✅ ID del documento del chofer encontrado: $_choferDocId');

      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        await _firestore.collection('choferes').doc(_choferDocId).update({
          'fcm_token': fcmToken,
        });
        print('✅ Token FCM actualizado.');
      }

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        if (_choferDocId != null) {
          await _firestore.collection('choferes').doc(_choferDocId).update({
            'fcm_token': newToken,
          });
        }
      });

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('¡Mensaje recibido en primer plano!');
        final String? tipoNotificacion = message.data['tipo_notificacion'];
        final String? tripId = message.data['tripId'];

        if (tripId != null) {
          // --- ADAPTACIÓN 2 (continuación): Lógica robusta con switch ---
          switch (tipoNotificacion) {
            case 'NUEVO_VIAJE':
              showNewTripNotification(tripId);
              break;
            case 'VIAJE_CANCELADO':
              showTripCancelledNotification(tripId);
              break;
            default:
              print('Tipo de notificación desconocido: $tipoNotificacion');
              break;
          }
        }
      });
    } else {
      print('❌ ERROR: No se encontró documento para el auth_uid: $_userId');
    }
  }

  Future<void> _iniciarRastreoUbicacion() async {
    if (_choferDocId != null) {
      await _firestore.collection('choferes').doc(_choferDocId).update({
        'esta_en_linea': true,
      });
      print('✅ Chofer puesto en modo online.');
    }

    _locationSubscription?.cancel();
    try {
      var permissionGranted = await _location.hasPermission();
      if (permissionGranted == loc.PermissionStatus.denied) {
        permissionGranted = await _location.requestPermission();
        if (permissionGranted != loc.PermissionStatus.granted) return;
      }
      if (!await _location.serviceEnabled()) {
        if (!await _location.requestService()) return;
      }
      if (await _location.hasPermission() == loc.PermissionStatus.granted) {
        await _location.enableBackgroundMode(enable: true);
      }
      await _location.changeSettings(
        accuracy: loc.LocationAccuracy.high,
        interval: 5000,
        distanceFilter: 10,
      );

      _locationSubscription = _location.onLocationChanged.listen((
        loc.LocationData currentLocation,
      ) {
        if (_choferDocId != null &&
            currentLocation.latitude != null &&
            currentLocation.longitude != null) {
          // --- ADAPTACIÓN 5: Eliminación de escritura redundante ---
          _firestore.collection('choferes').doc(_choferDocId).update({
            'coordenadas': GeoPoint(
              currentLocation.latitude!,
              currentLocation.longitude!,
            ),
            'ultima_actualizacion': FieldValue.serverTimestamp(),
            // Se elimina 'esta_en_linea': true de aquí.
          });
        }
      });
    } catch (e) {
      print('Error al iniciar el rastreo de ubicación: $e');
    }
  }

  Future<void> _detenerRastreoUbicacion() async {
    _locationSubscription?.cancel();
    _locationSubscription = null;
    if (_choferDocId != null) {
      try {
        await _firestore.collection('choferes').doc(_choferDocId).update({
          'esta_en_linea': false,
        });
        print('✅ Chofer puesto en modo offline.');
      } catch (e) {
        print('❌ Error al poner en modo offline: $e');
      }
    }
  }

  DateTime _getSortableDateTime(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final fecha = data['fecha_turno'] as String?;
    final horaPickup = data['hora_pickup'] as String?;
    final horaTurno = data['hora_turno'] as String?;

    if (fecha == null || fecha.isEmpty) return DateTime(9999);
    String? horaFinal =
        (horaPickup != null && horaPickup.isNotEmpty) ? horaPickup : horaTurno;
    if (horaFinal == null || horaFinal.isEmpty) return DateTime(9999);

    try {
      return DateTime.parse('${fecha}T$horaFinal');
    } catch (e) {
      print('Error de formato de fecha/hora: $e');
      return DateTime(9999);
    }
  }

  void _escucharViajesActivos() {
    if (_userId == null) return;

    _userDocSubscription = _firestore
        .collection('choferes')
        .where('auth_uid', isEqualTo: _userId)
        .limit(1)
        .snapshots()
        .listen((QuerySnapshot querySnapshot) {
      _reservasSubscription?.cancel();

      if (querySnapshot.docs.isEmpty) {
        if (mounted) setState(() => _viajesActivos = []);
        return;
      }

      final DocumentSnapshot snapshot = querySnapshot.docs.first;
      final data = snapshot.data() as Map<String, dynamic>;
      final List<dynamic> newViajeIds = data['viajes_activos'] ?? [];

      if (newViajeIds.isEmpty) {
        if (mounted) {
          setState(() => _viajesActivos = []);
        }
      } else {
        _reservasSubscription = _firestore
            .collection('reservas')
            .where(FieldPath.documentId, whereIn: newViajeIds)
            .snapshots()
            .listen((reservasSnapshot) {
          if (mounted) {
            final docs = reservasSnapshot.docs;
            docs.sort((a, b) {
              final dateTimeA = _getSortableDateTime(a);
              final dateTimeB = _getSortableDateTime(b);
              return dateTimeA.compareTo(dateTimeB);
            });
            setState(() => _viajesActivos = docs);
          }
        });
      }
    });
  }

  Widget _buildViajesList() {
    if (_viajesActivos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'No tienes viajes activos en este momento.',
            style: TextStyle(fontSize: 18, color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: _viajesActivos.length,
      itemBuilder: (context, index) {
        final viajeDoc = _viajesActivos[index];
        final viaje = viajeDoc.data() as Map<String, dynamic>;

        Color cardColor = Theme.of(context).cardColor;
        final estadoDetalle = (viaje['estado'] is Map)
            ? viaje['estado']['detalle'] as String?
            : null;
        final esExclusivo = viaje['es_exclusivo'] as bool? ?? false;
        final bool estaPendiente = estadoDetalle == 'Enviada al chofer';

        if (estaPendiente) {
          cardColor = esExclusivo
              ? Colors.purple.withOpacity(0.5)
              : Colors.amber.withOpacity(0.5);
        } else if (esExclusivo) {
          cardColor = Colors.green.withOpacity(0.4);
        }

        final fecha = viaje['fecha_turno'] as String?;
        final horaPickup = viaje['hora_pickup'] as String?;
        final horaTurno = viaje['hora_turno'] as String?;
        String horaMostrada =
            ((horaPickup?.isNotEmpty ?? false) ? horaPickup : horaTurno) ??
                '--:--';
        if (horaMostrada.length > 5)
          horaMostrada = horaMostrada.substring(0, 5);

        String fechaMostrada = 'Sin fecha';
        if (fecha != null && fecha.isNotEmpty) {
          try {
            final parsedDate = DateTime.parse(fecha);
            fechaMostrada =
                '${parsedDate.day.toString().padLeft(2, '0')}/${parsedDate.month.toString().padLeft(2, '0')}/${parsedDate.year}';
          } catch (e) {
            fechaMostrada = fecha;
          }
        }

        return Card(
          color: cardColor,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: const Icon(Icons.directions_car, color: Colors.white70),
            title: Text('Origen: ${viaje['origen'] ?? 'N/A'}'),
            subtitle: Text(
              'Destino: ${viaje['destino'] ?? 'N/A'}\nEstado: $estadoDetalle',
            ),
            isThreeLine: true,
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  horaMostrada,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  fechaMostrada,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      TripDetailScreen(reservaId: viajeDoc.id),
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('Mis Viajes Activos'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: Switch(
                  value: _isOnline,
                  onChanged: (value) {
                    setState(() => _isOnline = value);
                    if (value) {
                      _iniciarRastreoUbicacion();
                    } else {
                      _detenerRastreoUbicacion();
                    }
                  },
                  activeColor: Colors.greenAccent,
                  inactiveThumbColor: Colors.grey,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: () async {
                  await _detenerRastreoUbicacion();
                  await _auth.signOut();
                },
              ),
            ],
          ),
          body: _buildViajesList(),
        ),
        if (_isGpsDisabled)
          GpsDisabledOverlay(
            onPressed: () => _location.requestService(),
          ),
      ],
    );
  }
}

class GpsDisabledOverlay extends StatelessWidget {
  final VoidCallback onPressed;
  const GpsDisabledOverlay({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.85),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_off, color: Colors.amber, size: 80),
            const SizedBox(height: 20),
            const Text(
              'Servicio de GPS Desactivado',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 30.0),
              child: Text(
                'Para continuar, por favor activa el servicio de ubicación de tu dispositivo.',
                style: TextStyle(fontSize: 16, color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              icon: const Icon(Icons.settings),
              label: const Text('Activar GPS'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              ),
              onPressed: onPressed,
            ),
          ],
        ),
      ),
    );
  }
}
