import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../models/user_profile.dart';
import '../../providers/user_role_provider.dart';
import '../../services/attendance_service.dart';
import '../../services/google_places_service.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_loader.dart';

class ChurchLocationPickerScreen extends StatefulWidget {
  const ChurchLocationPickerScreen({super.key});

  @override
  State<ChurchLocationPickerScreen> createState() =>
      _ChurchLocationPickerScreenState();
}

class _ChurchLocationPickerScreenState
    extends State<ChurchLocationPickerScreen> {
  static const LatLng _jamaicaCenter = LatLng(18.1096, -77.2975);

  final AttendanceService _attendanceService = AttendanceService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _latitudeController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();

  GoogleMapController? _mapController;
  LatLng _selectedPosition = _jamaicaCenter;
  double _radiusMeters = 150;
  String? _selectedAddress;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isSearching = false;
  bool _isLocating = false;
  List<GooglePlaceResult> _searchResults = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCurrentLocation());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  bool get _supportsInteractiveMap =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  bool _canManageAttendanceSetup(UserProfile user) {
    if (user.capabilities.canManageSchedules ||
        user.capabilities.canManageMembersBasic) {
      return true;
    }

    const allowedRoles = {
      'pastor',
      'senior_pastor',
      'assistant_pastor',
      'acting_pastor',
      'admin',
      'church_admin',
      'administrator',
      'secretary',
      'church_secretary',
      'head_usher',
      'attendance_scanner',
    };

    return user.roles
        .map((role) => role
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
            .replaceAll(RegExp(r'_+'), '_')
            .replaceAll(RegExp(r'^_|_$'), ''))
        .any(allowedRoles.contains);
  }

  Future<void> _loadCurrentLocation() async {
    final user = context.read<UserRoleProvider>().user;
    if (user == null) return;

    try {
      final current = await _attendanceService.getChurchLocation(user.churchId);
      if (!mounted) return;

      if (current != null) {
        _selectedPosition = LatLng(current.latitude, current.longitude);
        _radiusMeters = current.radiusMeters.clamp(50, 500).toDouble();
      }
      _syncCoordinateFields();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load church location: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _searchPlaces() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchResults = const [];
    });

    try {
      final results = await GooglePlacesService.searchChurchLocations(query);
      if (!mounted) return;
      setState(() => _searchResults = results);
      if (results.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No places found. Tap the map to place the pin.'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Search unavailable. Tap the map to place the pin: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _useCurrentDeviceLocation() async {
    setState(() => _isLocating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        throw Exception('Location permission was not granted.');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      await _movePin(
        LatLng(position.latitude, position.longitude),
        address: 'Current device location',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not use current location: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _movePin(LatLng position, {String? address}) async {
    setState(() {
      _selectedPosition = position;
      _selectedAddress = address;
      _syncCoordinateFields();
    });
    await _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(position, 17),
    );
  }

  void _syncCoordinateFields() {
    _latitudeController.text = _selectedPosition.latitude.toStringAsFixed(6);
    _longitudeController.text = _selectedPosition.longitude.toStringAsFixed(6);
  }

  void _applyManualCoordinates() {
    final latitude = double.tryParse(_latitudeController.text.trim());
    final longitude = double.tryParse(_longitudeController.text.trim());

    if (latitude == null ||
        longitude == null ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid latitude and longitude.')),
      );
      return;
    }

    unawaited(_movePin(
      LatLng(latitude, longitude),
      address: 'Manual coordinates',
    ));
  }

  Future<void> _saveLocation(UserProfile user) async {
    setState(() => _isSaving = true);
    try {
      await _attendanceService.saveChurchLocation(
        churchId: user.churchId,
        latitude: _selectedPosition.latitude,
        longitude: _selectedPosition.longitude,
        radiusMeters: _radiusMeters,
        address: _selectedAddress,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Church geofence saved.')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save church geofence: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = context.watch<UserRoleProvider>().user;

    if (user == null || _isLoading) {
      return const Scaffold(body: Center(child: AppLoader()));
    }

    if (!_canManageAttendanceSetup(user)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Church Location')),
        body: const Center(
          child: Text('You do not have access to manage attendance setup.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Church Geofence',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w800),
        ),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : () => _saveLocation(user),
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Save'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          AppCard(
            color: theme.colorScheme.surfaceContainerHigh,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Place the church pin',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Members can only mark present when they are inside this radius during an active recurring service.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _searchPlaces(),
                  decoration: const InputDecoration(
                    labelText: 'Search church or address',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _isSearching ? null : _searchPlaces,
                icon: _isSearching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: const Text('Search'),
              ),
            ],
          ),
          if (_searchResults.isNotEmpty) ...[
            const SizedBox(height: 8),
            AppCard(
              child: Column(
                children: [
                  for (final place in _searchResults.take(5))
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.place_outlined),
                      title: Text(place.name),
                      subtitle: Text(place.address),
                      onTap: place.latitude == null || place.longitude == null
                          ? null
                          : () => _movePin(
                                LatLng(place.latitude!, place.longitude!),
                                address: place.address,
                              ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          _supportsInteractiveMap
              ? SizedBox(
                  height: 420,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: _selectedPosition,
                        zoom: _selectedPosition == _jamaicaCenter ? 8 : 17,
                      ),
                      markers: {
                        Marker(
                          markerId: const MarkerId('church_location'),
                          position: _selectedPosition,
                          draggable: true,
                          onDragEnd: (position) {
                            setState(() {
                              _selectedPosition = position;
                              _selectedAddress = 'Pinned location';
                              _syncCoordinateFields();
                            });
                          },
                        ),
                      },
                      circles: {
                        Circle(
                          circleId: const CircleId('church_radius'),
                          center: _selectedPosition,
                          radius: _radiusMeters,
                          fillColor: theme.colorScheme.primary.withValues(
                            alpha: 0.16,
                          ),
                          strokeColor: theme.colorScheme.primary,
                          strokeWidth: 2,
                        ),
                      },
                      myLocationButtonEnabled: false,
                      myLocationEnabled: false,
                      mapToolbarEnabled: false,
                      zoomControlsEnabled: true,
                      onTap: (position) {
                        setState(() {
                          _selectedPosition = position;
                          _selectedAddress = 'Pinned location';
                          _syncCoordinateFields();
                        });
                      },
                      onMapCreated: (controller) {
                        _mapController = controller;
                      },
                    ),
                  ),
                )
              : _UnsupportedMapFallback(
                  latitudeController: _latitudeController,
                  longitudeController: _longitudeController,
                  onApply: _applyManualCoordinates,
                ),
          if (_supportsInteractiveMap) ...[
            const SizedBox(height: 12),
            _UnsupportedMapFallback(
              latitudeController: _latitudeController,
              longitudeController: _longitudeController,
              onApply: _applyManualCoordinates,
            ),
          ],
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.radar_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Geofence radius: ${_radiusMeters.toStringAsFixed(0)}m',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _isLocating ? null : _useCurrentDeviceLocation,
                      icon: _isLocating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location),
                      label: const Text('Use Current'),
                    ),
                  ],
                ),
                Slider(
                  min: 50,
                  max: 500,
                  divisions: 18,
                  value: _radiusMeters.clamp(50, 500).toDouble(),
                  label: '${_radiusMeters.toStringAsFixed(0)}m',
                  onChanged: (value) {
                    setState(() => _radiusMeters = value);
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'Pin: ${_selectedPosition.latitude.toStringAsFixed(6)}, ${_selectedPosition.longitude.toStringAsFixed(6)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UnsupportedMapFallback extends StatelessWidget {
  const _UnsupportedMapFallback({
    required this.latitudeController,
    required this.longitudeController,
    required this.onApply,
  });

  final TextEditingController latitudeController;
  final TextEditingController longitudeController;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.map_outlined,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Map preview is available on phone',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'If the map is blank, search results, current location, and exact coordinates still work. Blank map tiles usually mean the Google Maps key needs billing, Maps SDK access, or bundle/package restrictions checked.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: latitudeController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Latitude',
                    prefixIcon: Icon(Icons.north_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: longitudeController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Longitude',
                    prefixIcon: Icon(Icons.east_outlined),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: onApply,
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Apply Coordinates'),
            ),
          ),
        ],
      ),
    );
  }
}
