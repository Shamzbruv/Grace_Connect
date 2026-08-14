import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/church_subscription_management.dart';
import '../../providers/user_role_provider.dart';
import '../../services/church_subscription_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_bottom_menu.dart';
import '../../widgets/ui/app_scaffold.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final ChurchSubscriptionService _service = ChurchSubscriptionService();
  final TextEditingController _contactNameController = TextEditingController();
  final TextEditingController _contactEmailController = TextEditingController();
  final TextEditingController _contactPhoneController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  Future<ChurchSubscriptionManagement>? _managementFuture;
  bool _contactSeeded = false;
  bool _isSubmitting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final profile = context.watch<UserRoleProvider>().userProfile;
    if (!_contactSeeded && profile != null) {
      _contactNameController.text = profile.fullName;
      _contactEmailController.text = profile.email;
      _contactPhoneController.text = profile.phoneNumber;
      _contactSeeded = true;
    }
    if (_managementFuture == null &&
        ChurchSubscriptionService.canManageForProfile(profile)) {
      _managementFuture = _service.getManagement(
        churchId: profile?.churchId,
      );
    }
  }

  @override
  void dispose() {
    _contactNameController.dispose();
    _contactEmailController.dispose();
    _contactPhoneController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final churchId = context.read<UserRoleProvider>().userProfile?.churchId;
    final next = _service.getManagement(churchId: churchId);
    setState(() => _managementFuture = next);
    await next;
  }

  Future<void> _openRequestSheet(
    ChurchSubscriptionManagement management, {
    required String requestType,
  }) async {
    if (management.subscription == null ||
        (requestType != 'billing_support' && requestType != 'cancellation')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Account management is available only for an existing church subscription.',
          ),
        ),
      );
      return;
    }
    final tier = management.calculatedTier;
    var termsAccepted = false;
    _noteController.clear();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Container(
              padding: EdgeInsets.fromLTRB(
                20,
                14,
                20,
                20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
              ),
              decoration: BoxDecoration(
                color: Theme.of(sheetContext).colorScheme.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.center,
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color:
                              Theme.of(sheetContext).colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      _requestTitle(requestType),
                      style: GoogleFonts.poppins(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${tier.label} · ${tier.priceLabel} per month',
                      style: TextStyle(
                        color:
                            Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const _HonestBillingNotice(compact: true),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _contactNameController,
                      maxLength: 160,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Plan contact name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _contactEmailController,
                      maxLength: 320,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Plan contact email',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _contactPhoneController,
                      maxLength: 64,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Phone (optional)',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _noteController,
                      maxLength: 4000,
                      minLines: 3,
                      maxLines: 5,
                      decoration: InputDecoration(
                        labelText: requestType == 'cancellation'
                            ? 'Cancellation note (optional)'
                            : 'How can billing support help? (optional)',
                        alignLabelWithHint: true,
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(bottom: 48),
                          child: Icon(Icons.notes_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    CheckboxListTile(
                      value: termsAccepted,
                      onChanged: _isSubmitting
                          ? null
                          : (value) => setSheetState(
                                () => termsAccepted = value ?? false,
                              ),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'I understand this is an existing-plan account request only. It does not charge, purchase, enroll, renew, or activate anything.',
                        style: TextStyle(fontSize: 12, height: 1.4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _isSubmitting || !termsAccepted
                          ? null
                          : () async {
                              setSheetState(() => _isSubmitting = true);
                              final success = await _submitRequest(
                                management,
                                requestType: requestType,
                              );
                              if (!mounted || !sheetContext.mounted) return;
                              setSheetState(() => _isSubmitting = false);
                              if (success) Navigator.pop(sheetContext);
                            },
                      icon: _isSubmitting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded),
                      label: Text(
                        _isSubmitting ? 'Sending…' : 'Send account request',
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (mounted && _isSubmitting) setState(() => _isSubmitting = false);
  }

  Future<bool> _submitRequest(
    ChurchSubscriptionManagement management, {
    required String requestType,
  }) async {
    if (requestType != 'billing_support' && requestType != 'cancellation') {
      return false;
    }
    final name = _contactNameController.text.trim();
    final email = _contactEmailController.text.trim();
    if (name.isEmpty || !_looksLikeEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a plan contact name and valid email.'),
        ),
      );
      return false;
    }

    try {
      final request = await _service.submitRequest(
        requestType: requestType,
        requestedTierCode: management.calculatedTier.code,
        contactName: name,
        contactEmail: email,
        contactPhone: _contactPhoneController.text,
        message: _noteController.text,
      );
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            request.status == 'pending'
                ? 'Request sent to the Grace Connect finance team.'
                : 'Your open request was updated.',
          ),
        ),
      );
      await _reload();
      return true;
    } catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(error))),
      );
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<UserRoleProvider>().userProfile;
    final canManage = ChurchSubscriptionService.canManageForProfile(profile);

    return AppScaffold(
      title: 'Church Subscription',
      withBackground: true,
      bottomNavigationBar: const AppBottomMenu(),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: canManage ? () => _reload() : null,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      body: !canManage
          ? const _NoSubscriptionAccess()
          : FutureBuilder<ChurchSubscriptionManagement>(
              future: _managementFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError || snapshot.data == null) {
                  return _LoadError(
                    message: _friendlyError(snapshot.error),
                    onRetry: () => _reload(),
                  );
                }
                return _SubscriptionBody(
                  management: snapshot.data!,
                  onRefresh: _reload,
                  onBillingHelp: () => _openRequestSheet(
                    snapshot.data!,
                    requestType: 'billing_support',
                  ),
                  onCancellation: () => _openRequestSheet(
                    snapshot.data!,
                    requestType: 'cancellation',
                  ),
                );
              },
            ),
    );
  }

  String _requestTitle(String requestType) {
    return switch (requestType) {
      'billing_support' => 'Contact billing support',
      'cancellation' => 'Request cancellation',
      _ => 'Manage existing subscription',
    };
  }

  static bool _looksLikeEmail(String value) {
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);
  }

  static String _friendlyError(Object? error) {
    final raw = error?.toString() ?? '';
    if (raw.contains('permission') || raw.contains('authorized')) {
      return 'Your church role does not have subscription access.';
    }
    if (raw.contains('SocketException') || raw.contains('network')) {
      return 'Check your internet connection and try again.';
    }
    return 'Subscription information is unavailable right now. Please try again.';
  }
}

