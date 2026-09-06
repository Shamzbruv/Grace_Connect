import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../models/bible_data.dart';
import 'package:google_fonts/google_fonts.dart';
import 'bible_reader_screen.dart';

class BibleScreen extends StatefulWidget {
  const BibleScreen({super.key});

  @override
  State<BibleScreen> createState() => _BibleScreenState();
}

class _BibleScreenState extends State<BibleScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List<BibleBook> _filteredBooks = BibleData.allBooks;
  String _currentTestament = 'Old'; // 'Old' or 'New'

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _currentTestament = _tabController.index == 0 ? 'Old' : 'New';
          _onSearchChanged(); // Re-filter
        });
      }
    });
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredBooks = BibleData.allBooks.where((book) {
        final matchesTestament = book.testament == _currentTestament;
        final matchesQuery = book.name.toLowerCase().contains(query);
        return matchesTestament && matchesQuery;
      }).toList();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Holy Bible',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.gold,
          indicatorWeight: 3,
          labelColor: isDark ? Colors.white : AppColors.primary,
          unselectedLabelColor: Colors.grey,
          labelStyle:
              GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
          tabs: const [
            Tab(text: 'Old Testament'),
            Tab(text: 'New Testament'),
          ],
        ),
      ),
      body: Column(
        children: [
          // 1. Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              decoration: InputDecoration(
                hintText: 'Search books...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor:
                    isDark ? colorScheme.surfaceContainerHighest : Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // 2. Book List
          Expanded(
            child: _filteredBooks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.menu_book,
                            size: 60,
                            color: colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.55)),
                        const SizedBox(height: 16),
                        Text('No books found',
                            style:
                                TextStyle(color: colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filteredBooks.length,
                    itemBuilder: (context, index) {
                      final book = _filteredBooks[index];
                      return _buildBookCard(context, book);
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        selectedIndex: 0,
        onDestinationSelected: (index) {
          if (index == 1) _searchFocus.requestFocus();
          if (index == 2) Navigator.of(context).pushNamed('/daily_bible_quiz');
        },
        indicatorColor: colorScheme.primaryContainer,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Read',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: 'Search',
          ),
          NavigationDestination(
            icon: Icon(Icons.quiz_outlined),
            selectedIcon: Icon(Icons.quiz),
            label: 'Quiz',
          ),
        ],
      ),
    );
  }

  Widget _buildBookCard(BuildContext context, BibleBook book) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        onTap: () {
          // Navigate to Reader
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BibleReaderScreen(book: book, chapter: 1),
            ),
          );
        },
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            book.name.substring(0, 1),
            style: GoogleFonts.outfit(
              color: colorScheme.primary,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ),
        title: Text(
          book.name,
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: colorScheme.onSurface,
          ),
        ),
        subtitle: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                book.category,
                style: GoogleFonts.outfit(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${book.chapters} Chapters',
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        trailing:
            Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}
