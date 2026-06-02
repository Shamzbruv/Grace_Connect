

enum TransactionType { offering, tithe, donation, expense, other }

class TransactionModel {
  final String id;
  final String churchId;
  final String userId;
  final String userName;
  final double amount;
  final TransactionType type;
  final String category; // e.g., "Building Fund", "Utilities"
  final String description;
  final DateTime date;
  final String? receiptUrl;

  TransactionModel({
    required this.id,
    required this.churchId,
    required this.userId,
    required this.userName,
    required this.amount,
    required this.type,
    required this.category,
    this.description = '',
    required this.date,
    this.receiptUrl,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'churchId': churchId,
      'userId': userId,
      'userName': userName,
      'amount': amount,
      'type': type.name, // Store enum as string
      'category': category,
      'description': description,
      'date': date.toIso8601String(),
      'receiptUrl': receiptUrl,
    };
  }

  factory TransactionModel.fromMap(Map<String, dynamic> data) {
    return TransactionModel(
      id: data['id'] ?? '',
      churchId: data['churchId'] ?? '',
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? 'Anonymous',
      amount: (data['amount'] ?? 0.0).toDouble(),
      type: parseType(data['type']),
      category: data['category'] ?? 'General',
      description: data['description'] ?? '',
      date: data['date'] != null ? DateTime.parse(data['date']) : DateTime.now(),
      receiptUrl: data['receiptUrl'],
    );
  }

  static TransactionType parseType(String? typeParams) {
    if (typeParams == null) return TransactionType.other;
    try {
      return TransactionType.values.firstWhere((e) => e.name == typeParams);
    } catch (e) {
      return TransactionType.other;
    }
  }
}
