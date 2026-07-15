import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

class GooglePlaceResult {
  const GooglePlaceResult({
    required this.id,
    required this.name,
    required this.address,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String name;
  final String address;
  final double? latitude;
  final double? longitude;
}

class GooglePlacesService {
  static const String _configuredApiKey = Config.googlePlacesApiKey;
  static const MethodChannel _configChannel =
      MethodChannel('love.graceconnect/config');

  static Future<List<Map<String, String>>> searchChurches(String query) async {
    final results = await searchChurchLocations(query);
    return results
        .map(
          (place) => {
            'id': place.id,
            'name': place.name,
            'address': place.address,
          },
        )
        .toList();
  }

  static Future<List<GooglePlaceResult>> searchChurchLocations(
      String query) async {
    if (query.isEmpty) return [];

    try {
      final apiKey = await _resolveApiKey();
      if (apiKey.isEmpty) {
        debugPrint('Google Places key unavailable for this build.');
        return [];
      }

      // Use Text Search API to find churches
      final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/place/textsearch/json?query=${Uri.encodeQueryComponent(query)}&type=church&key=$apiKey');

      final response = await http.get(
        url,
        headers: await _androidRestrictionHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK' || data['status'] == 'ZERO_RESULTS') {
          final results = data['results'] as List;

          return results.map<GooglePlaceResult>((place) {
            final location = place['geometry']?['location'];
            return GooglePlaceResult(
              id: place['place_id'] as String,
              name: place['name'] as String? ?? 'Unnamed place',
              address: place['formatted_address'] as String? ?? '',
              latitude: (location?['lat'] as num?)?.toDouble(),
              longitude: (location?['lng'] as num?)?.toDouble(),
            );
          }).toList();
        } else {
          debugPrint(
              'Google Places Error: ${data['status']} - ${data['error_message']}');
          return [];
        }
      } else {
        debugPrint('HTTP Error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('Exception in GooglePlacesService: $e');
      return [];
    }
  }

  static Future<String> _resolveApiKey() async {
    if (_configuredApiKey.trim().isNotEmpty) return _configuredApiKey.trim();
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return '';

    try {
      final key = await _configChannel.invokeMethod<String>(
        'getAndroidMapsApiKey',
      );
      return key?.trim() ?? '';
    } catch (error) {
      debugPrint('Android Maps key fallback unavailable: $error');
      return '';
    }
  }

  static Future<Map<String, String>> _androidRestrictionHeaders() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const {};
    }

    try {
      final status = await _configChannel
          .invokeMapMethod<String, dynamic>('getAndroidMapsConfigStatus');
      final packageName = status?['packageName']?.toString().trim() ?? '';
      final sha1 = status?['signingCertificateSha1']?.toString().trim() ?? '';
      final cert = sha1.replaceAll(':', '').toUpperCase();
      if (packageName.isEmpty || cert.isEmpty) return const {};
      return {
        'X-Android-Package': packageName,
        'X-Android-Cert': cert,
      };
    } catch (error) {
      debugPrint('Android Places restriction headers unavailable: $error');
      return const {};
    }
  }
}
