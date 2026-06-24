import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/church_service.dart';
import '../../services/membership_service.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../login screen/login_screen.dart';
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

        final membership = snapshot.data;
        if (membership == null || !membership.authenticated) {
          return const LoginScreen();
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
          return widget.child;
        }

        if (membership.hasPendingChurchApplication) {
          return _StatusScreen(
            icon: Icons.assignment_outlined,
            title: 'Church Application Pending',
            message:
                'Your church registration is ${membership.churchApplicationStatus ?? 'under review'}. Grace Connect will activate church access after approval.',
            onRefresh: _refresh,
          );
        }

        if (membership.hasPendingMembership) {
          return _StatusScreen(
            icon: Icons.hourglass_top_outlined,
            title: 'Membership Pending',
            message:
                'Your request to join ${membership.churchName ?? 'this church'} is waiting for church leadership approval.',
            onRefresh: _refresh,
            secondaryActionLabel: 'Cancel Request',
            onSecondaryAction: () async {
              await MembershipService().cancelMembershipRequest();
              _refresh();
            },
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

        return FindChurchScreen(onSubmitted: _refresh);
      },
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
  });

  final String title;
  final String intro;
  final VoidCallback? onSubmitted;

  @override
  State<FindChurchScreen> createState() => _FindChurchScreenState();
}

class _FindChurchScreenState extends State<FindChurchScreen> {
  final _churchSearchController = TextEditingController();
  final _messageController = TextEditingController();
  String? _selectedChurchId;
  String? _selectedChurchName;
  bool _isLoading = false;

  @override
  void dispose() {
    _churchSearchController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    final churchId = _selectedChurchId;
    if (churchId == null || churchId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select an approved church first.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await MembershipService().requestMembership(
        churchId: churchId,
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
                  const SizedBox(height: 24),
                  AppButton(
                    text: 'Request Membership',
                    icon: Icons.send_outlined,
                    isLoading: _isLoading,
                    onPressed: _submitRequest,
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

class _StatusScreen extends StatelessWidget {
  const _StatusScreen({
    required this.icon,
    required this.title,
    required this.message,
    required this.onRefresh,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onRefresh;
  final String? secondaryActionLabel;
  final Future<void> Function()? onSecondaryAction;

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
                  if (secondaryActionLabel != null &&
                      onSecondaryAction != null) ...[
                    const SizedBox(height: 12),
                    AppButton(
                      text: secondaryActionLabel!,
                      icon: Icons.cancel_outlined,
                      isSecondary: true,
                      onPressed: () {
                        onSecondaryAction!.call();
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
