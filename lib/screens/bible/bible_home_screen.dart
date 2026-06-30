import 'package:flutter/material.dart';
import 'package:grace_connect/screens/bible/bible_books_screen.dart';
import 'package:grace_connect/screens/bible/bible_quiz_screen.dart';
import 'package:grace_connect/screens/bible/bible_search_delegate.dart';

class BibleHomeScreen extends StatefulWidget {
  const BibleHomeScreen({
    super.key,
    this.showBottomNavigation = true,
    this.allowDailyQuiz = true,
  });

  final bool showBottomNavigation;
  final bool allowDailyQuiz;

  @override
  State<BibleHomeScreen> createState() => _BibleHomeScreenState();
}

class _BibleHomeScreenState extends State<BibleHomeScreen> {
  int _currentIndex = 0;

  void _onTabTapped(int index) {
    if (index == 1) {
      // Search Tab tapped, show search delegate instead of switching tab
      showSearch(context: context, delegate: BibleSearchDelegate());
    } else if (index == 2 && !widget.allowDailyQuiz) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Daily Bible Quiz is paused until your church subscription is active.',
          ),
        ),
      );
    } else {
      setState(() {
        _currentIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (_currentIndex) {
      2 => const BibleQuizScreen(),
      _ => BibleBooksScreen(allowDailyQuiz: widget.allowDailyQuiz),
    };

    return Scaffold(
      body: body,
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
                BottomNavigationBarItem(
                    icon: Icon(Icons.psychology_alt_outlined), label: 'Quiz'),
              ],
            )
          : null,
    );
  }
}
