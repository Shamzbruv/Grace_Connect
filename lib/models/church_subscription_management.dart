class ChurchSubscriptionTier {
  const ChurchSubscriptionTier({
    required this.code,
    required this.label,
    required this.minMembers,
    required this.maxMembers,
    required this.monthlyUsd,
    required this.monthlyJmd,
    this.customQuote = false,
  });

  final String code;
  final String label;
  final int minMembers;
  final int? maxMembers;
  final int? monthlyUsd;
  final int? monthlyJmd;
  final bool customQuote;

  static const all = <ChurchSubscriptionTier>[
    ChurchSubscriptionTier(
      code: 'tier_0_50',
      label: '0–50 members',
      minMembers: 0,
      maxMembers: 50,
      monthlyUsd: 17,
      monthlyJmd: 2689,
    ),
    ChurchSubscriptionTier(
      code: 'tier_51_100',
      label: '51–100 members',
      minMembers: 51,
      maxMembers: 100,
      monthlyUsd: 34,
      monthlyJmd: 5377,
    ),
    ChurchSubscriptionTier(
      code: 'tier_101_150',
      label: '101–150 members',
      minMembers: 101,
      maxMembers: 150,
      monthlyUsd: 51,
      monthlyJmd: 8066,
    ),
    ChurchSubscriptionTier(
      code: 'tier_151_200',
      label: '151–200 members',
      minMembers: 151,
      maxMembers: 200,
      monthlyUsd: 68,
      monthlyJmd: 10755,
    ),
    ChurchSubscriptionTier(
      code: 'tier_201_300',
      label: '201–300 members',
      minMembers: 201,
      maxMembers: 300,
      monthlyUsd: 85,
      monthlyJmd: 13444,
    ),
    ChurchSubscriptionTier(
      code: 'tier_301_400',
      label: '301–400 members',
      minMembers: 301,
      maxMembers: 400,
      monthlyUsd: 102,
      monthlyJmd: 16132,
    ),
    ChurchSubscriptionTier(
      code: 'tier_401_500',
      label: '401–500 members',
      minMembers: 401,
      maxMembers: 500,
      monthlyUsd: 119,
      monthlyJmd: 18821,
    ),
    ChurchSubscriptionTier(
      code: 'tier_501_700',
      label: '501–700 members',
      minMembers: 501,
      maxMembers: 700,
      monthlyUsd: 136,
      monthlyJmd: 21510,
    ),
    ChurchSubscriptionTier(
      code: 'tier_701_900',
      label: '701–900 members',
      minMembers: 701,
      maxMembers: 900,
      monthlyUsd: 153,
      monthlyJmd: 24199,
    ),
    ChurchSubscriptionTier(
      code: 'tier_901_1000',
      label: '901–1,000 members',
      minMembers: 901,
      maxMembers: 1000,
      monthlyUsd: 170,
      monthlyJmd: 26887,
    ),
    ChurchSubscriptionTier(
      code: 'enterprise_1001_plus',
      label: '1,001+ members',
      minMembers: 1001,
      maxMembers: null,
      monthlyUsd: null,
      monthlyJmd: null,
      customQuote: true,
    ),
  ];

  factory ChurchSubscriptionTier.fromMap(Map<String, dynamic> data) {
    return ChurchSubscriptionTier(
      code: (data['tierCode'] ?? '').toString(),
      label: (data['label'] ?? '').toString(),
      minMembers: _asInt(data['minMembers']) ?? 0,
      maxMembers: _asInt(data['maxMembers']),
      monthlyUsd: _asInt(data['monthlyUsd']),
      monthlyJmd: _asInt(data['monthlyJmd']),
      customQuote: data['customQuote'] == true,
    );
  }

  static ChurchSubscriptionTier forMemberCount(int memberCount) {
    final safeCount = memberCount < 0 ? 0 : memberCount;
    return all.firstWhere(
      (tier) =>
          safeCount >= tier.minMembers &&
          (tier.maxMembers == null || safeCount <= tier.maxMembers!),
    );
  }

  String get priceLabel {
    if (customQuote || monthlyUsd == null || monthlyJmd == null) {
      return 'Enterprise / Custom (Custom Quote)';
    }
    return 'US\$$monthlyUsd (${formatJmd(monthlyJmd!)})';
  }

  static String formatJmd(int value) => 'J\$${_formatNumber(value)}';

  static String _formatNumber(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[index]);
    }
    return buffer.toString();
  }
}

