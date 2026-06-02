import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/transaction_model.dart';

class FinanceService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Add a new transaction
  Future<void> addTransaction(TransactionModel transaction) async {
    final String docId =
        transaction.id.isEmpty ? const Uuid().v4() : transaction.id;
    final model = TransactionModel(
      id: docId,
      churchId: transaction.churchId,
      userId: transaction.userId,
      userName: transaction.userName,
      amount: transaction.amount,
      type: transaction.type,
      category: transaction.category,
      description: transaction.description,
      date: transaction.date,
      receiptUrl: transaction.receiptUrl,
    );

    await _supabase.from('transactions').insert(model.toMap());
  }

  // Get recent transactions
  Stream<List<TransactionModel>> getRecentTransactions(String churchId,
      {int limit = 20}) {
    return _supabase
        .from('transactions')
        .stream(primaryKey: ['id'])
        .eq('churchId', churchId)
        .order('date', ascending: false)
        .limit(limit)
        .map((docs) =>
            docs.map((doc) => TransactionModel.fromMap(doc)).toList());
  }

  // Get monthly summary (Simple aggregation on client side for now, can be cloud function later)
  Future<Map<String, double>> getMonthlySummary(String churchId) async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0);

    final snapshot = await _supabase
        .from('transactions')
        .select()
        .eq('churchId', churchId)
        .gte('date', startOfMonth.toIso8601String())
        .lte('date', endOfMonth.toIso8601String());

    double totalIncome = 0.0;
    double totalExpense = 0.0;

    for (var doc in snapshot) {
      final transaction = TransactionModel.fromMap(doc);
      if (transaction.type == TransactionType.expense) {
        totalExpense += transaction.amount;
      } else {
        totalIncome += transaction.amount;
      }
    }

    return {
      'income': totalIncome,
      'expense': totalExpense,
      'net': totalIncome - totalExpense,
    };
  }

  // Get Total Giving (All time income)
  Future<double> getTotalGiving(String churchId) async {
    // NOTE: In a real app, you'd want to keep a running total in a document
    // rather than reading all history. For MVP, this is fine or we can limit to this year.
    // Let's grab all generous types.

    final snapshot = await _supabase
        .from('transactions')
        .select('amount')
        .eq('churchId', churchId)
        .inFilter('type', ['offering', 'tithe', 'donation']);

    double total = 0.0;
    for (var doc in snapshot) {
      total += (doc['amount'] ?? 0.0);
    }
    return total;
  }

  Future<String?> getGivingUrl(String churchId) async {
    final data = await _supabase
        .from('churches')
        .select('policies')
        .eq('id', churchId)
        .maybeSingle();
    final policies = Map<String, dynamic>.from(data?['policies'] ?? {});
    final finance =
        Map<String, dynamic>.from(policies['financeSettings'] ?? {});
    final url = (finance['givingUrl'] ?? policies['givingUrl'])?.toString();
    return url == null || url.trim().isEmpty ? null : _normalizeUrl(url);
  }

  Future<void> updateGivingUrl(String churchId, String givingUrl) async {
    final data = await _supabase
        .from('churches')
        .select('policies')
        .eq('id', churchId)
        .maybeSingle();
    final policies = Map<String, dynamic>.from(data?['policies'] ?? {});
    final finance =
        Map<String, dynamic>.from(policies['financeSettings'] ?? {});
    finance['givingUrl'] = _normalizeUrl(givingUrl);
    finance['givingProvider'] = 'SpurrOpen';
    finance['updatedAt'] = DateTime.now().toIso8601String();
    policies['financeSettings'] = finance;

    await _supabase
        .from('churches')
        .update({'policies': policies}).eq('id', churchId);
  }

  String _normalizeUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'https://$trimmed';
  }
}
