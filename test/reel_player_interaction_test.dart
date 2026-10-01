import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:grace_connect/models/reel.dart';
import 'package:grace_connect/services/reel_service.dart';
import 'package:grace_connect/widgets/reels/reel_grace_player.dart';

class MemoryReelService extends ReelService {
  MemoryReelService(SupabaseClient client) : super(client: client);
  @override
  ReelMedia cachedMedia(String id) => ReelMedia(
      videoUrl: 'https://example.invalid/video.mp4',
      posterUrl: null,
      expiresAt: DateTime.now().add(const Duration(hours: 1)));
}

class MemoryVideoController extends VideoPlayerController {
  MemoryVideoController({this.gate}) : super.asset('test.mp4');
  final Completer<void>? gate;
  bool disposed = false;
  @override
  Future<void> initialize() async {
    await gate?.future;
    value = const VideoPlayerValue(
        duration: Duration(seconds: 10),
        size: Size(360, 640),
        isInitialized: true);
  }

  @override
  Future<void> setLooping(bool looping) async {
    value = value.copyWith(isLooping: looping);
  }

  @override
  Future<void> setVolume(double volume) async {
    value = value.copyWith(volume: volume);
  }

  @override
  Future<void> play() async {
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await super.dispose();
  }
}

void main() {
  const reel = Reel(
      id: 'test',
      authorId: 'author',
      authorName: 'Author',
      caption: '',
      visibility: ReelVisibility.public);
  late SupabaseClient client;
  setUp(() =>
      client = SupabaseClient('https://example.invalid', 'public-test-key'));
  tearDown(() async => client.dispose());

  testWidgets(
      'mobile playback loops with sound, taps pause, double-tap and hold are distinct',
      (tester) async {
    final controller = MemoryVideoController();
    var likes = 0;
    var holds = 0;
    await tester.pumpWidget(MaterialApp(
        home: ReelGracePlayer(
            reel: reel,
            service: MemoryReelService(client),
            isCurrent: true,
            shouldInitialize: true,
            muted: false,
            controllerFactory: (_) => controller,
            onDoubleTap: () => likes++,
            onLongPress: () => holds++)));
    await tester.pumpAndSettle();
    expect(controller.value.isLooping, isTrue);
    expect(controller.value.volume, 1);
    expect(controller.value.isPlaying, isTrue);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    await tester.tap(find.byType(ReelGracePlayer));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(controller.value.isPlaying, isFalse);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    await tester.tap(find.byType(ReelGracePlayer));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(controller.value.isPlaying, isTrue);
    await tester.tap(find.byType(ReelGracePlayer));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.byType(ReelGracePlayer));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(likes, 1);
    expect(controller.value.isPlaying, isTrue);
    await tester.longPress(find.byType(ReelGracePlayer));
    expect(holds, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(controller.disposed, isTrue);
  });

  testWidgets(
      'a pending controller is disposed if its page disappears during initialization',
      (tester) async {
    final gate = Completer<void>();
    final controller = MemoryVideoController(gate: gate);
    await tester.pumpWidget(MaterialApp(
        home: ReelGracePlayer(
            reel: reel,
            service: MemoryReelService(client),
            isCurrent: true,
            shouldInitialize: true,
            muted: false,
            controllerFactory: (_) => controller)));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pumpAndSettle();
    expect(controller.disposed, isTrue);
    expect(controller.value.isPlaying, isFalse);
  });

  testWidgets('completion fires once each loop and hidden players do not play',
      (tester) async {
    final controller = MemoryVideoController();
    var completions = 0;
    Widget surface(bool active) => MaterialApp(
        home: ReelGracePlayer(
            reel: reel,
            service: MemoryReelService(client),
            isCurrent: active,
            shouldInitialize: true,
            muted: false,
            controllerFactory: (_) => controller,
            onCompleted: () => completions++));
    await tester.pumpWidget(surface(true));
    await tester.pumpAndSettle();
    controller.value =
        controller.value.copyWith(position: const Duration(milliseconds: 9900));
    controller.value =
        controller.value.copyWith(position: const Duration(milliseconds: 9950));
    expect(completions, 1);
    controller.value =
        controller.value.copyWith(position: const Duration(milliseconds: 20));
    controller.value =
        controller.value.copyWith(position: const Duration(milliseconds: 9900));
    expect(completions, 2);
    await tester.pumpWidget(surface(false));
    await tester.pumpAndSettle();
    expect(controller.value.isPlaying, isFalse);
  });
}