class ChurchSubscriptionRequest {
  const ChurchSubscriptionRequest({
    required this.id,
    required this.requestType,
    required this.status,
    required this.memberCountSnapshot,
    required this.createdAt,
    this.requestedTierCode,
    this.monthlyUsd,
    this.monthlyJmd,
    this.message,
  });

  final String id;
  final String requestType;
  final String status;
  final int memberCountSnapshot;
  final String? requestedTierCode;
  final int? monthlyUsd;
  final int? monthlyJmd;
  final String? message;
  final DateTime? createdAt;

  bool get isOpen => const {'pending', 'in_review', 'quoted'}.contains(status);

  factory ChurchSubscriptionRequest.fromMap(Map<String, dynamic> data) {
    return ChurchSubscriptionRequest(
      id: (data['id'] ?? '').toString(),
      requestType: (data['requestType'] ?? 'new_subscription').toString(),
      status: (data['status'] ?? 'pending').toString(),
      memberCountSnapshot: _asInt(data['memberCountSnapshot']) ?? 0,
      requestedTierCode: data['requestedTierCode']?.toString(),
      monthlyUsd: _asInt(data['monthlyUsd']),
      monthlyJmd: _asInt(data['monthlyJmd']),
      message: data['message']?.toString(),
      createdAt: _asDateTime(data['createdAt']),
    );
  }
}

class ChurchSubscriptionRecord {
  const ChurchSubscriptionRecord({
    required this.status,
    required this.planCode,
    required this.billingState,
    required this.source,
    required this.billingCycle,
    required this.autoRenews,
    required this.autoConverts,
    this.monthlyUsd,
    this.monthlyJmd,
    this.currentPeriodStart,
    this.currentPeriodEnd,
    this.nextChargeAt,
    this.cancellationEffectiveAt,
  });

  final String status;
  final String planCode;
  final String billingState;
  final String source;
  final String billingCycle;
  final bool autoRenews;
  final bool autoConverts;
  final int? monthlyUsd;
  final int? monthlyJmd;
  final DateTime? currentPeriodStart;
  final DateTime? currentPeriodEnd;
  final DateTime? nextChargeAt;
  final DateTime? cancellationEffectiveAt;

  bool get isCurrentlyActive =>
      const {'active', 'trialing', 'grace_period'}.contains(status) &&
      (currentPeriodEnd == null || currentPeriodEnd!.isAfter(DateTime.now()));

  factory ChurchSubscriptionRecord.fromMap(Map<String, dynamic> data) {
    return ChurchSubscriptionRecord(
      status: (data['status'] ?? 'inactive').toString(),
      planCode: (data['planCode'] ?? '').toString(),
      billingState: (data['billingState'] ?? 'not_configured').toString(),
      source: (data['source'] ?? 'external_invoice').toString(),
      billingCycle: (data['billingCycle'] ?? 'monthly').toString(),
      autoRenews: data['autoRenews'] == true,
      autoConverts: data['autoConverts'] == true,
      monthlyUsd: _asInt(data['monthlyUsd']),
      monthlyJmd: _asInt(data['monthlyJmd']),
      currentPeriodStart: _asDateTime(data['currentPeriodStart']),
      currentPeriodEnd: _asDateTime(data['currentPeriodEnd']),
      nextChargeAt: _asDateTime(data['nextChargeAt']),
      cancellationEffectiveAt: _asDateTime(data['cancellationEffectiveAt']),
    );
  }
}

class ChurchBillingTerms {
  const ChurchBillingTerms({
    required this.version,
    required this.locale,
    required this.billingCycle,
    required this.autoRenews,
    required this.autoConverts,
    required this.requestDoesNotCharge,
    required this.cancellationMethod,
    required this.cancellationHandling,
    required this.paidServices,
    required this.freeServices,
  });

  final String version;
  final String locale;
  final String billingCycle;
  final bool autoRenews;
  final bool autoConverts;
  final bool requestDoesNotCharge;
  final String cancellationMethod;
  final String cancellationHandling;
  final List<String> paidServices;
  final List<String> freeServices;

