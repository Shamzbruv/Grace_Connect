import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/volunteer_need.dart';

class VolunteerService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final String _collection = 'volunteer_needs';

  // Get stream of open needs
  Stream<List<VolunteerNeed>> getOpenNeeds(String churchId) {
    return _supabase
        .from(_collection)
        .stream(primaryKey: ['id'])
        .eq('churchId', churchId)
        .order('date', ascending: true)
        .map((docs) {
      return docs
          .where((doc) => doc['status'] == 'open')
          .map((doc) => VolunteerNeed.fromMap(doc))
          .toList();
    });
  }

  // Create a need
  Future<void> createNeed(VolunteerNeed need) async {
    final String docId = const Uuid().v4();
    final newNeed = VolunteerNeed(
      id: docId,
      churchId: need.churchId,
      title: need.title,
      description: need.description,
      ministry: need.ministry,
      date: need.date,
      slotsNeeded: need.slotsNeeded,
      slotsFilled: [],
      createdBy: need.createdBy,
      status: 'open',
      createdAt: DateTime.now(),
    );
    await _supabase.from(_collection).insert(newNeed.toMap());
  }

  // Sign up
  Future<void> signUp(String needId, String userId) async {
    final data = await _supabase.from(_collection).select('slotsFilled').eq('id', needId).maybeSingle();
    if (data != null) {
      List<dynamic> slotsFilled = data['slotsFilled'] ?? [];
      if (!slotsFilled.contains(userId)) {
        slotsFilled.add(userId);
        await _supabase.from(_collection).update({'slotsFilled': slotsFilled}).eq('id', needId);
      }
    }
  }

  // Withdraw
  Future<void> withdraw(String needId, String userId) async {
    final data = await _supabase.from(_collection).select('slotsFilled').eq('id', needId).maybeSingle();
    if (data != null) {
      List<dynamic> slotsFilled = data['slotsFilled'] ?? [];
      if (slotsFilled.contains(userId)) {
        slotsFilled.remove(userId);
        await _supabase.from(_collection).update({'slotsFilled': slotsFilled}).eq('id', needId);
      }
    }
  }
}
