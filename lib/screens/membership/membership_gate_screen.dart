import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/church_service.dart';
import '../../services/church_subscription_service.dart';
import '../../services/membership_service.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../login screen/login_screen.dart';
import '../main/main_tabs_screen.dart';
import '../signup screen/complete_profile_screen.dart';

class MembershipGate extends StatefulWidget {
  const MembershipGate({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<MembershipGate> createState() => _MembershipGateState();
}

class _MembershipGateState extends State<MembershipGate> {
  late Stream<MembershipContext> _contextStream;

  @override
  void initState() {
    super.initState();
    _contextStream = MembershipService().watchCurrentContext();
  }

  void _refresh() {
    setState(() {
      _contextStream = MembershipService().watchCurrentContext();
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MembershipContext>(
      stream: _contextStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return _StatusScreen(
            icon: Icons.cloud_off_outlined,
            title: 'Membership Unavailable',
            message:
                'Grace Connect could not load your membership right now. Check your connection and try again.',
            onRefresh: _refresh,
          );
        }

        final membership = snapshot.data;
        if (membership == null || !membership.authenticated) {
          return const LoginScreen();
        }

        if (membership.hasLoadError) {
          return _StatusScreen(
            icon: Icons.cloud_off_outlined,
            title: membership.loadErrorTitle,
            message: membership.loadErrorMessage,
            onRefresh: _refresh,
          );
        }

        if (membership.isAccountRestricted) {
          return _StatusScreen(
            icon: Icons.lock_outline,
            title: 'Account Restricted',
            message:
                'This Grace Connect account is not currently available. Contact support if you think this is a mistake.',
            onRefresh: _refresh,
          );
        }

        if (!membership.hasProfile) {
          return const CompleteProfileScreen();
        }

        if (membership.hasActiveMembership) {
          return _SubscriptionGate(
            churchId: membership.churchId!,
            churchName: membership.churchName,
            child: widget.child,
          );
        }

        if (membership.hasPendingChurchApplication) {
          return MainTabsScreen(
            membershipLimited: true,
            limitedTitle: 'Church Application Pending',
            limitedMessage:
                'Your church registration is ${membership.churchApplicationStatus ?? 'under review'}. You can browse the public feed while Grace Connect reviews it. Church tools unlock after approval.',
            showFindChurchAction: false,
          );
        }

        if (membership.hasPendingMembership) {
          return MainTabsScreen(
            membershipLimited: true,
            limitedTitle: 'Membership Pending',
            limitedMessage:
                'Your request to join ${membership.churchName ?? 'this church'} is waiting for church leadership approval. You can browse the public feed while you wait; member tools unlock after approval.',
            showFindChurchAction: false,
          );
        }

        if (membership.hasBlockedMembership) {
          final action = membership.membershipStatus == 'removed'
              ? 'You are no longer connected to this church.'
              : 'That membership request was not approved.';
          return FindChurchScreen(
            title: 'Choose a Church',
            intro: '$action You can request access to another approved church.',
            onSubmitted: _refresh,
          );
        }

        if (_routeMayBrowseWithoutChurch(context)) {
          return const MainTabsScreen(
            membershipLimited: true,
            limitedTitle: 'Choose a Church',
            limitedMessage:
                'You are not connected to a church yet. You can browse public feed posts for now, but posting, messaging, and member tools unlock after a church approves you.',
          );
        }

        return FindChurchScreen(onSubmitted: _refresh);
      },
    );
  }

  bool _routeMayBrowseWithoutChurch(BuildContext context) {
    final route = ModalRoute.of(context)?.settings.name;
    return route == '/community';
  }
}

class _SubscriptionGate extends StatefulWidget {
  const _SubscriptionGate({
    required this.churchId,
    required this.child,
    this.churchName,
  });

  final String churchId;
  final String? churchName;
  final Widget child;

  @override
  State<_SubscriptionGate> createState() => _SubscriptionGateState();
}

class _SubscriptionGateState extends State<_SubscriptionGate> {
  late Future<ChurchSubscriptionContext> _subscriptionFuture;

  @override
  void initState() {
    super.initState();
    _subscriptionFuture = _loadSubscription();
  }

  @override
  void didUpdateWidget(covariant _SubscriptionGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.churchId != widget.churchId) {
      _subscriptionFuture = _loadSubscription();
    }
  }

  Future<ChurchSubscriptionContext> _loadSubscription() {
    return ChurchSubscriptionService().getCurrentChurchSubscription(
      churchId: widget.churchId,
    );
  }

  void _refresh() {
    setState(() {
      _subscriptionFuture = _loadSubscription();
    });
  }

  bool _routeMayBypassSubscription(BuildContext context) {
    final route = ModalRoute.of(context)?.settings.name;
    return route == null ||
        route == '/' ||
        route == '/community' ||
        route == '/developer_console';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ChurchSubscriptionContext>(
      future: _subscriptionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final subscription = snapshot.data;
        if (subscription?.isActive == true ||
            _routeMayBypassSubscription(context)) {
          return widget.child;
        }

        return _SubscriptionRequiredScreen(
          churchName: widget.churchName,
          loadError: subscription?.loadError,
          onRefresh: _refresh,
        );
      },
    );
  }
}

