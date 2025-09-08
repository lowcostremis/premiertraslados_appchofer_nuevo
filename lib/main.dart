import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// Importaciones para el rastreo de ubicación
import 'package:cloud_functions/cloud_functions.dart';
import 'package:location/location.dart';

import 'package:premiertraslados_appchofer_nuevo/login_screen.dart';
import 'package:premiertraslados_appchofer_nuevo/trip_detail_screen.dart';
import 'package:premiertraslados_appchofer_nuevo/firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
              body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData) {
          return const HomeScreen();
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription? _nuevosViajesSubscription;
  StreamSubscription? _viajesActivosSubscription;
  String? _choferId;
  final List<DocumentSnapshot> _viajesActivos = [];
  bool _isLoading = true;

  final Location _locationService = Location();
  StreamSubscription<LocationData>? _locationSubscription;

  @override
  void initState() {
    super.initState();
    _iniciarListeners();
  }

  @override
  void dispose() {
    _nuevosViajesSubscription?.cancel();
    _viajesActivosSubscription?.cancel();
    _detenerRastreoGlobal();
    super.dispose();
  }

  Future<void> _iniciarListeners() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final choferQuery = await FirebaseFirestore.instance
          .collection('choferes')
          .where('auth_uid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (choferQuery.docs.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      _choferId = choferQuery.docs.first.id;

      // Una vez que tenemos el ID del chofer, iniciamos el rastreo
      _iniciarRastreoGlobal();

      final nuevosViajesQuery = FirebaseFirestore.instance
          .collection('reservas')
          .where('chofer_asignado_id', isEqualTo: _choferId)
          .where('estado.principal', isEqualTo: 'Asignado')
          .where('estado.detalle', isEqualTo: 'Enviada al chofer');

      _nuevosViajesSubscription =
          nuevosViajesQuery.snapshots().listen((snapshot) {
        for (var change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            if (mounted) {
              _mostrarNotificacionDeViaje(
                  change.doc.id, change.doc.data() as Map<String, dynamic>?);
            }
          }
        }
      });

      final viajesActivosQuery = FirebaseFirestore.instance
          .collection('reservas')
          .where('chofer_asignado_id', isEqualTo: _choferId)
          .where('estado.principal',
              whereIn: ['Asignado', 'En Origen', 'Viaje Iniciado']);

      _viajesActivosSubscription =
          viajesActivosQuery.snapshots().listen((snapshot) {
        if (mounted) {
          setState(() {
            _viajesActivos.clear();
            _viajesActivos.addAll(snapshot.docs);
            _isLoading = false;
          });
        }
      });
    } catch (e) {
      print("Error al iniciar listeners: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // =======================================================================
  // FUNCIÓN DE RASTREO GLOBAL (REVISADA Y CON MEJORAS DE DEBUGGING)
  // =======================================================================
  Future<void> _iniciarRastreoGlobal() async {
    try {
      await _locationService.enableBackgroundMode(enable: true);

      final serviceEnabled = await _locationService.serviceEnabled();
      if (!serviceEnabled) {
        if (!await _locationService.requestService()) return;
      }

      var permissionGranted = await _locationService.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await _locationService.requestPermission();
        if (permissionGranted != PermissionStatus.granted) return;
      }

      if (_locationSubscription != null) {
        _locationSubscription?.cancel();
      }

      // Escuchamos los cambios de ubicación
      _locationSubscription =
          _locationService.onLocationChanged.handleError((error) {
        print("Error en el stream de ubicación: $error");
        _locationSubscription?.cancel();
        setState(() => _locationSubscription = null);
      }).listen((LocationData currentLocation) {
        if (currentLocation.latitude != null &&
            currentLocation.longitude != null) {
          // <<< MEJORA 1: Mensaje de confirmación en consola >>>
          print(
              'Enviando ubicación: Lat ${currentLocation.latitude}, Lng ${currentLocation.longitude}');

          FirebaseFunctions.instance
              .httpsCallable('actualizarUbicacionChofer')
              .call({
            'latitud': currentLocation.latitude,
            'longitud': currentLocation.longitude,
          })
              // <<< MEJORA 2: Captura de errores específicos de Firebase >>>
              .catchError((error) {
            // Si la llamada a la función falla, veremos el error aquí.
            print('Error al llamar a la función de Firebase: $error');
          });
        }
      });
    } catch (e) {
      print("Error al iniciar el rastreo de ubicación global: $e");
    }
  }

  Future<void> _detenerRastreoGlobal() async {
    _locationSubscription?.cancel();
    _locationSubscription = null;

    // Esta función borra las coordenadas del chofer en la base de datos
    // cuando cierra sesión o la app se cierra por completo. Es un comportamiento esperado.
    if (_choferId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('choferes')
            .doc(_choferId!)
            .update({'coordenadas': FieldValue.delete()});
        print('Coordenadas limpiadas al cerrar sesión.');
      } catch (e) {
        print("Error al limpiar coordenadas: $e");
      }
    }
  }

  void _mostrarNotificacionDeViaje(
      String reservaId, Map<String, dynamic>? viajeData) {
    if (viajeData == null || !mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('¡Nuevo Viaje Asignado!'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('Origen: ${viajeData['origen'] ?? 'N/A'}'),
                Text('Destino: ${viajeData['destino'] ?? 'N/A'}'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Rechazar'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            FilledButton(
              child: const Text('Aceptar'),
              onPressed: () {
                _aceptarViaje(reservaId);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _aceptarViaje(String reservaId) async {
    try {
      await FirebaseFirestore.instance
          .collection('reservas')
          .doc(reservaId)
          .update({
        'estado': {
          'principal': 'Asignado',
          'detalle': 'Aceptada',
          'actualizado_en': FieldValue.serverTimestamp(),
        }
      });
    } catch (e) {
      print("Error al aceptar el viaje: $e");
    }
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_viajesActivos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'No tienes viajes activos por el momento.\nEsperando nuevas asignaciones...',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, color: Colors.white70),
          ),
        ),
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
                'Destino: ${viaje['destino'] ?? 'N/A'}\nEstado: $estadoDetalle'),
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
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: _buildBody(),
    );
  }
}
