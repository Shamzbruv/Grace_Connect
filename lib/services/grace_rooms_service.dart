import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GraceRoom {
  const GraceRoom({
    required this.id,
    required this.title,
    this.topic = '',
    this.description = '',
    this.subtitle = '',
    this.purpose = '',
    this.scriptureRefs = const [],
    this.safetyNote = '',
    this.moderationNote = '',
    this.restrictions = '',
    this.iconKey = 'forum',
    this.accentHex = '#7DB9F1',
    this.sortOrder = 0,
    this.isPlatformRoom = true,
    this.status = 'open',
    this.participantCount = 0,
    this.createdAt,
  });

  final String id;
  final String title;
  final String topic;
  final String description;
  final String subtitle;
  final String purpose;
  final List<String> scriptureRefs;
  final String safetyNote;
  final String moderationNote;
  final String restrictions;
  final String iconKey;
  final String accentHex;
  final int sortOrder;
  final bool isPlatformRoom;
  final String status;
  final int participantCount;
  final DateTime? createdAt;

  factory GraceRoom.fromMap(Map<String, dynamic> data) {
    final metadataValue = data['metadata'];
    final metadata = metadataValue is Map
        ? Map<String, dynamic>.from(metadataValue)
        : const <String, dynamic>{};
    return GraceRoom(
      id: data['id']?.toString() ?? '',
      title: data['title']?.toString() ?? 'Grace Room',
      topic: data['topic']?.toString() ?? '',
      description: data['description']?.toString() ?? '',
      subtitle: data['subtitle']?.toString() ??
          metadata['subtitle']?.toString() ??
          data['description']?.toString() ??
          '',
      purpose: data['purpose']?.toString() ??
          metadata['purpose']?.toString() ??
          data['topic']?.toString() ??
          '',
      scriptureRefs:
          _stringList(data['scripture_refs'] ?? metadata['scripture_refs']),
      safetyNote: data['safety_note']?.toString() ??
          metadata['safety_note']?.toString() ??
          '',
      moderationNote: data['moderation_note']?.toString() ??
          metadata['moderation_note']?.toString() ??
          '',
      restrictions: data['restrictions']?.toString() ??
          metadata['restrictions']?.toString() ??
          '',
      iconKey: data['icon_key']?.toString() ??
          metadata['icon_key']?.toString() ??
          'forum',
      accentHex: data['accent_hex']?.toString() ??
          metadata['accent_hex']?.toString() ??
          '#7DB9F1',
      sortOrder: _intValue(data['sort_order'] ?? metadata['sort_order']),
      isPlatformRoom: data['is_platform_room'] == true ||
          data['is_platform_defined'] == true ||
          metadata['is_platform_room'] == true ||
          metadata['platform_defined'] == true ||
          _permanentRoomIds.contains(data['id']?.toString()),
      status: data['status']?.toString() ?? 'open',
      participantCount: _intValue(data['participant_count']),
      createdAt: _dateValue(data['created_at']),
    );
  }
}

class GraceRoomMessage {
  const GraceRoomMessage({
    required this.id,
    required this.roomId,
    required this.body,
    this.anonymousName = 'Anonymous',
    this.authorId = '',
    this.createdAt,
    this.expiresAt,
  });

  final String id;
  final String roomId;
  final String body;
  final String anonymousName;
  final String authorId;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  factory GraceRoomMessage.fromMap(Map<String, dynamic> data) {
    return GraceRoomMessage(
      id: data['id']?.toString() ?? '',
      roomId: data['room_id']?.toString() ?? '',
      body: data['body']?.toString() ?? '',
      anonymousName: data['anonymous_name']?.toString() ??
          data['alias']?.toString() ??
          'Anonymous',
      authorId:
          data['author_id']?.toString() ?? data['user_id']?.toString() ?? '',
      createdAt: _dateValue(data['created_at']),
      expiresAt: _dateValue(data['expires_at']),
    );
  }
}

class GraceRoomsSetupException implements Exception {
  const GraceRoomsSetupException();

