import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:premiertraslados_appchofer_nuevo/login_screen.dart'; // Importa la pantalla de login

// Asegúrate de tener estos dos imports para Firestore
import 'package:cloud_firestore/cloud_firestore.dart';

// --- NUEVA PANTALLA DE INICIO (CON ESTADO Y CONEXIÓN A FIRESTORE) ---

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = true;
  final List<DocumentSnapshot> _viajes = [];

  @override
  void initState() {
    super.initState();
    _fetchViajesAsignados();
  }

  Future<void> _fetchViajesAsignados() async {
    // Obtener el usuario actual de Firebase Auth
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // Si por alguna razón no hay usuario, no hacer nada.
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      // Consultar a Firestore
      final querySnapshot = await FirebaseFirestore.instance
          .collection('viajes') // <-- ¡AJUSTA ESTE NOMBRE SI ES DIFERENTE!
          .where(
            'driverId',
            isEqualTo: user.uid,
          ) // <-- ¡AJUSTA ESTE CAMPO SI ES DIFERENTE!
          .get();

      // Guardar los resultados en nuestra lista local
      setState(() {
        _viajes.clear();
        _viajes.addAll(querySnapshot.docs);
        _isLoading = false;
      });
    } catch (e) {
      print("Error al obtener viajes: $e");
      setState(() {
        _isLoading = false;
      });
      // Aquí podrías mostrar un SnackBar con el error si quisieras
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Viajes Asignados'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      // 1. Muestra el círculo de carga
      return const Center(child: CircularProgressIndicator());
    }

    if (_viajes.isEmpty) {
      // 2. Muestra el mensaje si no hay viajes
      return const Center(
        child: Text(
          'No tienes viajes asignados por el momento.',
          style: TextStyle(fontSize: 18),
        ),
      );
    }

    // 3. Muestra la lista de viajes
    return ListView.builder(
      itemCount: _viajes.length,
      itemBuilder: (context, index) {
        // Obtenemos los datos de un viaje específico
        final viaje = _viajes[index].data() as Map<String, dynamic>;

        // Extraemos los datos que queremos mostrar (ajusta los nombres de los campos)
        final origen = viaje['domicilio_origen'] ?? 'Origen no especificado';
        final destino = viaje['domicilio_destino'] ?? 'Destino no especificado';
        final fecha = viaje['fecha_turno'] ?? 'Fecha no disponible';

        // Creamos una tarjeta para mostrar la información
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            title: Text('Viaje del $fecha'),
            subtitle: Text('Desde: $origen\nHasta: $destino'),
            isThreeLine: true,
          ),
        );
      },
    );
  }
}

// --- El resto de tu archivo main.dart (MyApp, AuthWrapper, etc.) se mantiene igual ---
// ... (void main, MyApp, AuthWrapper)

// --- Punto de Entrada de la Aplicación ---
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
        // --- CORRECCIÓN APLICADA AQUÍ ---
        // Se especifica que la paleta de colores debe ser oscura desde su creación.
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.amber,
          brightness: Brightness.dark, // Se añade esta línea
        ),
        useMaterial3: true,
        // Ya no es necesario 'brightness' aquí, porque se infiere del colorScheme.
      ),
      home: const AuthWrapper(),
    );
  }
}

// --- AuthWrapper: El Controlador de Sesión ---
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
          return const HomeScreen();
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}
