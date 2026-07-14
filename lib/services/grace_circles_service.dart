import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GraceCircle {
  const GraceCircle({
    required this.id,
    required this.name,
    this.description = '',
    this.ownerId = '',
    this.churchId = '',
    this.visibility = 'public',
    this.memberCount = 0,
    this.createdAt,
  });

  final String id;
  final String name;
  final String description;
  final String ownerId;
  final String churchId;
  final String visibility;
  final int memberCount;
  final DateTime? createdAt;

  factory GraceCircle.fromMap(Map<String, dynamic> data) {
    return GraceCircle(
      id: data['id']?.toString() ?? '',
      name: data['name']?.toString() ?? 'Grace Circle',
      description: data['description']?.toString() ?? '',
      ownerId: data['owner_id']?.toString() ?? '',
      churchId: data['church_id']?.toString() ?? '',
      visibility: data['visibility']?.toString() ?? 'public',
      memberCount: _intValue(data['member_count']),
      createdAt: _dateValue(data['created_at']),
    );
  }

  static int _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime? _dateValue(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }
}

class GraceCirclesService {
  GraceCirclesService({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  String? get _userId => _supabase.auth.currentUser?.id;

  Future<List<GraceCircle>> fetchCircles() async {
    try {
      final rows = await _supabase.rpc('list_grace_circles');
      if (rows is List) {
        return rows
            .map((row) => GraceCircle.fromMap(Map<String, dynamic>.from(row)))
            .toList();
      }
    } catch (error) {
      debugPrint('Grace Circles RPC unavailable: $error');
    }

    try {
      final rows = await _supabase
          .from('grace_circles')
          .select()
          .order('created_at', ascending: false)
          .limit(50);
      return rows
          .map((row) => GraceCircle.fromMap(Map<String, dynamic>.from(row)))
          .toList();
    } catch (error) {
      debugPrint('Grace Circles unavailable: $error');
      return const [];
    }
  }

  Future<GraceCircle?> fetchCircle(String circleId) async {
    if (circleId.trim().isEmpty) return null;

    try {
      final row = await _supabase
          .from('grace_circles')
          .select()
          .eq('id', circleId)
          .maybeSingle();
      if (row == null) return null;
      return GraceCircle.fromMap(row);
    } catch (error) {
      debugPrint('Grace Circle unavailable: $error');
      return null;
    }
  }

  Future<GraceCircle?> createCircle({
    required String name,
    String description = '',
    String visibility = 'public',
  }) async {
    final userId = _userId;
    if (userId == null) return null;

    try {
      final row = await _supabase.rpc(
        'create_grace_circle',
        params: {
          'circle_name': name,
          'circle_description': description,
          'circle_visibility': visibility,
        },
      );
      if (row is Map)
        return GraceCircle.fromMap(Map<String, dynamic>.from(row));
    } catch (error) {
      debugPrint('Create Grace Circle RPC unavailable: $error');
    }

    final inserted = await _supabase
        .from('grace_circles')
        .insert({
          'name': name,
          'description': description,
          'owner_id': userId,
          'visibility': visibility,
        })
        .select()
        .single();
    return GraceCircle.fromMap(inserted);
  }

  Future<void> joinCircle(String circleId) async {
    final userId = _userId;
    if (userId == null || circleId.trim().isEmpty) return;

    try {
      await _supabase.rpc(
        'join_grace_circle',
        params: {'target_circle_id': circleId},
      );
      return;
    } catch (error) {
      debugPrint('Join Grace Circle RPC unavailable: $error');
    }

    await _supabase.from('grace_circle_members').upsert(
      {
        'circle_id': circleId,
        'user_id': userId,
        'status': 'active',
      },
      onConflict: 'circle_id,user_id',
    );
  }
}
