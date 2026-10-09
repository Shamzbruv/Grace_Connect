import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class DailyScripture {
  const DailyScripture(this.reference, this.text);
  final String reference;
  final String text;
}

enum DailyQuoteWidgetAction { like }

class DailyGraceService {
  static const channel = MethodChannel('love.graceconnect/home_widget');
  static Future<List<DailyScripture>>? _catalogue;
  static bool get supportsPin =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<List<DailyScripture>> catalogue() => _catalogue ??= () async {
        final json =
            jsonDecode(await rootBundle.loadString('assets/daily_grace.json'))
                as Map;
        return (json['verses'] as List)
            .map((row) => DailyScripture(
                row['reference'] as String, row['text'] as String))
            .toList(growable: false);
      }();

  // Use a UTC representation of the LOCAL calendar date, not elapsed local
  // midnight hours (which shift with daylight saving time).
  static int indexForDay(DateTime day, int count) =>
      DateTime.utc(day.year, day.month, day.day)
          .difference(DateTime.utc(1970))
          .inDays %
      count;

  static Future<DailyScripture> scripture(
      {String? reference, DateTime? now}) async {
    final verses = await catalogue();
    for (final verse in verses) {
      if (verse.reference == reference) return verse;
    }
    return verses[indexForDay(now ?? DateTime.now(), verses.length)];
  }

  static Future<bool> requestPin({bool dailyWord = false}) async {
    if (!supportsPin) return false;
    try {
      return await channel.invokeMethod<bool>(
              dailyWord ? 'requestQuotePin' : 'requestPin') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> syncQuoteViewer(String viewerId) async {
    if (!supportsPin) return;
    try {
      await channel.invokeMethod<void>('quoteViewer', {'viewerId': viewerId});
    } on PlatformException {
      /* The in-app reaction remains authoritative. */
    } on MissingPluginException {/* Older native hosts. */}
  }

  static Future<void> syncQuoteEngagement(
      String id, int count, bool liked) async {
    if (!supportsPin) return;
    try {
      await channel.invokeMethod<void>(
          'quoteEngagement', {'id': id, 'count': count, 'liked': liked});
    } on PlatformException {
      /* Keep the server reaction even if a launcher fails. */
    } on MissingPluginException {/* Older native hosts. */}
  }

  static Future<void> initialize(GlobalKey<NavigatorState> navigatorKey,
      {String? quoteApiUrl, String? quoteApiKey, String viewerId = ''}) async {
    if (!supportsPin) return;
    void open(dynamic value) {
      if (value is! Map) return;
      final destination = value['destination'];
      if (destination != 'scripture' &&
          destination != 'community' &&
          destination != 'quote') {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (destination == 'quote') {
          final id =
              value['reference'] is String ? value['reference'] as String : '';
          if (id.isNotEmpty &&
              !RegExp(r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$')
                  .hasMatch(id)) {
            return;
          }
          navigatorKey.currentState?.pushNamed(
              Uri(
                  path: '/daily_word',
                  queryParameters: {if (id.isNotEmpty) 'id': id}).toString(),
              arguments:
                  value['like'] == 'true' ? DailyQuoteWidgetAction.like : null);
          return;
        }
        navigatorKey.currentState?.pushNamed(
          destination == 'scripture' ? '/daily_grace' : '/community',
          arguments: value['reference'] is String ? value['reference'] : null,
        );
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }

    channel.setMethodCallHandler((call) async {
      if (call.method == 'open') open(call.arguments);
    });
    try {
      if (quoteApiUrl != null && quoteApiKey != null) {
        await channel.invokeMethod<void>('configureQuoteWidget', {
          'apiUrl': quoteApiUrl,
          'apiKey': quoteApiKey,
          'viewerId': viewerId
        });
      }
      open(await channel.invokeMethod<dynamic>('initialDestination'));
    } on PlatformException {
      // Older native hosts can still use the in-app Scripture card.
    } on MissingPluginException {
      // Web previews and tests have no native widget host.
    }
  }
}
