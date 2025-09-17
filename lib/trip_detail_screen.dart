import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:location/location.dart';
import 'package:cloud_functions/cloud_functions.dart'; // <-- 1. IMPORTAR

class TripDetailScreen extends StatefulWidget {
  final String reservaId;
  const TripDetailScreen({super.key, required this.reservaId});
  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  StreamSubscription? _viajeSubscription;
  Map<String, dynamic>? _viajeData;
  bool _isLoading = true;
  bool _isUpdatingState = false;

  final Location _locationService = Location();
  StreamSubscription<LocationData>? _locationSubscription;
  bool _isTrackingStarted = false;

  // <-- 2. CREAR INSTANCIA DE FUNCTIONS
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  @override
  void initState() {
    super.initState();
    _escucharDetallesDelViaje();
  }

  @override
  void dispose() {
    _viajeSubscription?.cancel();
    _detenerRastreoUbicacion();
    super.dispose();
  }

  void _escucharDetallesDelViaje() {
    final docRef =
        FirebaseFirestore.instance.collection('reservas').doc(widget.reservaId);
    _viajeSubscription = docRef.snapshots().listen((snapshot) {
      if (!snapshot.exists && mounted) {
        Navigator.of(context).pop();
        return;
      }
      if (mounted) {
        setState(() {
          _viajeData = snapshot.data();
          _isLoading = false;
        });
        _gestionarRastreo();
      }
    });
  }

  void _gestionarRastreo() {
    if (_viajeData == null || _isTrackingStarted) return;
    final estado = _viajeData!['estado'];
    if (estado is Map) {
      final estadoPrincipal = estado['principal'];
      if (['Asignado', 'En Origen', 'Viaje Iniciado']
          .contains(estadoPrincipal)) {
        _iniciarRastreoUbicacion();
        _isTrackingStarted = true;
      }
    }
  }

