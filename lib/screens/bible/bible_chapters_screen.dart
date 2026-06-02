import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/bible_data.dart';
import 'bible_reader_screen.dart';

class BibleChaptersScreen extends StatelessWidget {
  final BibleBook book;
  const BibleChaptersScreen({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(book.name,
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          childAspectRatio: 1,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: book.chapters,
        itemBuilder: (ctx, i) {
          final chapterNum = i + 1;
          return InkWell(
            onTap: () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          BibleReaderScreen(book: book, chapter: chapterNum)));
            },
            child: Container(
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.indigo.shade100),
              ),
              alignment: Alignment.center,
              child: Text(
                '$chapterNum',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold, color: Colors.indigo),
              ),
            ),
          );
        },
      ),
    );
  }
}
