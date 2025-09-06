import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart'; // <-- LÍNEA CORREGIDA
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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

  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _escucharDetallesDelViaje();
  }

  @override
  void dispose() {
    _viajeSubscription?.cancel();
    _mapController?.dispose();
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
        _updateMarkersAndCamera();
      }
    });
  }

  Future<void> _actualizarEstado(String nuevoEstado) async {
    if (_isUpdatingState) return;
    setState(() => _isUpdatingState = true);

    try {
      final actualizar = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('actualizarEstadoViaje');
      final result = await actualizar.call({
        'reservaId': widget.reservaId,
        'nuevoEstado': nuevoEstado,
      });
      print(result.data['message']);
    } on FirebaseFunctionsException catch (e) {
      print("Error al llamar a la función: ${e.code} - ${e.message}");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: ${e.message ?? 'No se pudo actualizar'}'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingState = false);
    }
  }

  Widget _buildActionButtons() {
    if (_viajeData == null) return const SizedBox.shrink();

    final estado = _viajeData!['estado'];
    String buttonText = '';
    String nextState = '';
    VoidCallback? onPressed;

    final origen = _viajeData!['origen'] ?? '';
    final destino = _viajeData!['destino'] ?? '';

    switch (estado) {
      case 'Aceptado':
        buttonText = 'Llegué al Origen';
        nextState = 'En Origen';
        onPressed = () => _actualizarEstado(nextState);
        break;
      case 'En Origen':
        buttonText = 'Iniciar Viaje';
        nextState = 'Viaje Iniciado';
        onPressed = () => _actualizarEstado(nextState);
        break;
      case 'Viaje Iniciado':
        buttonText = 'Finalizar Viaje';
        nextState = 'Finalizado';
        onPressed = () => _actualizarEstado(nextState);
        break;
      default:
        return const SizedBox.shrink();
    }

    Widget mainButton = SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16)),
        onPressed: _isUpdatingState ? null : onPressed,
        child: _isUpdatingState
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 3))
            : Text(buttonText),
      ),
    );

    Widget navButton = OutlinedButton.icon(
      icon: const Icon(Icons.navigation),
      label: Text(estado == 'Viaje Iniciado'
          ? 'Navegar al Destino'
          : 'Navegar al Origen'),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: Theme.of(context).colorScheme.secondary),
      ),
      onPressed: () =>
          _abrirNavegacion(estado == 'Viaje Iniciado' ? destino : origen),
    );

    return Column(
      children: [
        SizedBox(width: double.infinity, child: navButton),
        const SizedBox(height: 12),
        mainButton,
      ],
    );
  }

  void _updateMarkersAndCamera() {
    if (_viajeData == null || _mapController == null) return;
    final origenCoords = _viajeData!['origen_coords'] as GeoPoint?;
    final destinoCoords = _viajeData!['destino_coords'] as GeoPoint?;
    _markers.clear();
    if (origenCoords != null) {
      _markers.add(Marker(
          markerId: const MarkerId('origen'),
          position: LatLng(origenCoords.latitude, origenCoords.longitude),
          infoWindow: const InfoWindow(title: 'Origen'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen)));
    }
    if (destinoCoords != null) {
      _markers.add(Marker(
          markerId: const MarkerId('destino'),
          position: LatLng(destinoCoords.latitude, destinoCoords.longitude),
          infoWindow: const InfoWindow(title: 'Destino')));
    }
    if (origenCoords != null && destinoCoords != null) {
      LatLngBounds bounds = LatLngBounds(
          southwest: LatLng(
              origenCoords.latitude < destinoCoords.latitude
                  ? origenCoords.latitude
                  : destinoCoords.latitude,
              origenCoords.longitude < destinoCoords.longitude
                  ? origenCoords.longitude
                  : destinoCoords.longitude),
          northeast: LatLng(
              origenCoords.latitude > destinoCoords.latitude
                  ? origenCoords.latitude
                  : destinoCoords.latitude,
              origenCoords.longitude > destinoCoords.longitude
                  ? origenCoords.longitude
                  : destinoCoords.longitude));
      _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
    } else if (origenCoords != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLngZoom(
          LatLng(origenCoords.latitude, origenCoords.longitude), 14));
    }
    setState(() {});
  }

  Future<void> _abrirNavegacion(String? direccion) async {
    if (direccion == null || direccion.isEmpty) {
      print('La dirección de destino está vacía.');
      return;
    }
    final Uri googleMapsUrl = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(direccion)}');
    try {
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      } else {
        print('No se pudo abrir Google Maps');
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
              ? const Center(child: Text('El viaje ha sido finalizado.'))
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
        SizedBox(
            height: 250,
            child: GoogleMap(
                onMapCreated: (controller) {
                  _mapController = controller;
                  _updateMarkersAndCamera();
                },
                initialCameraPosition: const CameraPosition(
                    target: LatLng(-32.9575, -60.6393), zoom: 12),
                markers: _markers)),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: ListView(
              children: [
                _buildDetailRow(Icons.person, 'Pasajero', pasajero),
                _buildDetailRow(Icons.phone, 'Teléfono', telefono),
                _buildDetailRow(Icons.trip_origin, 'Origen', origen),
                _buildDetailRow(Icons.flag, 'Destino', destino),
                _buildDetailRow(Icons.notes, 'Observaciones', observaciones),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: _buildActionButtons(),
        ),
      ],
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
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
              ]))
        ]));
  }
}