  Future<void> _iniciarRastreoUbicacion() async {
    try {
      final serviceEnabled = await _locationService.serviceEnabled();
      if (!serviceEnabled) {
        if (!await _locationService.requestService()) return;
      }

      var permissionGranted = await _locationService.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await _locationService.requestPermission();
        if (permissionGranted != PermissionStatus.granted) return;
      }

      _locationSubscription =
          _locationService.onLocationChanged.handleError((error) {
        print("Error en el stream de ubicación: $error");
        _locationSubscription?.cancel();
        setState(() => _locationSubscription = null);
      }).listen((LocationData currentLocation) async {
        if (currentLocation.latitude != null &&
            currentLocation.longitude != null) {
          final user = FirebaseAuth.instance.currentUser;
          if (user == null) return;

          final choferQuery = await FirebaseFirestore.instance
              .collection('choferes')
              .where('auth_uid', isEqualTo: user.uid)
              .limit(1)
              .get();
          if (choferQuery.docs.isNotEmpty) {
            final choferId = choferQuery.docs.first.id;
            await FirebaseFirestore.instance
                .collection('choferes')
                .doc(choferId)
                .update({
              'coordenadas': GeoPoint(
                  currentLocation.latitude!, currentLocation.longitude!)
            });
          }
        }
      });
    } catch (e) {
      print("Error al iniciar el rastreo de ubicación: $e");
    }
  }

  void _detenerRastreoUbicacion() {
    _locationSubscription?.cancel();
    _locationSubscription = null;
  }

  Future<void> _actualizarEstado(Map<String, dynamic> nuevoEstado) async {
    if (_isUpdatingState) return;
    setState(() => _isUpdatingState = true);
    try {
      await FirebaseFirestore.instance
          .collection('reservas')
          .doc(widget.reservaId)
          .update({
        'estado': {
          'principal': nuevoEstado['principal'],
          'detalle': nuevoEstado['detalle'],
          'actualizado_en': FieldValue.serverTimestamp(),
        }
      });
    } catch (e) {
      print("Error al actualizar estado: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isUpdatingState = false);
    }
  }

  // --- 4. NUEVA FUNCIÓN PARA LLAMAR AL BACKEND ---
  Future<void> _finalizarViaje() async {
    if (_isUpdatingState) return;
    setState(() => _isUpdatingState = true);
    try {
      final callable = _functions.httpsCallable('finalizarViajeDesdeApp');
      await callable.call({'reservaId': widget.reservaId});
      
      if (mounted) {
         Navigator.of(context).pop();
      }

    } on FirebaseFunctionsException catch (e) {
      print("Error al llamar a la Cloud Function: ${e.message}");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.message}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingState = false);
      }
    }
  }


  Widget _buildActionButtons() {
    if (_viajeData == null || _viajeData!['estado'] is! Map) {
      return const SizedBox.shrink();
    }

    final estado = _viajeData!['estado'] as Map<String, dynamic>;
    final estadoPrincipal = estado['principal'];
    final estadoDetalle = estado['detalle'];

    List<Widget> botones = [];

    if (estadoPrincipal == 'Asignado' && estadoDetalle == 'Enviada al chofer') {
      botones.add(
        FilledButton(
          onPressed: () => _actualizarEstado(
              {'principal': 'Asignado', 'detalle': 'Aceptada'}),
          style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 48)),
          child: const Text('Aceptar Viaje'),
        ),
      );
      botones.add(const SizedBox(height: 12));
      botones.add(
        OutlinedButton(
          onPressed: _rechazarViaje,
          style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48)),
          child: const Text('Rechazar Viaje',
              style: TextStyle(color: Colors.orangeAccent)),
        ),
      );
    }
    else if (estadoPrincipal == 'Asignado' && estadoDetalle == 'Aceptada') {
      botones.add(
        FilledButton.icon(
          icon: const Icon(Icons.navigation),
          label: const Text('Navegar al Origen'),
          onPressed: () => _abrirNavegacion(_viajeData!['origen']),
          style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 48)),
        ),
      );
      botones.add(const SizedBox(height: 12));
      botones.add(
        OutlinedButton(
          onPressed: () => _actualizarEstado(
              {'principal': 'En Origen', 'detalle': 'Pasajero a Bordo'}),
          style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48)),
          child: const Text('Pasajero a bordo'),
        ),
      );
      botones.add(const SizedBox(height: 12));
      botones.add(
        TextButton(
          onPressed: _marcarTrasladoNegativo,
          style: TextButton.styleFrom(
              minimumSize: const Size(double.infinity, 48)),
          child: const Text('Traslado Negativo',
              style: TextStyle(color: Colors.redAccent)),
        ),
      );
    }
    else if (estadoPrincipal == 'En Origen' ||
        estadoPrincipal == 'Viaje Iniciado') {
      botones.add(
        FilledButton.icon(
          icon: const Icon(Icons.navigation),
          label: const Text('Navegar al Destino'),
          onPressed: () => _abrirNavegacion(_viajeData!['destino']),
          style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 48)),
        ),
      );
      botones.add(const SizedBox(height: 12));
      botones.add(
        OutlinedButton(
          // --- 3. CAMBIAR LA LLAMADA EN EL BOTÓN ---
          onPressed: _finalizarViaje,
          style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48)),
          child: const Text('Finalizar Viaje'),
        ),
      );
    }

    return _isUpdatingState
        ? const Center(child: CircularProgressIndicator())
        : Column(children: botones);
  }

  Future<void> _rechazarViaje() async {
    if (_isUpdatingState) return;
    setState(() => _isUpdatingState = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      String nombreChofer = 'Chofer';
      if (user != null &&
          user.displayName != null &&
          user.displayName!.isNotEmpty) {
        nombreChofer = user.displayName!;
      }

      await FirebaseFirestore.instance
          .collection('reservas')
          .doc(widget.reservaId)
          .update({
        'estado': {
          'principal': 'En Curso',
          'detalle': 'Rechazado por $nombreChofer',
          'actualizado_en': FieldValue.serverTimestamp(),
        },
        'chofer_asignado_id': FieldValue.delete(),
        'movil_asignado_id': FieldValue.delete(),
      });
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      print("Error al rechazar viaje: $e");
    } finally {
      if (mounted) setState(() => _isUpdatingState = false);
    }
  }

  Future<void> _marcarTrasladoNegativo() async {
    if (_isUpdatingState) return;
    setState(() => _isUpdatingState = true);
    try {
      await FirebaseFirestore.instance
          .collection('reservas')
          .doc(widget.reservaId)
          .update({
        'estado': {
          'principal':
              'En Curso', 
          'detalle': 'Traslado negativo',
          'actualizado_en': FieldValue.serverTimestamp(),
        },
        'chofer_asignado_id': FieldValue.delete(),
        'movil_asignado_id': FieldValue.delete(),
      });
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      print("Error en traslado negativo: $e");
    } finally {
      if (mounted) setState(() => _isUpdatingState = false);
    }
  }

  Future<void> _abrirNavegacion(String? direccion) async {
    if (direccion == null || direccion.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La dirección no está disponible.')));
      return;
    }
    final Uri googleMapsUrl = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(direccion)}');
    try {
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No se pudo abrir Google Maps.')));
        }
      }
    } catch (e) {
      print('Error al lanzar URL: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle del Viaje')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _viajeData == null
              ? const Center(
                  child: Text('El viaje ha sido finalizado o cancelado.'))
              : _buildTripDetails(),
    );
  }

  Widget _buildTripDetails() {
    final pasajero = _viajeData!['nombre_pasajero'] ?? 'N/A';
    final telefono = _viajeData!['telefono_pasajero'] ?? 'N/A';
    final origen = _viajeData!['origen'] ?? 'N/A';
    final destino = _viajeData!['destino'] ?? 'N/A';
    final observaciones = _viajeData!['observaciones'] ?? 'Sin observaciones';

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: ListView(
              children: [
                _buildDetailRow(Icons.person, 'Pasajero', pasajero),
                _buildDetailRow(Icons.phone, 'Teléfono', telefono,
                    canCall: true),
                _buildDetailRow(Icons.trip_origin, 'Origen', origen),
                _buildDetailRow(Icons.flag, 'Destino', destino),
                _buildDetailRow(Icons.notes, 'Observaciones', observaciones),
              ],
            ),
          ),
        ),
        Padding(
          padding:
              const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: _buildActionButtons(),
        ),
      ],
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value,
      {bool canCall = false}) {
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: Colors.amber, size: 24),
          const SizedBox(width: 16),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label, style: const TextStyle(color: Colors.white70)),
                Text(value, style: const TextStyle(fontSize: 16))
              ])),
          if (canCall && value != 'N/A')
            IconButton(
              icon: const Icon(Icons.call),
              onPressed: () async {
                final Uri launchUri = Uri(scheme: 'tel', path: value);
                if (await canLaunchUrl(launchUri)) {
                  await launchUrl(launchUri);
                }
              },
            )
        ]));
  }
}