class _SubscriptionRequiredScreen extends StatelessWidget {
  const _SubscriptionRequiredScreen({
    this.churchName,
    this.loadError,
    required this.onRefresh,
  });

  final String? churchName;
  final String? loadError;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = churchName == null || churchName!.trim().isEmpty
        ? 'your church'
        : churchName!.trim();
    final message = loadError == null
        ? '$name does not currently have an active Grace Connect subscription. The feed is still available, but the rest of the church management tools are paused. Please contact your church administrator to discuss subscription options.'
        : 'Grace Connect could not verify the subscription for $name. The feed is still available while this is checked. Please try again or contact your church administrator.';

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_clock_outlined,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Subscription Required',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context)
                        .pushNamedAndRemoveUntil('/community', (_) => false),
                    icon: const Icon(Icons.dynamic_feed_outlined),
                    label: const Text('Open Feed'),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Check Again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FindChurchScreen extends StatefulWidget {
  const FindChurchScreen({
    super.key,
    this.title = 'Find Your Church',
    this.intro =
        'Choose an approved church and submit a membership request. Church access opens after a leader approves you.',
    this.onSubmitted,
    this.allowBrowseFeed = true,
  });

  final String title;
  final String intro;
  final VoidCallback? onSubmitted;
  final bool allowBrowseFeed;

  @override
  State<FindChurchScreen> createState() => _FindChurchScreenState();
}

class _FindChurchScreenState extends State<FindChurchScreen> {
  final _churchSearchController = TextEditingController();
  final _messageController = TextEditingController();
  final _locationController = TextEditingController();
  String? _selectedChurchId;
  String? _selectedChurchName;
  bool _isLoading = false;
  bool _isLoadingPolicies = false;
  bool _notPartOfChurchYet = false;

  List<Map<String, dynamic>> _requiredPolicies = [];
  Map<String, bool> _acceptedPolicies = {};
  String? _policyLoadError;

  @override
  void initState() {
    super.initState();
    _loadPolicies();
  }

