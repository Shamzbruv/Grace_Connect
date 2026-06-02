import 'dart:io';
import 'package:flutter/foundation.dart';
import 'firebase_options.dart';

class Config {
  static String get apiUrl {
    if (kIsWeb) {
      return 'http://localhost:3000';
    } else if (Platform.isAndroid) {
      return 'http://10.0.2.2:3000';
    } else {
      return 'http://localhost:3000';
    }
  }

  static String get googlePlacesApiKey {
    return DefaultFirebaseOptions.currentPlatform.apiKey;
  }
}
