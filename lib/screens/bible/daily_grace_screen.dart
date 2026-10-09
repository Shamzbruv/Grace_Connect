import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../access/app_feature.dart';
import '../../models/bible_passage_reference.dart';
import '../../services/daily_grace_service.dart';
import '../../widgets/auth_required.dart';
import '../../widgets/daily_grace_card.dart';
import 'bible_reader_screen.dart';

/// The full widget passage remains readable without a session or a connection.
class DailyGraceScreen extends StatefulWidget {
  const DailyGraceScreen({super.key, this.reference});
  final String? reference;
  @override
  State<DailyGraceScreen> createState() => _DailyGraceScreenState();
}

class _DailyGraceScreenState extends State<DailyGraceScreen> {
  late final _scripture =
      DailyGraceService.scripture(reference: widget.reference);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('Daily Grace'),
            systemOverlayStyle: Theme.of(context).brightness == Brightness.dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark),
        body: FutureBuilder<DailyScripture>(
            future: _scripture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return Center(
                    child: snapshot.hasError
                        ? const Text('Please reopen Daily Grace.')
                        : const CircularProgressIndicator());
              }
              final verse = snapshot.data!;
              final reference = BiblePassageReference.tryParse(verse.reference);
              return ListView(padding: const EdgeInsets.all(24), children: [
                DailyGraceCard(scripture: verse),
                const SizedBox(height: 24),
                Text('Pause. Read. Pray.',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 10),
                const Text(
                    'Take a quiet moment with God. What does this passage invite you to bring to Him today?',
                    style: TextStyle(fontSize: 17, height: 1.6)),
                const SizedBox(height: 24),
                FilledButton.icon(
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('Read the full chapter'),
                    onPressed: reference == null
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) => AuthRequired(
                                    requiredFeature: AppFeature.bibleReading,
                                    child: BibleReaderScreen(
                                        book: reference.book,
                                        chapter: reference.chapter,
                                        initialVerse: reference.startVerse,
                                        initialVerseEnd:
                                            reference.endVerse))))),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pushNamed('/community'),
                    icon: const Icon(Icons.people_outline),
                    label: const Text('Connect with the community')),
                const SizedBox(height: 20),
                const Text('World English Bible · Public domain',
                    textAlign: TextAlign.center),
              ]);
            }),
      );
}
