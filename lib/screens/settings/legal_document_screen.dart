import 'package:flutter/material.dart';

import '../../widgets/ui/app_scaffold.dart';
import '../../widgets/ui/app_card.dart';

enum LegalDocumentType { terms, privacy, communityGuidelines, agePolicy }

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({
    super.key,
    required this.title,
    required this.documentType,
  });

  final String title;
  final LegalDocumentType documentType;

  @override
  Widget build(BuildContext context) {
    final sections = switch (documentType) {
      LegalDocumentType.terms => _termsSections,
      LegalDocumentType.privacy => _privacySections,
      LegalDocumentType.communityGuidelines => _communityGuidelinesSections,
      LegalDocumentType.agePolicy => _agePolicySections,
    };

    return AppScaffold(
      title: title,
      withBackground: true,
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemBuilder: (context, index) {
          final section = sections[index];
          return AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  section.body,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemCount: sections.length,
      ),
    );
  }
}

class _LegalSection {
  const _LegalSection(this.title, this.body);

  final String title;
  final String body;
}

const _termsSections = [
  _LegalSection(
    'Using Grace Connect',
    'Grace Connect is provided to help church members, ministry teams, and leaders communicate, coordinate events, manage attendance, and support church life. Use the app respectfully and only for lawful church community purposes.',
  ),
  _LegalSection(
    'Accounts and Roles',
    'Your access may depend on your church membership and assigned role. Leaders may approve, update, or remove role access when needed to keep church operations orderly.',
  ),
  _LegalSection(
    'Community Conduct',
    'Posts, comments, prayer requests, support tickets, and messages should be kind, truthful, and appropriate for a church community. Abusive, harassing, or harmful content may be removed.',
  ),
  _LegalSection(
    'Service Availability',
    'We work to keep the app reliable, but some features may be unavailable during updates, network outages, or third-party service interruptions.',
  ),
];

const _privacySections = [
  _LegalSection(
    'Information We Use',
    'Grace Connect uses account details, church membership details, profile information, roles, app settings, support tickets, and activity needed to provide the app experience.',
  ),
  _LegalSection(
    'Church Visibility',
    'Some profile and ministry information may be visible to leaders or members in your church based on your role and privacy settings.',
  ),
  _LegalSection(
    'Security',
    'Authentication is handled through Supabase. Keep your email and password safe, and use password reset if you suspect your account has been accessed by someone else.',
  ),
  _LegalSection(
    'Support Requests',
    'When you submit support requests, device and app details may be included so issues can be diagnosed and fixed.',
  ),
];

const _communityGuidelinesSections = [
  _LegalSection(
    'Faith-Centered Conduct',
    'Use Grace Connect with kindness, truthfulness, respect, and care for the church community. Harassment, abuse, threats, impersonation, and harmful content are not allowed.',
  ),
  _LegalSection(
    'Private Church Content',
    'Prayer requests, member conversations, internal announcements, groups, attendance, care, and counselling information are for approved church members and authorized leaders only.',
  ),
  _LegalSection(
    'Moderation',
    'Church leaders and Grace Connect platform staff may review reports, remove harmful content, restrict access, or escalate urgent safety concerns when needed.',
  ),
];

const _agePolicySections = [
  _LegalSection(
    '18+ Use',
    'Grace Connect is intended for adults who are 18 years of age or older. By creating an account, you confirm that you meet this age requirement.',
  ),
  _LegalSection(
    'Youth and Minors',
    'Youth ministry content and family information must be handled by authorized adults according to church policy, platform rules, and applicable law.',
  ),
];