  @override
  String toString() {
    return 'Grace Room messaging is still being configured. Please apply the latest Supabase migrations and try again.';
  }
}

class GraceRoomsService {
  GraceRoomsService({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;
  DateTime? _lastExpiredMessageCleanupAt;

  String? get _userId => _supabase.auth.currentUser?.id;

  static List<GraceRoom> get permanentRooms => _permanentRooms;
  static const Duration messageLifetime = Duration(hours: 24);

  Future<List<GraceRoom>> fetchRooms() async {
    try {
      final rows = await _supabase.rpc('list_grace_rooms');
      if (rows is List) {
        return _mergePermanentRooms(rows
            .map((row) => GraceRoom.fromMap(Map<String, dynamic>.from(row)))
            .toList());
      }
    } catch (error) {
      debugPrint('Grace Rooms RPC unavailable: $error');
    }

    try {
      final rows = await _supabase
          .from('grace_rooms')
          .select()
          .eq('status', 'open')
          .order('created_at', ascending: false)
          .limit(50);
      return _mergePermanentRooms(rows
          .map((row) => GraceRoom.fromMap(Map<String, dynamic>.from(row)))
          .toList());
    } catch (error) {
      debugPrint('Grace Rooms unavailable: $error');
      return _permanentRooms;
    }
  }

  Future<GraceRoom?> fetchRoom(String roomId) async {
    final cleanRoomId = roomId.trim();
    if (cleanRoomId.isEmpty) return null;
    try {
      final row = await _supabase
          .from('grace_rooms')
          .select()
          .eq('id', cleanRoomId)
          .maybeSingle();
      if (row != null) {
        final room = GraceRoom.fromMap(row);
        return room.isPlatformRoom ? room : fallbackRoom(cleanRoomId);
      }
    } catch (error) {
      debugPrint('Grace Room unavailable: $error');
    }
    return fallbackRoom(cleanRoomId);
  }

  GraceRoom? fallbackRoom(String roomId) {
    final cleanRoomId = roomId.trim();
    for (final room in _permanentRooms) {
      if (room.id == cleanRoomId) return room;
    }
    return null;
  }

  @Deprecated('Grace Rooms are platform-defined and cannot be created in-app.')
  Future<GraceRoom?> createRoom({
    required String title,
    String topic = '',
    String description = '',
  }) async {
    throw UnsupportedError(
      'Grace Rooms are permanent platform rooms and cannot be created in-app.',
    );
  }

  Future<void> joinRoom(String roomId) async {
    final userId = _userId;
    if (userId == null || roomId.trim().isEmpty) return;
    await _deleteExpiredMessages();

    try {
      await _supabase.rpc(
        'join_grace_room',
        params: {'target_room_id': roomId},
      );
      return;
    } catch (error) {
      debugPrint('Join Grace Room RPC unavailable: $error');
    }

    try {
      await _supabase.from('grace_room_participants').upsert(
        {
          'room_id': roomId,
          'user_id': userId,
          'anonymous_name': _anonymousName(userId),
        },
        onConflict: 'room_id,user_id',
      );
    } catch (error) {
      if (_isMissingGraceRoomsSchema(error)) {
        debugPrint('Grace Room participant schema missing: $error');
        return;
      }
      rethrow;
    }
  }

  Stream<List<GraceRoomMessage>> watchMessages(String roomId) {
    return _supabase
        .from('grace_room_messages')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId)
        .order('created_at', ascending: false)
        .limit(200)
        .map((rows) {
          final messages = rows
              .map((row) => GraceRoomMessage.fromMap(row))
              .where(
                (message) =>
                    message.body.trim().isNotEmpty && _isActiveMessage(message),
              )
              .toList()
            ..sort((a, b) {
              final aDate =
                  a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bDate =
                  b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              return aDate.compareTo(bDate);
            });
          return messages;
        });
  }

  Future<List<GraceRoomMessage>> fetchMessages(String roomId) async {
    await _deleteExpiredMessages();
    try {
      final cutoff = DateTime.now().toUtc().subtract(messageLifetime);
      final rows = await _supabase
          .from('grace_room_messages')
          .select()
          .eq('room_id', roomId)
          .gte('created_at', cutoff.toIso8601String())
          .order('created_at')
          .limit(200);
      return rows
          .map(
              (row) => GraceRoomMessage.fromMap(Map<String, dynamic>.from(row)))
          .where(_isActiveMessage)
          .toList();
    } catch (error) {
      debugPrint('Grace Room messages unavailable: $error');
      return const [];
    }
  }

  Future<void> sendMessage({
    required String roomId,
    required String body,
  }) async {
    final userId = _userId;
    final cleanRoomId = roomId.trim();
    final cleanBody = body.trim();
    if (userId == null || cleanRoomId.isEmpty || cleanBody.isEmpty) return;
    await joinRoom(cleanRoomId);
    await _deleteExpiredMessages();

    final row = {
      'room_id': cleanRoomId,
      'author_id': userId,
      'anonymous_name': _anonymousName(userId),
      'body': cleanBody,
      'expires_at':
          DateTime.now().toUtc().add(messageLifetime).toIso8601String(),
    };

    try {
      await _supabase.from('grace_room_messages').insert(row);
    } catch (error) {
      if (_isMissingGraceRoomsSchema(error)) {
        throw const GraceRoomsSetupException();
      }
      final message = error.toString();
      if (!message.contains('expires_at')) rethrow;
      row.remove('expires_at');
      try {
        await _supabase.from('grace_room_messages').insert(row);
      } catch (fallbackError) {
        if (_isMissingGraceRoomsSchema(fallbackError)) {
          throw const GraceRoomsSetupException();
        }
        rethrow;
      }
    }
  }

  Future<void> _deleteExpiredMessages({bool force = false}) async {
    final now = DateTime.now().toUtc();
    final lastCleanup = _lastExpiredMessageCleanupAt;
    if (!force &&
        lastCleanup != null &&
        now.difference(lastCleanup) < const Duration(minutes: 5)) {
      return;
    }
    _lastExpiredMessageCleanupAt = now;

    try {
      await _supabase.rpc('delete_expired_grace_room_messages');
    } catch (error) {
      debugPrint('Grace Room message cleanup unavailable: $error');
    }
  }

  static bool _isActiveMessage(GraceRoomMessage message) {
    final now = DateTime.now().toUtc();
    final expiresAt = message.expiresAt;
    if (expiresAt != null) return expiresAt.toUtc().isAfter(now);

    final createdAt = message.createdAt;
    if (createdAt == null) return true;
    return createdAt.toUtc().isAfter(now.subtract(messageLifetime));
  }

  static bool _isMissingGraceRoomsSchema(Object error) {
    if (error is PostgrestException) {
      if (error.code == 'PGRST205') return true;
      final message = error.message.toLowerCase();
      return message.contains('grace_room') && message.contains('schema cache');
    }

    final message = error.toString().toLowerCase();
    return message.contains('pgrst205') &&
        message.contains('grace_room') &&
        message.contains('schema cache');
  }

  static String _anonymousName(String userId) {
    final suffix = userId.replaceAll('-', '');
    final safeSuffix = suffix.length <= 4 ? suffix : suffix.substring(0, 4);
    return 'Anonymous $safeSuffix';
  }

  static List<GraceRoom> _mergePermanentRooms(List<GraceRoom> remoteRooms) {
    final remoteById = {
      for (final room in remoteRooms)
        if (room.isPlatformRoom && _permanentRoomIds.contains(room.id))
          room.id: room,
    };
    final merged = [
      for (final fallback in _permanentRooms)
        remoteById[fallback.id] ?? fallback,
    ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return merged;
  }
}

const Set<String> _permanentRoomIds = {
  '10000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000002',
  '10000000-0000-0000-0000-000000000003',
  '10000000-0000-0000-0000-000000000004',
  '10000000-0000-0000-0000-000000000005',
  '10000000-0000-0000-0000-000000000006',
  '10000000-0000-0000-0000-000000000007',
  '10000000-0000-0000-0000-000000000008',
  '10000000-0000-0000-0000-000000000009',
  '10000000-0000-0000-0000-000000000010',
};

const List<GraceRoom> _permanentRooms = [
  GraceRoom(
    id: '10000000-0000-0000-0000-000000000001',
    title: 'The Heavy Heart',
    topic: 'Emotional support',
    subtitle: 'A gentle space for sadness, pressure, and quiet overwhelm.',
    description: 'For days when your heart feels heavy and words are hard.',
    purpose: 'Sadness, depression, emotional weight, discouragement',
    scriptureRefs: [
      'Psalm 34:18',
      'Psalm 42:11',
      'Matthew 11:28-30',
      'Isaiah 41:10',
      'Romans 8:38-39',
      'Psalm 40:1-3',
    ],
    safetyNote:
        'If someone expresses self-harm or danger, guide them to emergency help and alert moderators.',
    iconKey: 'heart',
    accentHex: '#78C6A3',
    sortOrder: 1,
  ),
  GraceRoom(
    id: '10000000-0000-0000-0000-000000000002',
    title: 'Peace in the Storm',
    topic: 'Anxiety and fear',
    subtitle: 'A calm room for anxiety, worry, panic, and restless thoughts.',
    description: 'For prayerful steadiness when life feels loud.',
    purpose: 'Anxiety, fear, panic, worry, overthinking',
    scriptureRefs: [
      'Philippians 4:6-7',
      '1 Peter 5:7',
      'John 14:27',
      'Isaiah 26:3',
      'Psalm 56:3-4',
      'Psalm 94:19',
    ],
    iconKey: 'peace',
    accentHex: '#7DB9F1',
    sortOrder: 2,
  ),
  GraceRoom(
    id: '10000000-0000-0000-0000-000000000003',
    title: 'Grief and Goodbye',
    topic: 'Loss and comfort',
    subtitle: 'A tender place for loss, mourning, and remembrance.',
    description: 'For people walking through goodbye and grief.',
    purpose: 'Bereavement, grief, death, separation, major loss',
    scriptureRefs: [
      'Psalm 147:3',
      'Matthew 5:4',
      'John 11:35',
      'Revelation 21:4',
      'Psalm 30:5',
      '2 Corinthians 1:3-4',
    ],
    iconKey: 'leaf',
    accentHex: '#9BC3B9',
    sortOrder: 3,
  ),
  GraceRoom(
    id: '10000000-0000-0000-0000-000000000004',
    title: 'Not Alone',
    topic: 'Loneliness',
    subtitle: 'A welcoming room for isolation, rejection, and loneliness.',
    description: 'For anyone who needs to be reminded they are seen.',
    purpose: 'Loneliness, isolation, rejection, lack of belonging',
    scriptureRefs: [
      'Hebrews 13:5',
      'Psalm 27:10',
      'Ecclesiastes 4:9-10',
      'Isaiah 43:2',
      'Matthew 28:20',
      'Psalm 68:6',
    ],
    iconKey: 'people',
    accentHex: '#F4B860',
    sortOrder: 4,
  ),
  GraceRoom(
    id: '10000000-0000-0000-0000-000000000005',
    title: 'Faith Under Pressure',
    topic: 'Doubt and endurance',
    subtitle: 'A grounded room for questions, doubt, and spiritual fatigue.',
    description: 'For honest wrestling without shame.',
    purpose: 'Doubt, spiritual fatigue, unanswered prayer, weak faith',
    scriptureRefs: [
      'Mark 9:24',
      'Psalm 13:1-6',
      'Isaiah 42:3',
      'James 1:5',
      'Hebrews 11:1',
      'Psalm 73:26',
    ],
    moderationNote:
        'Allow honest questions while keeping the room respectful and Christ-centered.',
    iconKey: 'flame',
    accentHex: '#B8A4FF',
    sortOrder: 5,
  ),
  GraceRoom(
    id: '10000000-0000-0000-0000-000000000006',
    title: 'Wounded by Church',
    topic: 'Healing and safety',
    subtitle: 'A careful room for church hurt, betrayal, and rebuilding trust.',
    description: 'For healing conversations without public accusations.',
    purpose: 'Church hurt, leadership wounds, spiritual abuse recovery',
    scriptureRefs: [
      'Ezekiel 34:11-16',
      'Psalm 55:12-14',
      'Psalm 55:22',
      'Matthew 11:28-30',
      'Colossians 3:12-14',
      'Romans 12:18',
    ],
    restrictions:
        'Do not name churches, pastors, or individuals. Report abuse or criminal concerns privately.',
    iconKey: 'shield',
    accentHex: '#E7A6B8',
    sortOrder: 6,
  ),
  GraceRoom(
    id: '10000000-0000-0000-0000-000000000007',
    title: 'Marriage and Relationships',
    topic: 'Relationships',
    subtitle: 'A supportive room for love, conflict, patience, and repair.',
    description: 'For relationship burdens that need wisdom and prayer.',
    purpose: 'Marriage, dating, friendship conflict, reconciliation',
    scriptureRefs: [
      '1 Corinthians 13:4-7',
      'Colossians 3:12-14',
      'Proverbs 15:1',
      'Ephesians 4:2-3',
      'James 1:19-20',
      'Ecclesiastes 4:9-10',
    ],
    safetyNote:
        'If abuse or immediate danger is disclosed, direct the person to emergency and professional help.',
    iconKey: 'rings',
    accentHex: '#F29E7D',
    sortOrder: 7,
  ),
  GraceRoom(
    id: '10000000-0000-0000-0000-000000000008',
    title: 'Family Matters',
    topic: 'Home and family',
    subtitle: 'A warm room for parenting, family tension, and home life.',
    description: 'For people praying over family relationships.',
    purpose: 'Parenting, family conflict, home pressure, generational wounds',
    scriptureRefs: [
      'Ephesians 4:2-3',
      'Colossians 3:13',
      'Psalm 133:1',
      'Joshua 24:15',
      'Proverbs 22:6',
      'Ephesians 6:1-4',
    ],
    iconKey: 'home',
    accentHex: '#8DD7CF',
    sortOrder: 8,
  ),
  GraceRoom(
    id: '10000000-0000-0000-0000-000000000009',
    title: 'Freedom Journey',
    topic: 'Habits and recovery',
    subtitle: 'A steady room for temptation, habits, and recovery steps.',
    description: 'For taking the next faithful step toward freedom.',
    purpose:
        'Addiction recovery, temptation, unwanted patterns, accountability',
    scriptureRefs: [
      '1 Corinthians 10:13',
      'Galatians 5:1',
      'James 4:7',
      'Romans 6:14',
      'Psalm 40:1-3',
      'John 8:36',
    ],
    restrictions:
        'No medical diagnosis, medication advice, or substance sourcing. Encourage professional support where needed.',
    iconKey: 'path',
    accentHex: '#8FB8ED',
    sortOrder: 9,
  ),
  GraceRoom(
    id: '10000000-0000-0000-0000-000000000010',
    title: 'Grace After Failure',
    topic: 'Restoration',
    subtitle: 'A hopeful room for repentance, shame, and starting again.',
    description: 'For people who need mercy to feel possible again.',
    purpose: 'Shame, guilt, repentance, rebuilding after mistakes',
    scriptureRefs: [
      'Romans 8:1',
      '1 John 1:9',
      'Psalm 51:10-12',
      'Micah 7:8',
      'Lamentations 3:22-23',
      'Isaiah 1:18',
    ],
    iconKey: 'sunrise',
    accentHex: '#F6C85F',
    sortOrder: 10,
  ),
];

List<String> _stringList(dynamic value) {
  if (value is List) {
    return value
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList();
  }
  if (value is String) {
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  return const [];
}

int _intValue(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? _dateValue(dynamic value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value)?.toLocal();
  return null;
}
