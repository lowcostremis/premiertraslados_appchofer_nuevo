// lib/trip_detail_screen.dart - VERSIÓN OPTIMIZADA PREMIER TRASLADOS

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_functions/cloud_functions.dart';

class TripDetailScreen extends StatefulWidget {
  final String reservaId;
  final Future<void> Function()? onStateChanged;

  const TripDetailScreen({
    super.key,
    required this.reservaId,
    this.onStateChanged,
  });

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  StreamSubscription? _viajeSubscription;
  Map<String, dynamic>? _viajeData;
  bool _isLoading = true;
  bool _isUpdatingState = false;

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  );

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
    final docRef = FirebaseFirestore.instance
        .collection('reservas')
        .doc(widget.reservaId);
    _viajeSubscription = docRef.snapshots().listen((snapshot) {
      if (snapshot.exists && mounted) {
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
      await widget.onStateChanged?.call();
    } catch (e) {
      debugPrint("Error al actualizar estado: $e");
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
      if (mounted) Navigator.of(context).pop();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al finalizar: ${e.message}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingState = false);
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
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al procesar la solicitud'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingState = false);
    }
  }

  Future<void> _abrirNavegacion(String? direccion) async {
    if (direccion == null || direccion.isEmpty) return;

    // Se usa el esquema nativo de Google Maps para navegación directa
    final Uri googleMapsUrl = Uri.parse("google.navigation:q=${Uri.encodeComponent(direccion)}");

    try {
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl);
      } else {
        // Fallback a URL de navegador si el esquema nativo falla
        final Uri webMapsUrl = Uri.parse("https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(direccion)}");
        await launchUrl(webMapsUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error al lanzar navegación: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle del Viaje')),
      body: _isLoading || _viajeData == null
          ? const Center(child: CircularProgressIndicator())
          : _buildTripDetails(),
      backgroundColor: const Color(0xFF1c1c1e),
    );
  }

  Widget _buildTripDetails() {
    final cliente = _viajeData!['cliente_nombre'] ?? 'N/A';
    final pasajero = _viajeData!['nombre_pasajero'] ?? 'N/A';
    final telefono = _viajeData!['telefono_pasajero'] ?? 'N/A';
    final horaTurno = _viajeData!['hora_turno'] ?? '';
    final horaPickup = _viajeData!['hora_pickup'] ?? '';
    final origenRaw = _viajeData!['origen'] ?? 'N/A';
    final destino = _viajeData!['destino'] ?? 'N/A';
    final observaciones = _viajeData!['observaciones'] ?? 'Sin observaciones';

    // Desglosar Multi-Origen (Paradas)
    List<String> paradas = origenRaw.toString().split(' + ');

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: ListView(
              children: [
                _buildDetailRow(Icons.person, 'Pasajero', pasajero),
                _buildDetailRow(Icons.phone, 'Teléfono', telefono, canCall: true, canWhatsApp: true),
                if (horaPickup.isNotEmpty) _buildDetailRow(Icons.watch_later_outlined, 'Hora Pick Up', horaPickup),
                if (horaTurno.isNotEmpty) _buildDetailRow(Icons.access_time, 'Hora Turno', horaTurno),
                _buildDetailRow(Icons.business, 'Cliente', cliente),

                // Renderizado de paradas
                ...paradas.asMap().entries.map((entry) {
                  int idx = entry.key;
                  String dir = entry.value;
                  return _buildDetailRow(
                    idx == 0 ? Icons.trip_origin : Icons.location_on,
                    idx == 0 ? 'Origen' : 'Parada ${idx + 1}',
                    dir,
                    canNavigate: true,
                  );
                }),

                _buildDetailRow(Icons.flag, 'Destino', destino, canNavigate: true),
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

  Widget _buildActionButtons() {
    if (_viajeData == null || _viajeData!['estado'] is! Map) return const SizedBox.shrink();

    final estado = _viajeData!['estado'] as Map<String, dynamic>;
    final String principal = estado['principal'] ?? '';
    final String detalle = estado['detalle'] ?? '';
    List<Widget> botones = [];

    // Sincronizado con reservas.js: el sistema web envía detalle "Enviada" o "Enviada al chofer"
    if (principal == 'Asignado' && (detalle == 'Enviada' || detalle == 'Enviada al chofer')) {
      botones.add(
        FilledButton(
          onPressed: () => _actualizarEstado({'principal': 'Asignado', 'detalle': 'Aceptada'}),
          style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48), backgroundColor: Colors.amber),
          child: const Text('ACEPTAR VIAJE', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
        ),
      );
      botones.add(const SizedBox(height: 12));
      botones.add(
        OutlinedButton(
          onPressed: () => _gestionarRechazoONegativo(esNegativo: false),
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48), side: const BorderSide(color: Colors.orange)),
          child: const Text('RECHAZAR', style: TextStyle(color: Colors.orange)),
        ),
      );
    }
    else if (principal == 'Asignado' && detalle == 'Aceptada') {
      botones.add(
        FilledButton.icon(
          icon: const Icon(Icons.navigation, color: Colors.black),
          label: const Text('NAVEGAR AL ORIGEN', style: TextStyle(color: Colors.black)),
          onPressed: () => _abrirNavegacion(_viajeData!['origen'].toString().split(' + ')[0]),
          style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48), backgroundColor: Colors.amber),
        ),
      );
      botones.add(const SizedBox(height: 12));
      botones.add(
        OutlinedButton(
          onPressed: () => _actualizarEstado({'principal': 'En Origen', 'detalle': 'Pasajero a Bordo'}),
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48), side: const BorderSide(color: Colors.greenAccent)),
          child: const Text('PASAJERO A BORDO', style: TextStyle(color: Colors.greenAccent)),
        ),
      );
      botones.add(const SizedBox(height: 12));
      botones.add(
        TextButton(
          onPressed: () => _gestionarRechazoONegativo(esNegativo: true),
          child: const Text('TRASLADO NEGATIVO', style: TextStyle(color: Colors.redAccent)),
        ),
      );
    }
    else if (principal == 'En Origen' || principal == 'Viaje Iniciado') {
      botones.add(
        FilledButton.icon(
          icon: const Icon(Icons.navigation, color: Colors.black),
          label: const Text('NAVEGAR AL DESTINO', style: TextStyle(color: Colors.black)),
          onPressed: () => _abrirNavegacion(_viajeData!['destino']),
          style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48), backgroundColor: Colors.amber),
        ),
      );
      botones.add(const SizedBox(height: 12));
      botones.add(
        OutlinedButton(
          onPressed: _finalizarViaje,
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48), side: const BorderSide(color: Colors.green, width: 2)),
          child: const Text('FINALIZAR VIAJE', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
        ),
      );
    }

    return _isUpdatingState ? const CircularProgressIndicator() : Column(children: botones);
  }

  Widget _buildDetailRow(IconData icon, String label, String value, {bool canCall = false, bool canWhatsApp = false, bool canNavigate = false}) {
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
                Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                Text(value, style: const TextStyle(fontSize: 15, color: Colors.white)),
              ],
            ),
          ),
          if (canCall && value.isNotEmpty && value != 'N/A')
            IconButton(icon: const Icon(Icons.call, color: Colors.greenAccent), onPressed: () => launchUrl(Uri(scheme: 'tel', path: value))),
          if (canWhatsApp && value.isNotEmpty && value != 'N/A')
            IconButton(icon: const Icon(Icons.message, color: Color(0xFF25D366)), onPressed: () {
              String num = value.replaceAll(RegExp(r'\D'), '');
              if (num.length == 10) num = '549$num';
              launchUrl(Uri.parse('https://wa.me/$num'), mode: LaunchMode.externalApplication);
            }),
          if (canNavigate)
            IconButton(icon: const Icon(Icons.navigation_outlined, color: Colors.lightBlueAccent), onPressed: () => _abrirNavegacion(value)),
        ],
      ),
    );
  }
}