class _SubscriptionBody extends StatelessWidget {
  const _SubscriptionBody({
    required this.management,
    required this.onRefresh,
    required this.onBillingHelp,
    required this.onCancellation,
  });

  final ChurchSubscriptionManagement management;
  final Future<void> Function() onRefresh;
  final VoidCallback onBillingHelp;
  final VoidCallback onCancellation;

  @override
  Widget build(BuildContext context) {
    final tier = management.calculatedTier;
    final subscription = management.subscription;
    final openRequest = management.openRequest;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
        children: [
          const _NonTransactionalNotice(),
          const SizedBox(height: 14),
          _HeroCard(
            churchName: management.churchName,
            tier: tier,
            active: subscription?.isCurrentlyActive == true,
            hasRecordedSubscription: subscription != null,
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth = (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _MetricTile(
                    width: tileWidth,
                    icon: Icons.groups_2_outlined,
                    accent: const Color(0xFF275DCC),
                    label: 'Active members',
                    value: '${management.memberCount}',
                    detail: 'Calculated securely',
                  ),
                  _MetricTile(
                    width: tileWidth,
                    icon: Icons.account_balance_wallet_outlined,
                    accent: AppColors.secondary,
                    label: 'Monthly plan',
                    value: subscription?.monthlyUsd != null
                        ? 'US\$${subscription!.monthlyUsd}'
                        : tier.customQuote
                            ? 'Custom'
                            : 'US\$${tier.monthlyUsd}',
                    detail: subscription?.monthlyJmd != null
                        ? '(${ChurchSubscriptionTier.formatJmd(subscription!.monthlyJmd!)}) approx.'
                        : tier.customQuote
                            ? 'No recorded amount'
                            : '(${ChurchSubscriptionTier.formatJmd(tier.monthlyJmd!)}) approx.',
                  ),
                  _MetricTile(
                    width: tileWidth,
                    icon: Icons.verified_outlined,
                    accent: subscription?.isCurrentlyActive == true
                        ? const Color(0xFF18845B)
                        : const Color(0xFFB86822),
                    label: 'Subscription',
                    value: _prettyStatus(subscription?.status ?? 'inactive'),
                    detail: _billingDetail(subscription),
                  ),
                  _MetricTile(
                    width: tileWidth,
                    icon: Icons.mark_email_read_outlined,
                    accent: const Color(0xFF7954C7),
                    label: 'Finance request',
                    value: openRequest == null
                        ? 'None open'
                        : _prettyStatus(openRequest.status),
                    detail: openRequest == null
                        ? 'No account request'
                        : _requestTypeLabel(openRequest.requestType),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          const _HonestBillingNotice(),
          const SizedBox(height: 12),
          _BillingDisclosure(management: management),
          const SizedBox(height: 20),
          _IncludedServices(terms: management.billingTerms),
          const SizedBox(height: 20),
          _SectionTitle(
            title: 'Transparent monthly pricing',
            subtitle:
                'USD sets the billing tier; JMD amounts in brackets are approximate reference values.',
          ),
          const SizedBox(height: 10),
          _SoftPanel(
            child: Column(
              children: [
                for (var index = 0;
                    index < ChurchSubscriptionTier.all.length;
                    index++) ...[
                  _TierRow(
                    tier: ChurchSubscriptionTier.all[index],
                    selected:
                        ChurchSubscriptionTier.all[index].code == tier.code,
                  ),
                  if (index < ChurchSubscriptionTier.all.length - 1)
                    const Divider(height: 1),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (subscription == null)
            const _EnrollmentUnavailablePanel()
          else ...[
            const _SectionTitle(
              title: 'Existing-plan account management',
              subtitle:
                  'Contact billing support or request cancellation for the recorded plan.',
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onBillingHelp,
                    icon: const Icon(Icons.support_agent_outlined),
                    label: const Text('Billing support'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                if (subscription.status != 'cancelled' &&
                    subscription.status != 'inactive') ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onCancellation,
                      icon: const Icon(Icons.event_busy_outlined),
                      label: const Text('Cancel plan'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        foregroundColor: Theme.of(context).colorScheme.error,
                        side: BorderSide(
                          color: Theme.of(context)
                              .colorScheme
                              .error
                              .withValues(alpha: 0.45),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
          if (management.requests.isNotEmpty) ...[
            const SizedBox(height: 24),
            const _SectionTitle(
              title: 'Recent requests',
              subtitle: 'Track each request without losing the audit trail.',
            ),
            const SizedBox(height: 10),
            _SoftPanel(
              child: Column(
                children: [
                  for (var index = 0;
                      index < management.requests.take(5).length;
                      index++) ...[
                    _RequestRow(request: management.requests[index]),
                    if (index < management.requests.take(5).length - 1)
                      const Divider(height: 1),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _billingDetail(ChurchSubscriptionRecord? subscription) {
    if (subscription == null) return 'No plan recorded';
    return _prettyStatus(subscription.billingState);
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.churchName,
    required this.tier,
    required this.active,
    required this.hasRecordedSubscription,
  });

  final String churchName;
  final ChurchSubscriptionTier tier;
  final bool active;
  final bool hasRecordedSubscription;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF102A64), Color(0xFF245FC8)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF102A64).withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      active ? Icons.check_circle : Icons.schedule,
                      color: active
                          ? const Color(0xFF81E6B6)
                          : const Color(0xFFFFD46A),
                      size: 17,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      active
                          ? 'ACTIVE'
                          : hasRecordedSubscription
                              ? 'NOT ACTIVE'
                              : 'NO PLAN RECORDED',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              const Icon(Icons.auto_awesome, color: Color(0xFFFFCC54)),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            churchName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 23,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${tier.label} · ${tier.priceLabel}/month',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            active
                ? 'View the recorded monthly terms and manage this existing church plan. No purchase or payment happens in this Android app.'
                : 'Purchasing and enrollment are unavailable in this Android app. Pricing below is reference information only, with no external payment destination.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.86),
              height: 1.4,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _EnrollmentUnavailablePanel extends StatelessWidget {
  const _EnrollmentUnavailablePanel();

  @override
  Widget build(BuildContext context) {
    return const _SoftPanel(
      padding: EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.mobile_off_outlined, color: Color(0xFF245FC8)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Plan purchasing and enrollment are unavailable in this Android app. The pricing table is read-only, and this screen provides no external payment link or payment instructions.',
              style: TextStyle(fontSize: 12, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.width,
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
    required this.detail,
  });

  final double width;
  final IconData icon;
  final Color accent;
  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: _SoftPanel(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: accent, size: 21),
            ),
            const SizedBox(height: 13),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SoftPanel extends StatelessWidget {
  const _SoftPanel({
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? const Color(0xFF1C2432) : const Color(0xFFF6F8FC);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.white.withValues(alpha: 0.92),
        ),
        boxShadow: [
          BoxShadow(
            color: dark
                ? Colors.black.withValues(alpha: 0.32)
                : const Color(0xFF9AA9C2).withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(7, 7),
          ),
          BoxShadow(
            color: dark
                ? Colors.white.withValues(alpha: 0.025)
                : Colors.white.withValues(alpha: 0.9),
            blurRadius: 14,
            offset: const Offset(-6, -6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _TierRow extends StatelessWidget {
  const _TierRow({required this.tier, required this.selected});

  final ChurchSubscriptionTier tier;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
      decoration: selected
          ? BoxDecoration(
              color: const Color(0xFF245FC8).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: const Color(0xFF245FC8).withValues(alpha: 0.26),
              ),
            )
          : null,
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFF245FC8)
                  : Theme.of(context).colorScheme.outlineVariant,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              tier.label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            tier.priceLabel,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: selected
                  ? const Color(0xFF245FC8)
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({required this.request});

  final ChurchSubscriptionRequest request;

  @override
  Widget build(BuildContext context) {
    final statusColor = request.isOpen
        ? const Color(0xFFB86822)
        : request.status == 'approved'
            ? const Color(0xFF18845B)
            : Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(Icons.receipt_long_outlined, color: statusColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _requestTypeLabel(request.requestType),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${request.memberCountSnapshot} members · ${_formatDate(request.createdAt)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              _prettyStatus(request.status),
              style: TextStyle(
                color: statusColor,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NonTransactionalNotice extends StatelessWidget {
  const _NonTransactionalNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF9BB9F2)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFF174A9B)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'ACCOUNT MANAGEMENT ONLY — This Android screen does not sell, purchase, enroll, activate, or take payment for a plan. It shows pricing and terms, and supports existing-plan help or cancellation only.',
              style: TextStyle(
                color: Color(0xFF12396F),
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HonestBillingNotice extends StatelessWidget {
  const _HonestBillingNotice({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 15),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6DA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8C963)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined, color: Color(0xFF8A6710)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Monthly billing disclosure: no card details, payment links, or payment instructions are provided here. Purchasing and enrollment are unavailable in this Android app. Plans, trials, and manual grants do not auto-renew or auto-convert. Existing subscriptions show their access-through date below and can request cancellation here.',
              style: TextStyle(
                color: Color(0xFF624A0D),
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BillingDisclosure extends StatelessWidget {
  const _BillingDisclosure({required this.management});

  final ChurchSubscriptionManagement management;

  @override
  Widget build(BuildContext context) {
    final tier = management.calculatedTier;
    final subscription = management.subscription;
    final accessThrough = subscription?.currentPeriodEnd;
    final cancellationDate = subscription?.cancellationEffectiveAt;
    final monthlyPrice = subscription == null
        ? tier.customQuote
            ? 'Monthly · no amount recorded (reference tier)'
            : '${tier.priceLabel} every month (reference tier)'
        : subscription.monthlyUsd == null
            ? 'Monthly · amount not recorded'
            : 'US\$${subscription.monthlyUsd}'
                '${subscription.monthlyJmd == null ? '' : ' (${ChurchSubscriptionTier.formatJmd(subscription.monthlyJmd!)}) approx.'}'
                ' every month';
    return _SoftPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.fact_check_outlined, color: Color(0xFF245FC8)),
              SizedBox(width: 9),
              Text(
                'Billing terms at a glance',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _DisclosureRow(
            label: 'Billing cycle',
            value: monthlyPrice,
          ),
          const _DisclosureRow(
            label: 'Automatic renewal',
            value: 'No · no renewal date or automatic charge is scheduled',
          ),
          const _DisclosureRow(
            label: 'Trials / manual grants',
            value: 'Never auto-convert to a paid subscription',
          ),
          _DisclosureRow(
            label: 'Current access through',
            value: accessThrough == null
                ? 'Not scheduled — no access period is recorded'
                : _formatDate(accessThrough),
          ),
          _DisclosureRow(
            label: 'Cancellation',
            value: cancellationDate == null
                ? 'Request here; finance confirms the effective date'
                : 'Effective ${_formatDate(cancellationDate)}',
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _DisclosureRow extends StatelessWidget {
  const _DisclosureRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IncludedServices extends StatelessWidget {
  const _IncludedServices({required this.terms});

  final ChurchBillingTerms terms;

  @override
  Widget build(BuildContext context) {
    const fallbackPaid = [
      'Member approvals, directory, attendance, and alerts',
      'Church ministries, schedules, private care, roles, finance, and analytics',
    ];
    const fallbackFree = [
      'Community, public events, Bible, Daily Word, and Grace Rooms',
      'Saved items, profile, notifications, and church transfer',
    ];
    final paid = terms.paidServices.isEmpty ? fallbackPaid : terms.paidServices;
    final free = terms.freeServices.isEmpty ? fallbackFree : terms.freeServices;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          title: 'What the church plan covers',
          subtitle: 'Free member experiences remain available without a plan.',
        ),
        const SizedBox(height: 10),
        _SoftPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _ServiceHeading(
                icon: Icons.workspace_premium_outlined,
                color: Color(0xFFD2982C),
                text: 'Included with the paid church plan',
              ),
              const SizedBox(height: 9),
              for (final item in paid) _ServiceBullet(text: item),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),
              const _ServiceHeading(
                icon: Icons.favorite_border_rounded,
                color: Color(0xFF18845B),
                text: 'Available without a paid church plan',
              ),
              const SizedBox(height: 9),
              for (final item in free) _ServiceBullet(text: item),
            ],
          ),
        ),
      ],
    );
  }
}

class _ServiceHeading extends StatelessWidget {
  const _ServiceHeading({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 21),
        const SizedBox(width: 8),
        Expanded(
          child:
              Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

class _ServiceBullet extends StatelessWidget {
  const _ServiceBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(Icons.check_circle, size: 15, color: Color(0xFF18845B)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child:
                Text(text, style: const TextStyle(fontSize: 12, height: 1.35)),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _NoSubscriptionAccess extends StatelessWidget {
  const _NoSubscriptionAccess();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: _SoftPanel(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_person_outlined, size: 52),
              const SizedBox(height: 16),
              Text(
                'Subscription access is restricted',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'A pastor, church administrator, treasurer, financial secretary, or person with the subscription privilege can manage this section.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

String _prettyStatus(String raw) {
  if (raw.isEmpty) return 'Unknown';
  return raw
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String _requestTypeLabel(String raw) {
  return switch (raw) {
    'new_subscription' => 'New subscription',
    'change_plan' => 'Plan review',
    'enterprise_quote' => 'Enterprise quote',
    'billing_support' => 'Billing support',
    'cancellation' => 'Cancellation',
    _ => _prettyStatus(raw),
  };
}

String _formatDate(DateTime? value) {
  if (value == null) return 'Date unavailable';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = value.toLocal();
  return '${months[local.month - 1]} ${local.day}, ${local.year}';
}
