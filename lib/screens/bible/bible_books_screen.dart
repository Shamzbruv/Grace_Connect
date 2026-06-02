import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/bible_data.dart';
import '../../services/bible_streak_service.dart';
import 'bible_chapters_screen.dart';

class BibleBooksScreen extends StatefulWidget {
  const BibleBooksScreen({super.key});

  @override
  State<BibleBooksScreen> createState() => _BibleBooksScreenState();
}

class _BibleBooksScreenState extends State<BibleBooksScreen> {
  late Future<int> _streakFuture;

  @override
  void initState() {
    super.initState();
    _streakFuture = BibleStreakService().currentStreak();
  }

  void _refreshStreak() {
    setState(() {
      _streakFuture = BibleStreakService().currentStreak();
    });
  }

  @override
  Widget build(BuildContext context) {
    final oldTestament =
        BibleData.allBooks.where((b) => b.testament == 'Old').toList();
    final newTestament =
        BibleData.allBooks.where((b) => b.testament == 'New').toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('The Bible',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.indigo,
          actions: [
            FutureBuilder<int>(
              future: _streakFuture,
              builder: (context, snapshot) {
                final streak = snapshot.data ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Chip(
                    avatar: const Icon(Icons.local_fire_department, size: 18),
                    label: Text('$streak day${streak == 1 ? '' : 's'}'),
                    visualDensity: VisualDensity.compact,
                  ),
                );
              },
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Old Testament'),
              Tab(text: 'New Testament'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildBookList(context, oldTestament),
            _buildBookList(context, newTestament),
          ],
        ),
      ),
    );
  }

  Widget _buildBookList(BuildContext context, List<BibleBook> books) {
    return ListView.builder(
      itemCount: books.length,
      itemBuilder: (ctx, i) {
        final book = books[i];
        return ListTile(
          title: Text(book.name,
              style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => BibleChaptersScreen(book: book),
              ),
            ).then((_) => _refreshStreak());
          },
        );
      },
    );
  }
}
