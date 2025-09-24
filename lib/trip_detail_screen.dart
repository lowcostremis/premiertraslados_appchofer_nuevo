import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_functions/cloud_functions.dart';

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

  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  @override
  void initState() {
    super.initState();
    _escucharDetallesDelViaje();
  }

  @override
  void dispose() {
    _viajeSubscription?.cancel();
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
      }
    });
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
        },
      });
    } catch (e) {
      print("Error al actualizar estado: $e");
    } finally {
      if (mounted) setState(() => _isUpdatingState = false);
    }
  }

  Future<void> _finalizarViaje() async {
    if (_isUpdatingState) return;
    setState(() => _isUpdatingState = true);
    try {
      final callable = _functions.httpsCallable('finalizarViajeDesdeApp');
      await callable.call({'reservaId': widget.reservaId});
    } on FirebaseFunctionsException catch (e) {
      print("Error al llamar a la Cloud Function: ${e.message}");
      if (mounted) {
        setState(() => _isUpdatingState = false);
      }
    }
  }

  Future<void> _gestionarRechazoONegativo({required bool esNegativo}) async {
    if (_isUpdatingState) return;
    setState(() => _isUpdatingState = true);
    try {
      final callable = _functions.httpsCallable('gestionarRechazoDesdeApp');
      await callable.call({
        'reservaId': widget.reservaId,
        'esNegativo': esNegativo,
      });
    } on FirebaseFunctionsException catch (e) {
      print("Error al gestionar rechazo/negativo: ${e.message}");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
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
          onPressed: () => _actualizarEstado({
            'principal': 'Asignado',
            'detalle': 'Aceptada',
          }),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
          child: const Text('Aceptar Viaje'),
        ),
      );
      botones.add(const SizedBox(height: 12));
      botones.add(
        OutlinedButton(
          onPressed: () => _gestionarRechazoONegativo(esNegativo: false),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
          child: const Text(
            'Rechazar Viaje',
            style: TextStyle(color: Colors.orangeAccent),
          ),
        ),
      );
    } else if (estadoPrincipal == 'Asignado' && estadoDetalle == 'Aceptada') {
      botones.add(
        FilledButton.icon(
          icon: const Icon(Icons.navigation),
          label: const Text('Navegar al Origen'),
          onPressed: () => _abrirNavegacion(_viajeData!['origen']),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
      );
      botones.add(const SizedBox(height: 12));
      botones.add(
        OutlinedButton(
          onPressed: () => _actualizarEstado({
            'principal': 'En Origen',
            'detalle': 'Pasajero a Bordo',
          }),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
          child: const Text('Pasajero a bordo'),
        ),
      );
      botones.add(const SizedBox(height: 12));
      botones.add(
        TextButton(
          onPressed: () => _gestionarRechazoONegativo(esNegativo: true),
          style: TextButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
          child: const Text(
            'Traslado Negativo',
            style: TextStyle(color: Colors.redAccent),
          ),
        ),
      );
    } else if (estadoPrincipal == 'En Origen' ||
        estadoPrincipal == 'Viaje Iniciado') {
      botones.add(
        FilledButton.icon(
          icon: const Icon(Icons.navigation),
          label: const Text('Navegar al Destino'),
          onPressed: () => _abrirNavegacion(_viajeData!['destino']),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
      );
      botones.add(const SizedBox(height: 12));
      botones.add(
        OutlinedButton(
          onPressed: _finalizarViaje,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
          child: const Text('Finalizar Viaje'),
        ),
      );
    }

    return _isUpdatingState
        ? const Center(child: CircularProgressIndicator())
        : Column(children: botones);
  }

  Future<void> _abrirNavegacion(String? direccion) async {
    if (direccion == null || direccion.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La dirección no está disponible.')),
      );
      return;
    }
    final Uri googleMapsUrl = Uri.parse(
      'google.navigation:q=${Uri.encodeComponent(direccion)}',
    );
    try {
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo abrir Google Maps.')),
          );
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
                  child: Text('El viaje ha sido finalizado o cancelado.'),
                )
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
                _buildDetailRow(
                  Icons.phone,
                  'Teléfono',
                  telefono,
                  canCall: true,
                  canWhatsApp: true,
                ),
                _buildDetailRow(Icons.trip_origin, 'Origen', origen),
                _buildDetailRow(Icons.flag, 'Destino', destino),
                _buildDetailRow(Icons.notes, 'Observaciones', observaciones),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: _buildActionButtons(),
        ),
      ],
    );
  }

  Widget _buildDetailRow(
    IconData icon,
    String label,
    String value, {
    bool canCall = false,
    bool canWhatsApp = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.amber, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white70)),
                Text(value, style: const TextStyle(fontSize: 16)),
              ],
            ),
          ),
          if (canCall && value.isNotEmpty && value != 'N/A')
            IconButton(
              icon: const Icon(Icons.call, color: Colors.greenAccent),
              tooltip: 'Llamar al pasajero',
              onPressed: () async {
                final Uri launchUri = Uri(scheme: 'tel', path: value);
                if (await canLaunchUrl(launchUri)) {
                  await launchUrl(launchUri);
                }
              },
            ),
          if (canWhatsApp && value.isNotEmpty && value != 'N/A')
            IconButton(
              icon: const Icon(Icons.message, color: Color(0xFF25D366)),
              tooltip: 'Enviar WhatsApp al pasajero',
              onPressed: () async {
                String numeroLimpio = value.replaceAll(RegExp(r'[^\d]'), '');
                if (!numeroLimpio.startsWith('54')) {
                  numeroLimpio = '54$numeroLimpio';
                }
                final Uri launchUri = Uri.parse('https://wa.me/$numeroLimpio');
                if (await canLaunchUrl(launchUri)) {
                  await launchUrl(launchUri,
                      mode: LaunchMode.externalApplication);
                }
              },
            ),
        ],
      ),
    );
  }
}
