import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart';
import '../services/location_service.dart';
import '../utils/theme.dart';

/// Result of [MapPickerScreen]: the pinned point, the chosen range and the
/// reverse-geocoded address/city (may be empty).
class MapPickResult {
  final double lat;
  final double lng;
  final int radiusKm;
  final String address;
  final String city;
  const MapPickResult(this.lat, this.lng, this.radiusKm, this.address, this.city);
}

/// Full-screen OpenStreetMap picker (same behaviour as the website's
/// HS_MapPicker): the pin is fixed in the centre, the provider pans/zooms the
/// map under it, a circle shows the service range (1–30 km slider), and the
/// address is looked up whenever the map stops moving.
class MapPickerScreen extends StatefulWidget {
  final double? lat;
  final double? lng;
  final int radiusKm;
  final String title;
  final String confirmText;
  const MapPickerScreen({
    super.key,
    this.lat,
    this.lng,
    this.radiusKm = 5,
    this.title = 'Your service location & range',
    this.confirmText = 'Confirm location & range',
  });

  /// Opens the picker; returns null when the provider backs out.
  static Future<MapPickResult?> open(BuildContext context,
          {double? lat, double? lng, int radiusKm = 5, String? title, String? confirmText}) =>
      Navigator.push<MapPickResult>(
          context,
          MaterialPageRoute(
              builder: (_) => MapPickerScreen(
                    lat: lat,
                    lng: lng,
                    radiusKm: radiusKm,
                    title: title ?? 'Your service location & range',
                    confirmText: confirmText ?? 'Confirm location & range',
                  )));

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  static const int _minKm = 1, _maxKm = 30;
  static const LatLng _india = LatLng(20.5937, 78.9629);

  final _map = MapController();
  late LatLng _center;
  late int _radius;
  bool _ready = false;
  bool _locating = false;
  String _address = '';
  String _city = '';
  String _msg = '';
  bool _lookingUp = false;
  Timer? _idle;
  int _lookupSeq = 0;

  bool get _hasStart =>
      widget.lat != null && widget.lng != null && widget.lat != 0 && widget.lng != 0;

  @override
  void initState() {
    super.initState();
    _radius = widget.radiusKm.clamp(_minKm, _maxKm);
    _center = _hasStart ? LatLng(widget.lat!, widget.lng!) : _india;
  }

  @override
  void dispose() {
    _idle?.cancel();
    _map.dispose();
    super.dispose();
  }

  void _onMapReady() {
    _ready = true;
    if (_hasStart) {
      _fitRange();
      _scheduleLookup();
    } else {
      _locate();
    }
  }

  void _onMapEvent(MapEvent e) {
    _center = e.camera.center;
    if (mounted) setState(() {}); // circle follows the centre
    _scheduleLookup();
  }

  /// Reverse geocode once the map has been still for a moment.
  void _scheduleLookup() {
    _idle?.cancel();
    _idle = Timer(const Duration(milliseconds: 600), _lookup);
  }

  Future<void> _lookup() async {
    final seq = ++_lookupSeq;
    final c = _center;
    if (mounted) setState(() => _lookingUp = true);
    String addr = '', city = '';
    try {
      final marks = await placemarkFromCoordinates(c.latitude, c.longitude);
      if (marks.isNotEmpty) {
        final p = marks.first;
        final parts = <String>[];
        for (final x in [p.subThoroughfare, p.thoroughfare, p.subLocality, p.locality,
                         p.administrativeArea, p.postalCode]) {
          if (x != null && x.trim().isNotEmpty && !parts.contains(x.trim())) parts.add(x.trim());
        }
        addr = parts.join(', ');
        city = (p.locality?.isNotEmpty == true) ? p.locality! : (p.subAdministrativeArea ?? '');
      }
    } catch (_) {}
    if (!mounted || seq != _lookupSeq) return;
    setState(() {
      _lookingUp = false;
      _address = addr;
      _city = city;
    });
  }

