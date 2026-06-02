import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SubscriptionProvider with ChangeNotifier {
  final GoTrueClient _auth = Supabase.instance.client.auth;
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isPremium = false;
  bool _isLoading = false;

  bool get isPremium => _isPremium;
  bool get isLoading => _isLoading;

  Future<void> checkSubscriptionStatus() async {
    final user = _auth.currentUser;
    if (user == null) {
      _isPremium = false;
      notifyListeners();
      return;
    }

    try {
      final data = await _supabase.from('users').select('isPremium').eq('uid', user.id).maybeSingle();
      if (data != null) {
        _isPremium = data['isPremium'] ?? false;
      } else {
        _isPremium = false;
      }
    } catch (e) {
      debugPrint('Error checking subscription: $e');
      _isPremium = false;
    }
    notifyListeners();
  }

  Future<void> subscribe() async {
    final user = _auth.currentUser;
    if (user == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      // Simulate payment delay
      await Future.delayed(const Duration(seconds: 2));

      // Update DB
      await _supabase.from('users').update({
        'isPremium': true,
        'subscriptionDate': DateTime.now().toIso8601String(),
      }).eq('uid', user.id);

      _isPremium = true;
    } catch (e) {
      debugPrint('Error subscribing: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
