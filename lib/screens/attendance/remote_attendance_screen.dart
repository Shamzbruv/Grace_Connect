import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/user_role_provider.dart';
import '../../services/attendance_service.dart';
import '../../widgets/ui/app_loader.dart';

class RemoteAttendanceScreen extends StatefulWidget {
  const RemoteAttendanceScreen({super.key});

  @override
  State<RemoteAttendanceScreen> createState() => _RemoteAttendanceScreenState();
}

class _RemoteAttendanceScreenState extends State<RemoteAttendanceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  final _engagementController = TextEditingController();

  bool _isLoading = false;
  String? _selectedReason;

  final List<String> _reasons = [
    'Sick / Medical',
    'Traveling',
    'Work Conflict',
    'Caring for Family',
    'Distance / Transportation',
    'Other',
  ];

  Future<void> _submitAttendance() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a reason for absence')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = Provider.of<UserRoleProvider>(context, listen: false).user;
      final churchId = Provider.of<UserRoleProvider>(context, listen: false)
          .userProfile
          ?.churchId;

      if (user == null || churchId == null) {
        throw Exception('User profile not loaded');
      }

      await AttendanceService().markRemotePresent(
        userId: user.uid,
        churchId: churchId,
        reason: _selectedReason == 'Other'
            ? _reasonController.text
            : _selectedReason!,
        engagementAnswer: _engagementController.text,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Checked in remotely successfully!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Remote Check-In',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo,
      ),
      body: _isLoading
          ? const AppLoader()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Join Us Remotely',
                      style: GoogleFonts.poppins(
                          fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Please let us know why you strictly cannot make it in person today, and answer the engagement question below.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),

                    // Reason Dropdown
                    DropdownButtonFormField<String>(
                      value: _selectedReason,
                      decoration: const InputDecoration(
                        labelText: 'Reason for Absence',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.sick_outlined),
                      ),
                      items: _reasons
                          .map(
                              (r) => DropdownMenuItem(value: r, child: Text(r)))
                          .toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedReason = val;
                          if (val != 'Other') _reasonController.clear();
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // "Other" Text Field
                    if (_selectedReason == 'Other')
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: TextFormField(
                          controller: _reasonController,
                          decoration: const InputDecoration(
                            labelText: 'Please specify reason',
                            border: OutlineInputBorder(),
                          ),
                          validator: (val) =>
                              val == null || val.isEmpty ? 'Required' : null,
                        ),
                      ),

                    // Engagement Question
                    Text(
                      'Engagement Verification',
                      style: GoogleFonts.poppins(
                          fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: Colors.indigo.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.lightbulb, color: Colors.indigo),
                          SizedBox(width: 12),
                          Expanded(
                              child: Text(
                                  'What is the main topic of today\'s sermon or reading?')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _engagementController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Your Answer',
                        border: OutlineInputBorder(),
                        hintText:
                            'e.g. The Pastor spoke about faith and works...',
                      ),
                      validator: (val) => val == null || val.length < 10
                          ? 'Please provide a clearer answer (min 10 chars)'
                          : null,
                    ),
                    const SizedBox(height: 32),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _submitAttendance,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Check In Remotely'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          textStyle: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
