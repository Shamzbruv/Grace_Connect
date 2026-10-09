import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grace_connect/services/daily_word_likes_service.dart';
import 'package:grace_connect/utils/compact_count.dart';
import 'package:grace_connect/widgets/daily_word_like_button.dart';

class FakeLikes implements DailyWordLikesService {
  DailyWordEngagement value =
      const DailyWordEngagement(count: 999, liked: false);
  Completer<DailyWordEngagement>? pending;
  int mutations = 0;
  bool? desired;
  @override
  Future<DailyWordEngagement> fetch(String id) async => value;
  @override
  Future<DailyWordEngagement> setLiked(String id, bool liked) {
    mutations++;
    desired = liked;
    return (pending ??= Completer<DailyWordEngagement>()).future;
  }
}

void main() {
  test('like counts reach each milestone exactly and preserve one decimal', () {
    for (final entry in {
      -1: '0',
      0: '0',
      999: '999',
      1000: '1K',
      1200: '1.2K',
      9999: '9.9K',
      10000: '10K',
      999999: '999.9K',
      1000000: '1M',
      1250000: '1.2M',
      1000000000: '1B',
      1000000000000: '1T',
    }.entries) {
      expect(compactCount(entry.key), entry.value);
    }
  });

  testWidgets(
      'a like updates optimistically, ignores repeat taps and rolls back on failure',
      (tester) async {
    final service = FakeLikes();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body:
                DailyWordLikeButton(motivationId: 'quote', service: service))));
    await tester.pumpAndSettle();
    expect(find.text('Like · 999'), findsOneWidget);
    await tester.tap(find.text('Like · 999'));
    await tester.pump();
    expect(find.text('Liked · 1K'), findsOneWidget);
    await tester.tap(find.text('Liked · 1K'));
    expect(service.mutations, 1);
    expect(service.desired, isTrue);
    service.pending!.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Like · 999'), findsOneWidget);
    expect(find.textContaining('could not be updated'), findsOneWidget);
  });

  testWidgets(
      'a widget heart uses idempotent like instead of toggling an existing like off',
      (tester) async {
    final service = FakeLikes()
      ..value = const DailyWordEngagement(count: 1200, liked: true);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DailyWordLikeButton(
                motivationId: 'quote', service: service, likeOnOpen: true))));
    expect(service.mutations, 1);
    expect(service.desired, isTrue);
    service.pending!.complete(service.value);
    await tester.pumpAndSettle();
    expect(find.text('Liked · 1.2K'), findsOneWidget);
    await tester.pump();
    expect(service.mutations, 1);
  });
}
