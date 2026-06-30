import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EmailDeliveryService {
  EmailDeliveryService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<bool> flushSupportTicketEmails(String ticketId) async {
    final cleanTicketId = ticketId.trim();
    if (cleanTicketId.isEmpty) return false;

    try {
      final response = await _client.functions.invoke(
        'grace-mailer',
        body: {
          'action': 'flush-support-ticket',
          'ticketId': cleanTicketId,
        },
      );
      final data = response.data;
      if (data is Map && data['ok'] == true) return true;
      debugPrint('Support ticket email delivery was not confirmed: $data');
    } catch (error) {
      debugPrint('Support ticket email delivery failed: $error');
    }
    return false;
  }
}
