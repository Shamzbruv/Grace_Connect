import 'package:flutter/material.dart';
import '../../services/bible_service.dart';
import 'package:google_fonts/google_fonts.dart';

class BibleSearchDelegate extends SearchDelegate {
  final BibleService _bibleService = BibleService();

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, null);
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    if (query.isEmpty) {
      return const Center(child: Text("Enter a reference like 'John 3:16'"));
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: _bibleService.getPassage(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(child: Text('Error found: ${snapshot.error}'));
        } else if (!snapshot.hasData) {
          return const Center(child: Text('No results found.'));
        }

        final data = snapshot.data!;
        final text = data['text'] ?? '';
        final reference = data['reference'] ?? query;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(reference,
                style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo)),
            const SizedBox(height: 16),
            Text(text,
                style: GoogleFonts.merriweather(fontSize: 18, height: 1.5)),
          ],
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    // Basic implementation: just show what user typed as a suggestion to search
    return ListView(
      children: [
        ListTile(
          title: Text(query.isEmpty
              ? "Search for verses (e.g. John 3:16)"
              : "Read '$query'"),
          onTap: () {
            if (query.isNotEmpty) showResults(context);
          },
        )
      ],
    );
  }
}
