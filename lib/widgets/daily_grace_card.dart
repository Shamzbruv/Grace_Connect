import 'package:flutter/material.dart';

import '../services/daily_grace_service.dart';

class DailyGraceCard extends StatelessWidget {
  const DailyGraceCard(
      {super.key, this.scripture, this.onRead, this.onConnect});
  final DailyScripture? scripture;
  final VoidCallback? onRead;
  final VoidCallback? onConnect;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF173E59), Color(0xFF101E33)]),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0xFF536279)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.auto_awesome_outlined,
                color: Color(0xFFE8C77F), size: 20),
            SizedBox(width: 10),
            Flexible(
                child: Text('DAILY GRACE',
                    style: TextStyle(
                        color: Color(0xFFE8C77F),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2)))
          ]),
          const SizedBox(height: 20),
          Text(
              scripture?.text ??
                  'A moment in God’s Word, wherever your day takes you.',
              style: const TextStyle(
                  fontFamily: 'Georgia',
                  color: Color(0xFFFFF9EB),
                  fontSize: 23,
                  height: 1.5)),
          const SizedBox(height: 14),
          Text(
              scripture == null
                  ? 'SCRIPTURE • EVERY DAY'
                  : '${scripture!.reference} · WEB',
              style: const TextStyle(color: Color(0xFFE8C77F), fontSize: 13)),
          if (onRead != null) ...[
            const SizedBox(height: 22),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                  onPressed: onRead,
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: const Text('Read Scripture'),
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE8C77F),
                      foregroundColor: const Color(0xFF102C45))),
              if (onConnect != null)
                OutlinedButton(
                    onPressed: onConnect,
                    style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFFF9EB),
                        side: const BorderSide(color: Color(0xFF677788))),
                    child: const Text('Connect')),
            ]),
          ],
        ]),
      );
}

class DailyGraceWidgetSettings extends StatelessWidget {
  const DailyGraceWidgetSettings({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FutureBuilder<DailyScripture>(
              future: DailyGraceService.scripture(),
              builder: (context, snapshot) => DailyGraceCard(
                  scripture: snapshot.data,
                  onRead: () => Navigator.of(context).pushNamed('/daily_grace'),
                  onConnect: () =>
                      Navigator.of(context).pushNamed('/community'))),
          const SizedBox(height: 12),
          const Text('Daily Grace on your home screen',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          const SizedBox(height: 6),
          const Text(
              'A fresh Scripture each day, even offline. Resize the widget to make more room for the verse.'),
          const SizedBox(height: 12),
          FilledButton.icon(
              icon: const Icon(Icons.add_to_home_screen),
              label: const Text('Add home-screen widget'),
              onPressed: () async {
                final shown = await DailyGraceService.requestPin();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(shown
                        ? 'Confirm Add in your phone’s home-screen prompt.'
                        : 'Touch and hold a blank area of your home screen, choose Widgets, then Grace Connect → Daily Grace.')));
              }),
        ]),
      );
}
