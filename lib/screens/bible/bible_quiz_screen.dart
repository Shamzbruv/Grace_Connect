import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/subscription_provider.dart';
import '../../screens/subscription/subscription_screen.dart';

class BibleQuizScreen extends StatefulWidget {
  const BibleQuizScreen({super.key});

  @override
  State<BibleQuizScreen> createState() => _BibleQuizScreenState();
}

class _BibleQuizScreenState extends State<BibleQuizScreen> {
  // Using a default verse for quiz generation context, could be random or daily
  final String _selectedVerse = 'John 3:16';
  List<String> _quizQuestions = [];
  bool _showQuiz = false;
  bool _isGeneratingQuiz = false;
  String _userAnswer = '';

  Future<void> _generateQuiz() async {
    final subscriptionProvider =
        Provider.of<SubscriptionProvider>(context, listen: false);

    // Check if subscription provider is available and check status
    // Safely handling potential missing provider implementation details
    try {
      if (!subscriptionProvider.isPremium) {
        _showSubscriptionDialog();
        return;
      }
    } catch (e) {
      // If provider not found or error, assume free for safety or show error
      debugPrint("Subscription check error: $e");
    }

    setState(() => _isGeneratingQuiz = true);

    const apiUrl =
        'https://api-inference.huggingface.co/models/microsoft/Phi-3-mini-4k-instruct';
    const token = String.fromEnvironment('HUGGINGFACE_API_TOKEN');
    if (token.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('AI quiz generation is not configured yet.')));
      }
      setState(() => _isGeneratingQuiz = false);
      return;
    }

    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'inputs':
              'Generate 3 fun multiple-choice questions from this Bible verse: $_selectedVerse. Make them engaging with emojis (e.g., 🎉, 😊), include 4 answer options per question with one correct answer, and provide the correct answer at the end of each question. Format as: Q1: [question]? A) [option1] B) [option2] C) [option3] D) [option4] Correct: [letter].',
        }),
      );

      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);
        final generatedText = data is List && data.isNotEmpty
            ? data[0]['generated_text'] as String
            : '';
        final cleanText = generatedText
            .replaceAll(
                'Generate 3 fun multiple-choice questions from this Bible verse: $_selectedVerse.',
                '')
            .trim();

        setState(() {
          _quizQuestions =
              cleanText.split('\n').where((line) => line.isNotEmpty).toList();
          _showQuiz = true;
        });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Failed to generate quiz. AI might be busy! 😅')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isGeneratingQuiz = false);
    }
  }

  void _showSubscriptionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Premium Feature 💎'),
        content: const Text(
            'Bible Quizzes are available for premium subscribers only! Unlock deeper study and fun quizzes for just \$4.99/mo.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Maybe Later')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const SubscriptionScreen()));
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
            child: const Text('Subscribe Now'),
          ),
        ],
      ),
    );
  }

  void _checkAnswer() {
    if (_userAnswer.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an answer before submitting.')),
      );
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Great job studying! Keep it up! 🎉')));
      setState(() {
        _showQuiz = false;
        _userAnswer = '';
        _quizQuestions = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Bible Quiz',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    const Icon(Icons.psychology,
                        size: 60, color: Colors.indigo),
                    const SizedBox(height: 16),
                    Text('Test your knowledge!',
                        style: GoogleFonts.poppins(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Text(
                      'Generate AI-powered quizzes based on bible verses.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.merriweather(
                          fontSize: 16, color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _isGeneratingQuiz ? null : _generateQuiz,
                      icon: _isGeneratingQuiz
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.play_arrow),
                      label: Text(
                          _isGeneratingQuiz ? 'Generating...' : 'Start Quiz'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber[700],
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_showQuiz) ...[
              Text('Quiz Time! 🧠',
                  style: GoogleFonts.poppins(
                      fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              ..._quizQuestions.map((q) => Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    color: Colors.indigo[50],
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Text(q, style: GoogleFonts.poppins(fontSize: 16)),
                    ),
                  )),
              const SizedBox(height: 20),
              TextField(
                onChanged: (val) => _userAnswer = val,
                decoration: const InputDecoration(
                  labelText: 'Type your answer check (e.g., A, B...)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.edit),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                    onPressed: _checkAnswer,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo),
                    child: const Text('Submit Answer')),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
