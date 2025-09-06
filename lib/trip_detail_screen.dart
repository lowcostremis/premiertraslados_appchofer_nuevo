import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:location/location.dart'; // <-- 1. IMPORTAMOS LOCATION

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

  // --- 2. VARIABLES PARA EL RASTREO DE UBICACIÓN ---
  final Location _locationService = Location();
  StreamSubscription<LocationData>? _locationSubscription;
  bool _isTrackingStarted = false;
  // ---

  @override
  void initState() {
    super.initState();
    _escucharDetallesDelViaje();
  }

  @override
  void dispose() {
    _viajeSubscription?.cancel();
    _detenerRastreoUbicacion(); // Detenemos el rastreo al salir
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
        _gestionarRastreo(); // Gestionamos si el rastreo debe iniciar o no
      }
    });
  }

  // --- 3. NUEVA LÓGICA DE RASTREO ---
  void _gestionarRastreo() {
    if (_viajeData == null || _isTrackingStarted) return;

    final estado = _viajeData!['estado'];
    if (estado is Map) {
      final estadoPrincipal = estado['principal'];
      // Inicia el rastreo si el viaje está confirmado, en origen o en curso
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
      }).listen((LocationData currentLocation) {
        if (currentLocation.latitude != null &&
            currentLocation.longitude != null) {
          FirebaseFunctions.instanceFor(region: 'us-central1')
              .httpsCallable('actualizarUbicacionChofer')
              .call({
            'latitud': currentLocation.latitude,
            'longitud': currentLocation.longitude,
          });
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
  // --- FIN DE LÓGICA DE RASTREO ---

  // --- 4. FUNCIÓN _actualizarEstado MODIFICADA ---
  Future<void> _actualizarEstado(Map<String, dynamic> nuevoEstado) async {
    if (_isUpdatingState) return;
    setState(() => _isUpdatingState = true);

    // Añadimos el timestamp desde el cliente para referencia
    nuevoEstado['actualizado_en'] = FieldValue.serverTimestamp();

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

  // --- 5. LÓGICA DE BOTONES COMPLETAMENTE RECONSTRUIDA ---
  Widget _buildActionButtons() {
    if (_viajeData == null || !(_viajeData!['estado'] is Map)) {
      return const SizedBox.shrink();
    }

    final estado = _viajeData!['estado'] as Map<String, dynamic>;
    final estadoPrincipal = estado['principal'];
    final estadoDetalle = estado['detalle'];

    String buttonText = '';
    Map<String, dynamic> nextState = {};
    VoidCallback? onPressed;

    final origen = _viajeData!['origen'] ?? '';
    final destino = _viajeData!['destino'] ?? '';

    switch (estadoPrincipal) {
      case 'Asignado':
        if (estadoDetalle == 'Enviada al chofer') {
          buttonText = 'Confirmar Viaje';
          nextState = {
            'principal': 'Asignado',
            'detalle': 'Confirmada por chofer'
          };
        } else {
          // 'Confirmada por chofer'
          buttonText = 'Llegué al Origen';
          nextState = {
            'principal': 'En Origen',
            'detalle': 'Chofer en domicilio'
          };
        }
        onPressed = () => _actualizarEstado(nextState);
        break;
      case 'En Origen':
        buttonText = 'Iniciar Viaje (Pasajero a Bordo)';
        nextState = {
          'principal': 'Viaje Iniciado',
          'detalle': 'Pasajero a Bordo'
        };
        onPressed = () => _actualizarEstado(nextState);
        break;
      case 'Viaje Iniciado':
        buttonText = 'Finalizar Viaje';
        nextState = {
          'principal': 'Finalizado',
          'detalle': 'Traslado Concluido'
        };
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
      label: Text(estadoPrincipal == 'Viaje Iniciado'
          ? 'Navegar al Destino'
          : 'Navegar al Origen'),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: Theme.of(context).colorScheme.secondary),
      ),
      onPressed: () => _abrirNavegacion(
          estadoPrincipal == 'Viaje Iniciado' ? destino : origen),
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
    if (mounted) setState(() {});
  }

  // --- 6. FUNCIÓN DE NAVEGACIÓN CORREGIDA ---
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
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No se pudo abrir Google Maps.')));
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
          padding: const EdgeInsets.all(16.0),
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
