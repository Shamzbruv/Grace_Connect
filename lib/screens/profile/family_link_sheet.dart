import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/family_relationship.dart';
import '../../models/user_profile.dart';
import '../../services/family_service.dart';

class FamilyLinkSheet extends StatefulWidget {
  const FamilyLinkSheet({
    super.key,
    required this.currentUser,
  });

  final UserProfile currentUser;

  @override
  State<FamilyLinkSheet> createState() => _FamilyLinkSheetState();
}

class _FamilyLinkSheetState extends State<FamilyLinkSheet> {
  final FamilyService _familyService = FamilyService();
  final TextEditingController _memberController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  FamilyMemberSummary? _selectedMember;
  String _relationshipType = 'father';
  bool _isSending = false;

  @override
  void dispose() {
    _memberController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _sendRequest() async {
    final selectedMember = _selectedMember;
    if (selectedMember == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select the family member first.')),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      await _familyService.requestFamilyLink(
        requester: widget.currentUser,
        relatedMember: selectedMember,
        relationshipType: _relationshipType,
        note: _noteController.text,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Family request sent to ${selectedMember.fullName}.',
          ),
        ),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      final isDuplicate =
          e.message.toLowerCase().contains('duplicate') || e.code == '23505';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isDuplicate
                ? 'There is already an active request for this family link.'
                : 'Could not send family request: ${e.message}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send family request: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedRelationship =
        FamilyRelationship.optionFor(_relationshipType);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.dividerColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Connect Family',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'They will need to approve this before it becomes official.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _relationshipType,
                isExpanded: true,
                items: FamilyRelationship.relationshipOptions
                    .map(
                      (option) => DropdownMenuItem(
                        value: option.value,
                        child: Text(
                          option.menuLabel,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                decoration: const InputDecoration(
                  labelText: 'Relationship',
                  prefixIcon: Icon(Icons.family_restroom_outlined),
                ),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _relationshipType = value);
                },
              ),
              const SizedBox(height: 8),
              Text(
                selectedRelationship.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TypeAheadField<FamilyMemberSummary>(
                controller: _memberController,
                suggestionsCallback: (query) {
                  return _familyService.searchMembers(
                    query: query,
                    churchId: widget.currentUser.placeId,
                    excludeUid: widget.currentUser.uid,
                  );
                },
                builder: (context, controller, focusNode) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'Family member',
                      hintText: 'Search church members',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) => _selectedMember = null,
                  );
                },
                itemBuilder: (context, member) {
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: member.photoUrl.isNotEmpty
                          ? NetworkImage(member.photoUrl)
                          : null,
                      child: member.photoUrl.isEmpty
                          ? Text(member.fullName[0].toUpperCase())
                          : null,
                    ),
                    title: Text(member.fullName),
                  );
                },
                onSelected: (member) {
                  setState(() {
                    _selectedMember = member;
                    _memberController.text = member.fullName;
                  });
                },
                emptyBuilder: (context) => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No matching members found.'),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _noteController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Relationship context',
                  hintText:
                      'Optional detail, such as married through my daughter, step-family, adopted, or church family.',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _isSending ? null : _sendRequest,
                  icon: _isSending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined),
                  label: Text(_isSending ? 'Sending...' : 'Send Request'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