  factory ChurchBillingTerms.fromMap(Map<String, dynamic> data) {
    return ChurchBillingTerms(
      version: (data['version'] ?? '2026-08-11-en-v1').toString(),
      locale: (data['locale'] ?? 'en').toString(),
      billingCycle: (data['billingCycle'] ?? 'monthly').toString(),
      autoRenews: data['autoRenews'] == true,
      autoConverts: data['autoConverts'] == true,
      requestDoesNotCharge: data['requestDoesNotCharge'] != false,
      cancellationMethod: (data['cancellationMethod'] ??
              'Submit a cancellation request in this section.')
          .toString(),
      cancellationHandling: (data['cancellationHandling'] ??
              'The finance team confirms the effective date.')
          .toString(),
      paidServices: _asStringList(data['paidServices']),
      freeServices: _asStringList(data['freeServices']),
    );
  }
}

class ChurchSubscriptionEvent {
  const ChurchSubscriptionEvent({
    required this.id,
    required this.eventType,
    required this.createdAt,
    this.status,
    this.planCode,
  });

  final String id;
  final String eventType;
  final String? status;
  final String? planCode;
  final DateTime? createdAt;

  factory ChurchSubscriptionEvent.fromMap(Map<String, dynamic> data) {
    return ChurchSubscriptionEvent(
      id: (data['id'] ?? '').toString(),
      eventType: (data['eventType'] ?? '').toString(),
      status: data['status']?.toString(),
      planCode: data['planCode']?.toString(),
      createdAt: _asDateTime(data['createdAt']),
    );
  }
}

class ChurchSubscriptionManagement {
  const ChurchSubscriptionManagement({
    required this.churchId,
    required this.churchName,
    required this.memberCount,
    required this.calculatedTier,
    required this.billingTerms,
    required this.requests,
    required this.history,
    this.subscription,
  });

  final String churchId;
  final String churchName;
  final int memberCount;
  final ChurchSubscriptionTier calculatedTier;
  final ChurchBillingTerms billingTerms;
  final ChurchSubscriptionRecord? subscription;
  final List<ChurchSubscriptionRequest> requests;
  final List<ChurchSubscriptionEvent> history;

  ChurchSubscriptionRequest? get openRequest {
    for (final request in requests) {
      if (request.isOpen) return request;
    }
    return null;
  }

  factory ChurchSubscriptionManagement.fromMap(Map<String, dynamic> data) {
    final tierData = _asMap(data['calculatedTier']);
    final subscriptionData = _asMapOrNull(data['subscription']);
    return ChurchSubscriptionManagement(
      churchId: (data['churchId'] ?? '').toString(),
      churchName: (data['churchName'] ?? 'Your church').toString(),
      memberCount: _asInt(data['memberCount']) ?? 0,
      calculatedTier: tierData.isEmpty
          ? ChurchSubscriptionTier.forMemberCount(
              _asInt(data['memberCount']) ?? 0,
            )
          : ChurchSubscriptionTier.fromMap(tierData),
      billingTerms: ChurchBillingTerms.fromMap(_asMap(data['billingTerms'])),
      subscription: subscriptionData == null
          ? null
          : ChurchSubscriptionRecord.fromMap(subscriptionData),
      requests: _asList(data['requests'])
          .map(ChurchSubscriptionRequest.fromMap)
          .toList(growable: false),
      history: _asList(data['history'])
          .map(ChurchSubscriptionEvent.fromMap)
          .toList(growable: false),
    );
  }
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

DateTime? _asDateTime(dynamic value) {
  if (value is DateTime) return value;
  return DateTime.tryParse(value?.toString() ?? '');
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

Map<String, dynamic>? _asMapOrNull(dynamic value) {
  if (value == null) return null;
  final map = _asMap(value);
  return map.isEmpty ? null : map;
}

List<Map<String, dynamic>> _asList(dynamic value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map(Map<String, dynamic>.from).toList();
}

List<String> _asStringList(dynamic value) {
  if (value is! List) return const [];
  return value.map((item) => item.toString()).toList(growable: false);
}
