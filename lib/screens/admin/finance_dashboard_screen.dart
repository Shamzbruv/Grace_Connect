import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/user_role_provider.dart';
import '../../services/finance_service.dart';
import '../../models/transaction_model.dart';
import '../../widgets/ui/app_loader.dart';

class FinanceDashboardScreen extends StatefulWidget {
  const FinanceDashboardScreen({super.key});

  @override
  State<FinanceDashboardScreen> createState() => _FinanceDashboardScreenState();
}

class _FinanceDashboardScreenState extends State<FinanceDashboardScreen> {
  final FinanceService _financeService = FinanceService();

  @override
  Widget build(BuildContext context) {
    final userProfile = Provider.of<UserRoleProvider>(context).userProfile;
    final churchId = userProfile?.churchId;

    if (churchId == null) {
      return const Scaffold(
          body: Center(child: Text('Error: No Church ID found')));
    }

    if (userProfile?.canViewFinance != true) {
      return const Scaffold(
        body: Center(child: Text('You do not have access to finances.')),
      );
    }

    final currencyFormat = NumberFormat.simpleCurrency(name: 'JMD');

    return Scaffold(
      appBar: AppBar(
        title: Text('Church Finances',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
      ),
      floatingActionButton: userProfile!.capabilities.canManageFinance
          ? FloatingActionButton(
              onPressed: () => _showAddTransactionDialog(context, churchId),
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: const Icon(Icons.add),
            )
          : null,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Month Summary
            FutureBuilder<Map<String, double>>(
              future: _financeService.getMonthlySummary(churchId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                      height: 150,
                      child: Center(child: CircularProgressIndicator()));
                }

                final data = snapshot.data ??
                    {'income': 0.0, 'expense': 0.0, 'net': 0.0};
                final income = data['income']!;
                final expense = data['expense']!;
                final net = data['net']!;

                return Column(
                  children: [
                    _buildFinanceCard(
                      context,
                      title: 'This Month Income',
                      amount: currencyFormat.format(income),
                      trend: 'Income',
                      color: Colors.green,
                      icon: Icons.arrow_upward,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildFinanceCard(
                            context,
                            title: 'Expenses',
                            amount: currencyFormat.format(expense),
                            trend: 'Outflow',
                            color: Colors.redAccent,
                            isSmall: true,
                            icon: Icons.arrow_downward,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildFinanceCard(
                            context,
                            title: 'Net Total',
                            amount: currencyFormat.format(net),
                            trend: net >= 0 ? 'Surplus' : 'Deficit',
                            color: net >= 0 ? Colors.blue : Colors.orange,
                            isSmall: true,
                            icon: Icons.account_balance_wallet,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),

            Text('Recent Transactions',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),

            StreamBuilder<List<TransactionModel>>(
              stream: _financeService.getRecentTransactions(churchId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const AppLoader();
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final transactions = snapshot.data ?? [];

                if (transactions.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Center(child: Text("No transactions recorded yet.")),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: transactions.length,
                  itemBuilder: (context, index) {
                    final tx = transactions[index];
                    final isExpense = tx.type == TransactionType.expense;
                    final color = isExpense ? Colors.red : Colors.green;
                    final icon = isExpense
                        ? Icons.remove_circle_outline
                        : Icons.add_circle_outline;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color.withValues(alpha: 0.1),
                          child: Icon(icon, color: color),
                        ),
                        title: Text(tx.category.isNotEmpty
                            ? tx.category
                            : 'Transaction'),
                        subtitle: Text(
                            '${tx.userName} • ${DateFormat.MMMd().format(tx.date)}'),
                        trailing: Text(
                          currencyFormat.format(tx.amount),
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold, color: color),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinanceCard(
    BuildContext context, {
    required String title,
    required String amount,
    required String trend,
    required Color color,
    required IconData icon,
    bool isSmall = false,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isSmall ? 16 : 20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.grey)),
              Icon(icon, color: color.withValues(alpha: 0.5), size: 20),
            ],
          ),
          SizedBox(height: isSmall ? 8 : 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              amount,
              style: GoogleFonts.poppins(
                  fontSize: isSmall ? 20 : 28,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
          if (!isSmall) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.trending_up, size: 16, color: color),
                const SizedBox(width: 4),
                Text(trend,
                    style:
                        TextStyle(color: color, fontWeight: FontWeight.bold)),
              ],
            ),
          ]
        ],
      ),
    );
  }

  void _showAddTransactionDialog(BuildContext context, String churchId) {
    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();
    final categoryController = TextEditingController(); // Or dropdown
    TransactionType selectedType = TransactionType.offering;
    final user =
        Provider.of<UserRoleProvider>(context, listen: false).userProfile;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Add Transaction'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<TransactionType>(
                        value: selectedType,
                        decoration: const InputDecoration(labelText: 'Type'),
                        items: TransactionType.values.map((type) {
                          return DropdownMenuItem(
                            value: type,
                            child: Text(type.name.toUpperCase()),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => selectedType = val);
                        },
                      ),
                      TextFormField(
                        controller: amountController,
                        decoration:
                            const InputDecoration(labelText: 'Amount (JMD)'),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        validator: (val) =>
                            val == null || val.isEmpty ? 'Enter amount' : null,
                      ),
                      TextFormField(
                        controller: categoryController,
                        decoration: const InputDecoration(
                            labelText: 'Category (e.g. Tithe, Building)'),
                        validator: (val) => val == null || val.isEmpty
                            ? 'Enter category'
                            : null,
                      ),
                      TextFormField(
                        controller: descriptionController,
                        decoration: const InputDecoration(
                            labelText: 'Description (Optional)'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      final amount =
                          double.tryParse(amountController.text) ?? 0.0;
                      final tx = TransactionModel(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        churchId: churchId,
                        userId: user?.uid ?? 'admin',
                        userName: user?.fullName ?? 'Admin',
                        amount: amount,
                        type: selectedType,
                        category: categoryController.text,
                        description: descriptionController.text,
                        date: DateTime.now(),
                      );

                      await _financeService.addTransaction(tx);
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