  void _fitRange() {
    if (!_ready) return;
    const d = Distance();
    final m = _radius * 1000;
    final pts = [0, 90, 180, 270].map((b) => d.offset(_center, m, b)).toList();
    _map.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts), padding: const EdgeInsets.all(28)));
  }

  Future<void> _locate() async {
    if (_locating) return;
    setState(() { _locating = true; _msg = 'Getting your location…'; });
    final pos = await LocationService.currentPosition(ask: true);
    if (!mounted) return;
    if (pos == null) {
      setState(() {
        _locating = false;
        _msg = 'Location not available — move the map to your place.';
      });
      return;
    }
    setState(() { _locating = false; _msg = ''; });
    _center = LatLng(pos.latitude, pos.longitude);
    if (_ready) {
      _map.move(_center, 14);
      _fitRange();
    }
    _scheduleLookup();
  }

  void _confirm() {
    final c = _center;
    Navigator.pop(
        context,
        MapPickResult(double.parse(c.latitude.toStringAsFixed(7)),
            double.parse(c.longitude.toStringAsFixed(7)), _radius, _address, _city));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), backgroundColor: AppColors.teal),
      body: Column(children: [
        Expanded(
          child: Stack(children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: _center,
                initialZoom: _hasStart ? 13 : 5,
                minZoom: 3,
                maxZoom: 19,
                onMapReady: _onMapReady,
                onMapEvent: _onMapEvent,
                interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.hamaraservice.provider',
                  maxZoom: 19,
                ),
                CircleLayer(circles: [
                  CircleMarker(
                    point: _center,
                    radius: _radius * 1000.0,
                    useRadiusInMeter: true,
                    color: AppColors.teal.withOpacity(0.12),
                    borderColor: AppColors.teal,
                    borderStrokeWidth: 2,
                  ),
                ]),
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Container(
                    color: Colors.white.withOpacity(0.8),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: const Text('© OpenStreetMap contributors',
                        style: TextStyle(fontSize: 11, color: AppColors.ink2)),
                  ),
                ),
              ],
            ),
            // Fixed centre pin (tip of the icon on the centre point)
            const IgnorePointer(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 40),
                  child: Icon(Icons.location_on, size: 44, color: AppColors.red),
                ),
              ),
            ),
            if (_msg.isNotEmpty)
              Positioned(
                left: 12, right: 12, top: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFFF3CD), borderRadius: BorderRadius.circular(10)),
                  child: Text(_msg,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF7A5A00))),
                ),
              ),
            Positioned(
              right: 12, bottom: 28,
              child: ElevatedButton.icon(
                onPressed: _locating ? null : _locate,
                icon: _locating
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal))
                    : const Icon(Icons.my_location_rounded, size: 18, color: AppColors.teal),
                label: const Text('Use my current location',
                    style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700, fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  elevation: 3,
                  minimumSize: const Size(0, 42),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
              ),
            ),
          ]),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            decoration: BoxDecoration(color: Colors.white, boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, -2)),
            ]),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              const Text('SELECTED LOCATION',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.4)),
              const SizedBox(height: 4),
              Text(
                _lookingUp
                    ? 'Finding address…'
                    : _address.isNotEmpty
                        ? _address
                        : '${_center.latitude.toStringAsFixed(5)}, ${_center.longitude.toStringAsFixed(5)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink),
              ),
              const SizedBox(height: 10),
              Row(children: [
                const Expanded(
                    child: Text('Service range',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink))),
                Text('$_radius km',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.teal)),
              ]),
              Slider(
                value: _radius.toDouble(),
                min: _minKm.toDouble(),
                max: _maxKm.toDouble(),
                divisions: _maxKm - _minKm,
                activeColor: AppColors.teal,
                label: '$_radius km',
                onChanged: (v) => setState(() => _radius = v.round()),
                onChangeEnd: (_) => _fitRange(),
              ),
              ElevatedButton(
                onPressed: _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(widget.confirmText,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
