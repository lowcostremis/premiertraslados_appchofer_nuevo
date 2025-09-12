import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:location/location.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:premiertraslados_appchofer_nuevo/login_screen.dart';
import 'package:premiertraslados_appchofer_nuevo/trip_detail_screen.dart';
import 'package:premiertraslados_appchofer_nuevo/firebase_options.dart';

// 1. Instancia global del plugin de notificaciones
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// 2. Definir un canal de notificación para Android
const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'high_importance_channel', // id del canal
  'Notificaciones de Viajes', // nombre del canal
  description: 'Este canal se usa para notificaciones de nuevos viajes.',
  importance: Importance.max,
  playSound: true,
  sound: RawResourceAndroidNotificationSound(
    'reserva_sound',
  ), // Nombre del archivo sin la extensión
);

// 3. Función para mostrar la notificación de NUEVO viaje
Future<void> showNewTripNotification(String tripId) async {
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
        'high_importance_channel', // Debe coincidir con el id del canal
        'Notificaciones de Viajes',
        channelDescription:
            'Este canal se usa para notificaciones de nuevos viajes.',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(
          'reserva_sound',
        ), // Nombre del archivo sin la extensión
        styleInformation: BigTextStyleInformation(''),
      );
  const NotificationDetails platformChannelSpecifics = NotificationDetails(
    android: androidPlatformChannelSpecifics,
  );
  await flutterLocalNotificationsPlugin.show(
    0, // ID de la notificación para nuevos viajes
    '¡Nuevo Viaje Asignado!',
    'Tienes una nueva reserva pendiente.',
    platformChannelSpecifics,
    payload: tripId,
  );
}

// 4. Función para mostrar la notificación de CANCELACIÓN (Nueva)
Future<void> showTripCancelledNotification(String tripId) async {
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
        'high_importance_channel', // Usamos el mismo canal
        'Notificaciones de Viajes',
        channelDescription:
            'Este canal se usa para notificaciones de viajes cancelados.',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(
          'reserva_sound', // Puedes usar un sonido diferente si lo deseas
        ),
        styleInformation: BigTextStyleInformation(''),
      );
  const NotificationDetails platformChannelSpecifics = NotificationDetails(
    android: androidPlatformChannelSpecifics,
  );
  await flutterLocalNotificationsPlugin.show(
    1, // ID de notificación diferente para no sobreescribir otras
    'Reserva Cancelada por el Operador',
    'Una de tus reservas fue anulada o reasignada.',
    platformChannelSpecifics,
    payload: tripId,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
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
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final Location _location = Location();
  StreamSubscription<QuerySnapshot>? _userDocSubscription;
  String? _userId;
  List<DocumentSnapshot> _viajesActivos = [];

  @override
  void initState() {
    super.initState();
    _userId = _auth.currentUser?.uid;
    _iniciarRastreoUbicacion();
    _escucharViajesActivos();
  }

  @override
  void dispose() {
    _userDocSubscription?.cancel();
    super.dispose();
  }

  Future<void> _iniciarRastreoUbicacion() async {
    try {
      await _location.requestPermission();
      _location.onLocationChanged.listen((LocationData currentLocation) {
        if (_userId != null) {
          _functions.httpsCallable('actualizarUbicacionChofer').call({
            'userId': _userId,
            'lat': currentLocation.latitude,
            'lng': currentLocation.longitude,
          });
        }
      });
    } catch (e) {
      print('Error al iniciar el rastreo de ubicación: $e');
    }
  }

  // --- FUNCIÓN MODIFICADA ---
  void _escucharViajesActivos() {
    if (_userId == null) return;
    _userDocSubscription = _firestore
        .collection('choferes')
        .where('auth_uid', isEqualTo: _userId)
        .limit(1)
        .snapshots()
        .listen((QuerySnapshot querySnapshot) {
          if (querySnapshot.docs.isEmpty) {
            print(
              "No se encontró un documento de chofer para el UID: $_userId",
            );
            return;
          }

          final DocumentSnapshot snapshot = querySnapshot.docs.first;

          if (snapshot.exists) {
            final data = snapshot.data() as Map<String, dynamic>;

            // Se asegura que 'viajes_activos' exista y sea una lista
            final List<dynamic> newViajeIds =
                data.containsKey('viajes_activos') &&
                    data['viajes_activos'] is List
                ? data['viajes_activos']
                : [];

            final List<String> oldViajeIds = _viajesActivos
                .map((doc) => doc.id)
                .toList();

            // 1. Detectar NUEVOS viajes
            final List<String> newReservas = newViajeIds
                .where((id) => !oldViajeIds.contains(id))
                .cast<String>()
                .toList();

            if (newReservas.isNotEmpty) {
              for (final reservaId in newReservas) {
                showNewTripNotification(reservaId);
              }
            }

            // 2. Detectar viajes ELIMINADOS
            final List<String> removedReservas = oldViajeIds
                .where((id) => !newViajeIds.contains(id))
                .cast<String>()
                .toList();

            if (removedReservas.isNotEmpty) {
              for (final reservaId in removedReservas) {
                showTripCancelledNotification(reservaId);
              }
            }

            // 3. Actualizar la interfaz de usuario
            if (newViajeIds.isEmpty) {
              if (mounted) {
                setState(() {
                  _viajesActivos = [];
                });
              }
              return;
            }

            _firestore
                .collection('reservas')
                .where(FieldPath.documentId, whereIn: newViajeIds)
                .get()
                .then((querySnapshot) {
                  if (mounted) {
                    setState(() {
                      _viajesActivos = querySnapshot.docs;
                    });
                  }
                });
          }
        });
  }

  Future<void> _detenerRastreoGlobal() async {
    _userDocSubscription?.cancel();
    if (_userId != null) {
      _functions.httpsCallable('actualizarUbicacionChofer').call({
        'userId': _userId,
        'lat': null,
        'lng': null,
      });
    }
    await _auth.signOut();
  }

  Widget _buildViajesList() {
    if (_viajesActivos.isEmpty) {
      return const Center(
        child: Text('No tienes viajes activos en este momento.'),
      );
    }

    return ListView.builder(
      itemCount: _viajesActivos.length,
      itemBuilder: (context, index) {
        final viajeDoc = _viajesActivos[index];
        final viaje = viajeDoc.data() as Map<String, dynamic>;

        final estadoDetalle = (viaje['estado'] is Map)
            ? viaje['estado']['detalle'] ?? viaje['estado']['principal']
            : viaje['estado'];

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: const Icon(Icons.directions_car, color: Colors.amber),
            title: Text('Origen: ${viaje['origen'] ?? 'N/A'}'),
            subtitle: Text(
              'Destino: ${viaje['destino'] ?? 'N/A'}\nEstado: $estadoDetalle',
            ),
            isThreeLine: true,
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Viajes Activos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _detenerRastreoGlobal();
              // No es necesario llamar a signOut dos veces. _detenerRastreoGlobal ya lo hace.
            },
          ),
        ],
      ),
      body: _buildViajesList(),
    );
  }
}
