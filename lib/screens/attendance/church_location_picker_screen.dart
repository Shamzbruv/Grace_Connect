import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
  static const MethodChannel _configChannel =
      MethodChannel('love.graceconnect/config');

  final AttendanceService _attendanceService = AttendanceService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _latitudeController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();
  final TextEditingController _radiusController = TextEditingController();

  GoogleMapController? _mapController;
  LatLng _selectedPosition = _jamaicaCenter;
  double _radiusMeters = 150;
  String? _selectedAddress;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isSearching = false;
  bool _isLocating = false;
  bool _isCheckingMap = false;
  bool _mapLoadFailed = false;
  bool? _androidMapsApiKeyPresent;
  String? _mapFailureDetail;
  int _mapRetryToken = 0;
  List<GooglePlaceResult> _searchResults = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadCurrentLocation());
      unawaited(_refreshMapAvailability());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _radiusController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  bool get _supportsInteractiveMap =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  bool get _isAndroidMapBuild =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _canRenderInteractiveMap =>
      _supportsInteractiveMap &&
      !_isCheckingMap &&
      !_mapLoadFailed &&
      _androidMapsApiKeyPresent != false;

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
      _syncRadiusField();
      await _moveCameraToSelectedPosition();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load church location: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _moveCameraToSelectedPosition() async {
    final controller = _mapController;
    if (controller == null) return;

    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          _selectedPosition,
          _selectedPosition == _jamaicaCenter ? 8 : 17,
        ),
      );
    } catch (error) {
      // The platform view can disappear while an async location read is in
      // flight. A recreated map will receive this position in onMapCreated.
      debugPrint('Could not move the church-location map camera: $error');
    }
  }

  Future<void> _refreshMapAvailability() async {
    if (!_supportsInteractiveMap) return;

    setState(() {
      _isCheckingMap = true;
      _mapLoadFailed = false;
      _mapFailureDetail = null;
    });

    try {
      final connectivity = await Connectivity().checkConnectivity();
      final isOffline = connectivity.isEmpty ||
          connectivity.every((result) => result == ConnectivityResult.none);
      if (isOffline) {
        if (!mounted) return;
        setState(() {
          _mapLoadFailed = true;
          _mapFailureDetail =
              'Device is offline. Manual coordinates can still be saved.';
          _androidMapsApiKeyPresent =
              _isAndroidMapBuild ? (_androidMapsApiKeyPresent ?? true) : true;
        });
        return;
      }

      if (_isAndroidMapBuild) {
        final status = await _configChannel
            .invokeMapMethod<String, dynamic>('getAndroidMapsConfigStatus');
        final hasKey = status?['hasKey'] == true;
        if (!mounted) return;
        setState(() {
          _androidMapsApiKeyPresent = hasKey;
          _mapLoadFailed = !hasKey;
          _mapFailureDetail = hasKey
              ? null
              : 'Android Maps API key is missing from this build.';
        });
      } else if (mounted) {
        setState(() => _androidMapsApiKeyPresent = true);
      }
    } catch (error) {
      debugPrint('Map availability check skipped: $error');
      if (mounted) {
        setState(() {
          _androidMapsApiKeyPresent = true;
          _mapFailureDetail = error.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _isCheckingMap = false);
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
            content: Text(
              'No places found. Enter coordinates manually or tap the map if it is available.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Search unavailable. Enter coordinates manually or tap the map if it is available: $e',
          ),
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

  void _syncRadiusField() {
    _radiusController.text = _radiusMeters.toStringAsFixed(0);
  }

  _ValidatedGeofence? _readValidatedGeofenceFromFields() {
    final latitude = double.tryParse(_latitudeController.text.trim());
    final longitude = double.tryParse(_longitudeController.text.trim());
    final radius = double.tryParse(_radiusController.text.trim());

    if (latitude == null ||
        longitude == null ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter a valid latitude between -90 and 90 and longitude between -180 and 180.',
          ),
        ),
      );
      return null;
    }

    if (radius == null || radius < 50 || radius > 500) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a geofence radius between 50 and 500 meters.'),
        ),
      );
      return null;
    }

    return _ValidatedGeofence(
      position: LatLng(latitude, longitude),
      radiusMeters: radius,
    );
  }

  void _applyManualCoordinates() {
    final geofence = _readValidatedGeofenceFromFields();
    if (geofence == null) return;

    setState(() {
      _radiusMeters = geofence.radiusMeters;
      _syncRadiusField();
    });
    unawaited(_movePin(geofence.position, address: 'Manual coordinates'));
  }

  void _retryMap() {
    _mapController?.dispose();
    _mapController = null;
    setState(() {
      _mapRetryToken += 1;
      _mapLoadFailed = false;
    });
    unawaited(_refreshMapAvailability());
  }

  Future<void> _saveLocation(UserProfile user) async {
    if (!_canManageAttendanceSetup(user)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have permission to save this geofence.'),
        ),
      );
      return;
    }
    if (user.churchId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your account is not assigned to a church.'),
        ),
      );
      return;
    }

    final geofence = _readValidatedGeofenceFromFields();
    if (geofence == null) return;

    setState(() => _isSaving = true);
    try {
      await _attendanceService.saveChurchLocation(
        churchId: user.churchId,
        latitude: geofence.position.latitude,
        longitude: geofence.position.longitude,
        radiusMeters: geofence.radiusMeters,
        address: _selectedAddress,
      );
      if (!mounted) return;
      setState(() {
        _selectedPosition = geofence.position;
        _radiusMeters = geofence.radiusMeters;
        _syncCoordinateFields();
        _syncRadiusField();
      });
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
          _isCheckingMap
              ? const _MapCheckingCard()
              : _canRenderInteractiveMap
                  ? SizedBox(
                      height: 420,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: GoogleMap(
                          key: ValueKey(_mapRetryToken),
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
                            unawaited(_moveCameraToSelectedPosition());
                          },
                        ),
                      ),
                    )
                  : _MapFailureCard(
                      onRetry: _retryMap,
                      unsupportedPlatform: !_supportsInteractiveMap,
                      detail: _mapFailureDetail,
                    ),
          if (_supportsInteractiveMap) ...[
            const SizedBox(height: 12),
            _ManualGeofenceFields(
              latitudeController: _latitudeController,
              longitudeController: _longitudeController,
              radiusController: _radiusController,
              onApply: _applyManualCoordinates,
              onRetryMap: _retryMap,
            ),
          ] else ...[
            const SizedBox(height: 12),
            _ManualGeofenceFields(
              latitudeController: _latitudeController,
              longitudeController: _longitudeController,
              radiusController: _radiusController,
              onApply: _applyManualCoordinates,
              onRetryMap: null,
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
                    setState(() {
                      _radiusMeters = value;
                      _syncRadiusField();
                    });
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

class _ValidatedGeofence {
  const _ValidatedGeofence({
    required this.position,
    required this.radiusMeters,
  });

  final LatLng position;
  final double radiusMeters;
}

class _MapCheckingCard extends StatelessWidget {
  const _MapCheckingCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Preparing map',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapFailureCard extends StatelessWidget {
  const _MapFailureCard({
    required this.onRetry,
    required this.unsupportedPlatform,
    this.detail,
  });

  final VoidCallback onRetry;
  final bool unsupportedPlatform;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      color: theme.colorScheme.errorContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                unsupportedPlatform ? Icons.map_outlined : Icons.error_outline,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  unsupportedPlatform
                      ? 'Map is only available in the Android or iOS app.'
                      : 'Map could not load. Check your internet connection or try again.',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (!unsupportedPlatform) ...[
            if (detail?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(
                detail!.trim(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry Map'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ManualGeofenceFields extends StatelessWidget {
  const _ManualGeofenceFields({
    required this.latitudeController,
    required this.longitudeController,
    required this.radiusController,
    required this.onApply,
    required this.onRetryMap,
  });

  final TextEditingController latitudeController;
  final TextEditingController longitudeController;
  final TextEditingController radiusController;
  final VoidCallback onApply;
  final VoidCallback? onRetryMap;

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
                  'Manual geofence details',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Latitude, longitude, and radius can be saved even if the map does not load.',
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
          TextField(
            controller: radiusController,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: false,
              signed: false,
            ),
            decoration: const InputDecoration(
              labelText: 'Radius in meters',
              prefixIcon: Icon(Icons.radar_outlined),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (onRetryMap != null)
                OutlinedButton.icon(
                  onPressed: onRetryMap,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry Map'),
                ),
              FilledButton.icon(
                onPressed: onApply,
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Apply Coordinates'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
