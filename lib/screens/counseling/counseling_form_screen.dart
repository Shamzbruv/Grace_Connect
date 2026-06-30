import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/user_role_provider.dart';
import '../../models/counseling_request_model.dart';
import '../../services/counseling_service.dart';
import '../../widgets/ui/app_loader.dart';

class CounselingFormScreen extends StatefulWidget {
  const CounselingFormScreen({super.key});

  @override
  State<CounselingFormScreen> createState() => _CounselingFormScreenState();
}

class _CounselingFormScreenState extends State<CounselingFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descController = TextEditingController();

  bool _isLoading = false;
  String _category = 'Spiritual';
  String _urgency = 'Low';
  String _contactMethod = 'Phone';

  final List<String> _categories = [
    'Spiritual',
    'Marriage / Relationship',
    'Grief / Loss',
    'Addiction / Recovery',
    'Mental Health',
    'Other',
  ];

  final List<String> _urgencies = ['Low', 'Medium', 'High'];
  final List<String> _contactMethods = ['Phone', 'Email', 'In-Person'];

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = Provider.of<UserRoleProvider>(context, listen: false).user;
      final churchId = Provider.of<UserRoleProvider>(context, listen: false)
          .userProfile
          ?.churchId;

      if (user == null || churchId == null) {
        throw Exception('User profile not loaded');
      }

      final request = CounselingRequest(
        id: '', // Service will generate ID
        userId: user.uid,
        churchId: churchId,
        category: _category,
        urgency: _urgency,
        preferredContactMethod: _contactMethod,
        description: _descController.text,
        createdAt: DateTime.now(),
      );

      await CounselingService().submitRequest(request);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request submitted confidentially.')),
        );
        Navigator.pop(context); // Go back to Intro
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
        title: Text('New Request',
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
                      'How can we help?',
                      style: GoogleFonts.poppins(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Please provide some details so we can connect you with the right person.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),

                    // Category
                    DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: _category,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.category),
                      ),
                      items: _categories
                          .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (val) => setState(() => _category = val!),
                    ),
                    const SizedBox(height: 16),

                    // Urgency
                    DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: _urgency,
                      decoration: const InputDecoration(
                        labelText: 'Urgency',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.warning_amber_rounded),
                      ),
                      items: _urgencies
                          .map(
                              (u) => DropdownMenuItem(value: u, child: Text(u)))
                          .toList(),
                      onChanged: (val) => setState(() => _urgency = val!),
                    ),
                    const SizedBox(height: 16),

                    // Contact Method
                    DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: _contactMethod,
                      decoration: const InputDecoration(
                        labelText: 'Preferred Contact Method',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.contact_phone),
                      ),
                      items: _contactMethods
                          .map(
                              (m) => DropdownMenuItem(value: m, child: Text(m)))
                          .toList(),
                      onChanged: (val) => setState(() => _contactMethod = val!),
                    ),
                    const SizedBox(height: 16),

                    // Description
                    TextFormField(
                      controller: _descController,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Brief Description (Confidential)',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      validator: (val) => val == null || val.isEmpty
                          ? 'Please describe your request'
                          : null,
                    ),
                    const SizedBox(height: 32),

                    // Submit
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _submitRequest,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                        ),
                        child: Text(
                          'Submit Confidential Request',
                          style: GoogleFonts.poppins(
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