  Future<void> _loadPolicies() async {
    if (mounted) {
      setState(() {
        _isLoadingPolicies = true;
        _policyLoadError = null;
      });
    }

    try {
      final policies =
          await MembershipService().getRequiredPolicies('member_signup');
      if (mounted) {
        setState(() {
          _requiredPolicies = policies;
          _policyLoadError = null;
          _acceptedPolicies = {
            for (final policy in policies)
              policy['document_key'] as String:
                  _acceptedPolicies[policy['document_key'] as String] ?? false,
          };
          _isLoadingPolicies = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load required policies: $e');
      if (mounted) {
        setState(() {
          _policyLoadError =
              'Failed to load required policies. Please check your connection and try again.';
          _isLoadingPolicies = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _churchSearchController.dispose();
    _messageController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    if (_selectedChurchId == null || _selectedChurchId!.isEmpty) return false;
    if (_isLoadingPolicies || _policyLoadError != null) return false;
    if (_requiredPolicies.isEmpty) return false;
    for (var p in _requiredPolicies) {
      if (_acceptedPolicies[p['document_key'] as String] != true) {
        return false;
      }
    }
    return true;
  }

  Future<void> _submitRequest() async {
    if (!_canSubmit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Please select a church and accept all required policies.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final service = MembershipService();
      await service.acceptPolicies(
        _requiredPolicies,
        source: 'flutter_church_request',
        metadata: {
          'isAdultConfirmed': _acceptedPolicies['age_policy'] == true,
          'locationNoticeAccepted':
              _acceptedPolicies['location_disclosure'] == true
        },
      );

      await service.requestMembership(
        churchId: _selectedChurchId!,
        message: _messageController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Membership request submitted.')),
      );
      widget.onSubmitted?.call();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not submit request: $error')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Uri resolvePolicyUrl(String rawUrl) {
    final uri = Uri.parse(rawUrl);

    if (uri.hasScheme) {
      if (uri.scheme != 'https') {
        throw ArgumentError('Only HTTPS policy URLs are allowed.');
      }
      return uri;
    }

    return Uri.https(
      'www.graceconnect.love',
      '/${rawUrl.replaceFirst(RegExp(r'^/'), '')}',
    );
  }

  Widget _buildPolicyLink(String text, String? url) {
    return InkWell(
      onTap: () async {
        if (url == null || url.isEmpty) return;
        try {
          final uri = resolvePolicyUrl(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not open policy link: $e')),
            );
          }
        }
      },
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      withBackground: true,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: AppCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.church_outlined,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.intro,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  TypeAheadField<Map<String, String>>(
                    controller: _churchSearchController,
                    builder: (context, controller, focusNode) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          labelText: 'Approved Church',
                          hintText: 'Search by name, parish, or address',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                          ),
                        ),
                      );
                    },
                    suggestionsCallback: ChurchService.searchChurches,
                    itemBuilder: (context, suggestion) {
                      return ListTile(
                        leading: Icon(
                          Icons.church,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(suggestion['name'] ?? ''),
                        subtitle: Text(
                          suggestion['address'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                    onSelected: (suggestion) {
                      setState(() {
                        _selectedChurchId = suggestion['id'];
                        _selectedChurchName = suggestion['name'];
                        _churchSearchController.text = suggestion['name'] ?? '';
                      });
                    },
                    emptyBuilder: (context) => const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No approved churches match that search.'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: _notPartOfChurchYet,
                    onChanged: (value) {
                      setState(() => _notPartOfChurchYet = value ?? false);
                    },
                    title: const Text('I am not part of a church yet'),
                    subtitle: const Text(
                      'You can browse the public feed now and request a church later.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (_notPartOfChurchYet) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _locationController,
                      decoration: InputDecoration(
                        labelText: 'Your area or parish',
                        hintText: 'Example: Kingston, St. Ann, Montego Bay',
                        prefixIcon: const Icon(Icons.place_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: _messageController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: 'Message to church leaders',
                      hintText: _selectedChurchName == null
                          ? 'Optional'
                          : 'Tell ${_selectedChurchName!} who you are.',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  if (_policyLoadError != null) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _policyLoadError!,
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onErrorContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed:
                                _isLoadingPolicies ? null : _loadPolicies,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reload Policies'),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_isLoadingPolicies) ...[
                    const SizedBox(height: 24),
                    const LinearProgressIndicator(),
                  ] else if (_requiredPolicies.isEmpty) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Membership policies are not available yet.',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: _loadPolicies,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reload Policies'),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_requiredPolicies.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    Text(
                      'Required Policies & Consents',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    ..._requiredPolicies.map((policy) {
                      final key = policy['document_key'] as String;
                      final title = policy['title'] as String? ?? 'Policy';
                      final url = policy['content_url'] as String?;

                      return CheckboxListTile(
                        value: _acceptedPolicies[key] ?? false,
                        onChanged: (val) => setState(() {
                          _acceptedPolicies[key] = val ?? false;
                        }),
                        title: Wrap(
                          children: [
                            const Text('I accept the '),
                            _buildPolicyLink(title, url),
                            const Text('.'),
                          ],
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      );
                    }),
                    const SizedBox(height: 16),
                  ],
                  const SizedBox(height: 24),
                  AppButton(
                    text: 'Request Membership',
                    icon: Icons.send_outlined,
                    isLoading: _isLoading,
                    onPressed: _canSubmit ? _submitRequest : null,
                  ),
                  if (widget.allowBrowseFeed) ...[
                    const SizedBox(height: 12),
                    AppButton(
                      text: 'Browse Feed For Now',
                      icon: Icons.dynamic_feed_outlined,
                      isSecondary: true,
                      onPressed: () {
                        Navigator.of(context).pushNamedAndRemoveUntil(
                          '/community',
                          (route) => false,
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () async {
                      await Supabase.instance.client.auth.signOut();
                      if (!context.mounted) return;
                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        '/login',
                        (route) => false,
                      );
                    },
                    child: const Text('Sign Out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusScreen extends StatelessWidget {
  const _StatusScreen({
    required this.icon,
    required this.title,
    required this.message,
    required this.onRefresh,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      withBackground: true,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: AppCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  AppButton(
                    text: 'Check Again',
                    icon: Icons.refresh,
                    onPressed: onRefresh,
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () async {
                      await Supabase.instance.client.auth.signOut();
                      if (!context.mounted) return;
                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        '/login',
                        (route) => false,
                      );
                    },
                    child: const Text('Sign Out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
