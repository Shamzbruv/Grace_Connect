import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class GooglePlacesService {
  // Ideally this should be in an environment variable or secure config
  static const String _apiKey = 'AIzaSyCwOedktmKNGVOK5mmpvNbSrnbzZ0PG1wg';

  static Future<List<Map<String, String>>> searchChurches(String query) async {
    if (query.isEmpty) return [];

    try {
      // Use Text Search API to find churches
      final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/place/textsearch/json?query=$query&type=church&key=$_apiKey');

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK' || data['status'] == 'ZERO_RESULTS') {
          final results = data['results'] as List;

          return results.map<Map<String, String>>((place) {
            return {
              'id': place['place_id'] as String,
              'name': place['name'] as String,
              'address': place['formatted_address'] as String? ?? '',
            };
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
}
