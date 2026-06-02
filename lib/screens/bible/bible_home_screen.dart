import 'package:flutter/material.dart';
import 'package:grace_connect/screens/bible/bible_books_screen.dart';
import 'package:grace_connect/screens/bible/bible_quiz_screen.dart';
import 'package:grace_connect/screens/bible/bible_search_delegate.dart';

class BibleHomeScreen extends StatefulWidget {
  const BibleHomeScreen({
    super.key,
    this.showBottomNavigation = true,
  });

  final bool showBottomNavigation;

  @override
  State<BibleHomeScreen> createState() => _BibleHomeScreenState();
}

class _BibleHomeScreenState extends State<BibleHomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const BibleBooksScreen(),
    const Center(child: Text("Search")), // Managed by onTap
    const BibleQuizScreen(),
  ];

  void _onTabTapped(int index) {
    if (index == 1) {
      // Search Tab tapped, show search delegate instead of switching tab
      showSearch(context: context, delegate: BibleSearchDelegate());
    } else {
      setState(() {
        _currentIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _currentIndex == 1
          ? const BibleBooksScreen()
          : _screens[_currentIndex], // Fallback if index stuck
      bottomNavigationBar: widget.showBottomNavigation
          ? BottomNavigationBar(
              currentIndex: _currentIndex,
              selectedItemColor: Theme.of(context).colorScheme.primary,
              unselectedItemColor: Theme.of(context).colorScheme.onSurface,
              onTap: _onTabTapped,
              items: const [
                BottomNavigationBarItem(
                    icon: Icon(Icons.menu_book), label: 'Read'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.search), label: 'Search'),
                BottomNavigationBarItem(icon: Icon(Icons.quiz), label: 'Quiz'),
              ],
            )
          : null,
    );
  }
}
