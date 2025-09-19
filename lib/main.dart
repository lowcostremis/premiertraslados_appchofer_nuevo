import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:location/location.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:premiertraslados_appchofer_nuevo/login_screen.dart';
import 'package:premiertraslados_appchofer_nuevo/trip_detail_screen.dart';
import 'package:premiertraslados_appchofer_nuevo/firebase_options.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'high_importance_channel',
  'Notificaciones de Viajes',
  description: 'Este canal se usa para notificaciones de nuevos viajes.',
  importance: Importance.max,
  playSound: true,
  sound: RawResourceAndroidNotificationSound('reserva_sound'),
);

Future<void> showNewTripNotification(String tripId) async {
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
  AndroidNotificationDetails(
    'high_importance_channel',
    'Notificaciones de Viajes',
    channelDescription:
    'Este canal se usa para notificaciones de nuevos viajes.',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('reserva_sound'),
    styleInformation: BigTextStyleInformation(''),
  );
  const NotificationDetails platformChannelSpecifics = NotificationDetails(
    android: androidPlatformChannelSpecifics,
  );
  await flutterLocalNotificationsPlugin.show(
    0,
    '¡Nuevo Viaje Asignado!',
    'Tienes una nueva reserva pendiente.',
    platformChannelSpecifics,
    payload: tripId,
  );
}

Future<void> showTripCancelledNotification(String tripId) async {
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
  AndroidNotificationDetails(
    'high_importance_channel',
    'Notificaciones de Viajes',
    channelDescription:
    'Este canal se usa para notificaciones de viajes cancelados.',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('reserva_sound'),
    styleInformation: BigTextStyleInformation(''),
  );
  const NotificationDetails platformChannelSpecifics = NotificationDetails(
    android: androidPlatformChannelSpecifics,
  );
  await flutterLocalNotificationsPlugin.show(
    1,
    'Reserva Cancelada por el Operador',
    'Una de tus reservas fue anulada o reasignada.',
    platformChannelSpecifics,
    payload: tripId,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  const AndroidInitializationSettings initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

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
  final Location _location = Location();
  StreamSubscription<QuerySnapshot>? _userDocSubscription;
  StreamSubscription<QuerySnapshot>? _reservasSubscription;
  String? _userId;
  String? _choferDocId;
  List<DocumentSnapshot> _viajesActivos = [];

  Timer? _gpsCheckTimer;
  bool _isGpsDisabled = false;

  Future<void> _pedirPermisos() async {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  }

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

  Future<void> _inicializarConfiguracionChofer() async {
    await _pedirPermisos();
    await _configurarNotificacionesPush();
    _iniciarRastreoUbicacion();
    _escucharViajesActivos();
  }

  Future<void> _configurarNotificacionesPush() async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();

    final fcmToken = await messaging.getToken();
    print('FCM Token: $fcmToken');

    if (fcmToken != null && _userId != null) {
      final querySnapshot = await _firestore
          .collection('choferes')
          .where('auth_uid', isEqualTo: _userId)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        _choferDocId = querySnapshot.docs.first.id;
        print('✅ ID del documento del chofer encontrado: $_choferDocId');

        await _firestore
            .collection('choferes')
            .doc(_choferDocId)
            .update({'fcm_token': fcmToken});
      } else {
        print('❌ ERROR: No se encontró documento en la colección "choferes" para el auth_uid: $_userId');
      }
    }

    messaging.onTokenRefresh.listen((newToken) async {
      if (_choferDocId != null) {
        await _firestore
            .collection('choferes')
            .doc(_choferDocId)
            .update({'fcm_token': newToken});
      }
    });
  }

  Future<void> _iniciarRastreoUbicacion() async {
    try {
      await _location.requestPermission();
      final serviceEnabled = await _location.serviceEnabled();
      if (!serviceEnabled) {
        if (!await _location.requestService()) return;
      }

      await _location.changeSettings(
        accuracy: LocationAccuracy.high,
        interval: 5000,
        distanceFilter: 10,
      );

      await _location.enableBackgroundMode(enable: true);

      _location.onLocationChanged.listen((LocationData currentLocation) {
        print('📍 Ubicación recibida: Lat ${currentLocation.latitude}, Lng ${currentLocation.longitude}');

        final user = _auth.currentUser;

        if (user != null &&
            _choferDocId != null &&
            currentLocation.latitude != null &&
            currentLocation.longitude != null) {

          print('📡 Intentando actualizar Firestore con ID: $_choferDocId');

          _firestore.collection('choferes').doc(_choferDocId).update({
            'coordenadas': GeoPoint(
              currentLocation.latitude!,
              currentLocation.longitude!,
            ),
          });
        } else {
          print('⚠️ NO SE ACTUALIZA FIRESTORE. Chequeando condiciones:');
          print('   - User no es null? -----> ${user != null}');
          print('   - _choferDocId no es null? -> ${_choferDocId != null} (Valor actual: $_choferDocId)');
        }
      });
    } catch (e) {
      print('Error al iniciar el rastreo de ubicación: $e');
    }
  }

  @override
  void dispose() {
    _userDocSubscription?.cancel();
    _reservasSubscription?.cancel();
    _gpsCheckTimer?.cancel();
    super.dispose();
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
      if (!snapshot.exists) {
        if (mounted) setState(() => _viajesActivos = []);
        return;
      }

      final data = snapshot.data() as Map<String, dynamic>;
      final List<dynamic> newViajeIds =
      data.containsKey('viajes_activos') && data['viajes_activos'] is List
          ? data['viajes_activos']
          : [];

      final List<String> oldViajeIds =
      _viajesActivos.map((doc) => doc.id).toList();

      final List<String> newReservas = newViajeIds
          .where((id) => !oldViajeIds.contains(id))
          .cast<String>()
          .toList();
      if (newReservas.isNotEmpty) {
        for (final reservaId in newReservas) {
          showNewTripNotification(reservaId);
        }
      }
      final List<String> removedReservas = oldViajeIds
          .where((id) => !newViajeIds.contains(id))
          .cast<String>()
          .toList();
      if (removedReservas.isNotEmpty) {
        for (final reservaId in removedReservas) {
          showTripCancelledNotification(reservaId);
        }
      }

      if (newViajeIds.isEmpty) {
        if (mounted) {
          setState(() {
            _viajesActivos = [];
          });
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
            setState(() {
              _viajesActivos = docs;
            });
          }
        });
      }
    });
  }

  Future<void> _detenerRastreoGlobal() async {
    _userDocSubscription?.cancel();
    _reservasSubscription?.cancel();
    await _auth.signOut();
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
        } else {
          if (esExclusivo) {
            cardColor = Colors.green.withOpacity(0.4);
          }
        }

        final fecha = viaje['fecha_turno'] as String?;
        final horaPickup = viaje['hora_pickup'] as String?;
        final horaTurno = viaje['hora_turno'] as String?;

        String horaMostrada = (horaPickup != null && horaPickup.isNotEmpty)
            ? horaPickup.substring(0, 5)
            : (horaTurno != null && horaTurno.isNotEmpty)
            ? horaTurno.substring(0, 5)
            : '--:--';

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
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: () async {
                  await _detenerRastreoGlobal();
                },
              ),
            ],
          ),
          body: _buildViajesList(),
        ),
        if (_isGpsDisabled)
          GpsDisabledOverlay(
            onPressed: () {
              _location.requestService();
            },
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
    return Container(
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