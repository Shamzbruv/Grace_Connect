import 'package:flutter_test/flutter_test.dart';
import 'package:grace_connect/models/direct_message.dart';
import 'package:grace_connect/services/direct_message_service.dart';

void main() {
  group('DirectMessageService reply context hardening', () {
    test('cleans null reply context without mutating a const map', () {
      expect(DirectMessageService.sanitizeReplyContext(null), isEmpty);
    });

    test('copies immutable reply context before removing null values', () {
      final source = Map<String, dynamic>.unmodifiable({
        'type': 'community_story',
        'story_id': 'story-1',
        'media_url': null,
      });

      final cleaned = DirectMessageService.sanitizeReplyContext(source);

      expect(cleaned, {
        'type': 'community_story',
        'story_id': 'story-1',
      });
      expect(() => source['media_url'] = 'changed', throwsUnsupportedError);
    });

    test('model parsing returns mutable reply context copies', () {
      final message = DirectMessage.fromMap({
        'id': 'message-1',
        'conversation_id': 'conversation-1',
        'sender_id': 'sender-1',
        'text': 'hello',
        'created_at': DateTime.now().toIso8601String(),
        'is_read': false,
        'reply_context': Map<String, dynamic>.unmodifiable({
          'type': 'community_story',
        }),
      });

      message.replyContext['opened'] = true;

      expect(message.replyContext['opened'], isTrue);
    });
  });
}
