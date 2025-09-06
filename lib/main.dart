import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:premiertraslados_appchofer_nuevo/login_screen.dart';
// --- ADAPTACIÓN: Importamos la nueva pantalla de detalles ---
import 'package:premiertraslados_appchofer_nuevo/trip_detail_screen.dart';

// El resto de la app (main, MyApp, AuthWrapper) no necesita cambios.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
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

// =======================================================================
// --- PANTALLA DE INICIO CON LISTA DE VIAJES ACTIVOS ---
// =======================================================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription? _nuevosViajesSubscription;
  StreamSubscription? _viajesAceptadosSubscription;
  String? _choferId;
  final List<DocumentSnapshot> _viajesAceptados = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _iniciarListeners();
  }

  @override
  void dispose() {
    _nuevosViajesSubscription?.cancel();
    _viajesAceptadosSubscription?.cancel();
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
        setState(() => _isLoading = false);
        return;
      }
      _choferId = choferQuery.docs.first.id;

      final nuevosViajesQuery = FirebaseFirestore.instance
          .collection('reservas')
          .where('chofer_asignado_id', isEqualTo: _choferId)
          .where('estado', isEqualTo: 'Asignado');

      _nuevosViajesSubscription =
          nuevosViajesQuery.snapshots().listen((snapshot) {
        for (var change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            if (mounted) {
              _mostrarNotificacionDeViaje(change.doc.id, change.doc.data());
            }
          }
        }
      });

      final viajesAceptadosQuery = FirebaseFirestore.instance
          .collection('reservas')
          .where('chofer_asignado_id', isEqualTo: _choferId)
          .where('estado', isEqualTo: 'Aceptado');

      _viajesAceptadosSubscription =
          viajesAceptadosQuery.snapshots().listen((snapshot) {
        setState(() {
          _viajesAceptados.clear();
          _viajesAceptados.addAll(snapshot.docs);
          _isLoading = false;
        });
      });
    } catch (e) {
      print("Error al iniciar listeners: $e");
      if (mounted) setState(() => _isLoading = false);
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
          .update({'estado': 'Aceptado'});
    } catch (e) {
      print("Error al aceptar el viaje: $e");
    }
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_viajesAceptados.isEmpty) {
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
      itemCount: _viajesAceptados.length,
      itemBuilder: (context, index) {
        final viajeDoc = _viajesAceptados[index];
        final viaje = viajeDoc.data() as Map<String, dynamic>;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: const Icon(Icons.directions_car, color: Colors.amber),
            title: Text('Origen: ${viaje['origen'] ?? 'N/A'}'),
            subtitle: Text(
                'Destino: ${viaje['destino'] ?? 'N/A'}\nPasajero: ${viaje['nombre_pasajero'] ?? 'N/A'}'),
            isThreeLine: true,
            // --- ADAPTACIÓN: Lógica de navegación a la pantalla de detalle ---
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
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }
}
