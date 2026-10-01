import 'package:flutter/material.dart';

class ReelModeHeader extends StatelessWidget {
  const ReelModeHeader(
      {super.key,
      required this.mode,
      required this.onModeChanged,
      required this.onCreate});
  final String mode;
  final ValueChanged<String> onModeChanged;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Row(children: [
        // Match the create button and its outer spacing so the tabs are centered
        // on the entire video, including on narrow phones and with larger text.
        const SizedBox(width: 52),
        Expanded(
            child: Center(
                child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      key: const Key('reel-mode-tabs'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final item in const {
                          'following': 'Following',
                          'discover': 'Discover'
                        }.entries)
                          TextButton(
                              onPressed: () => onModeChanged(item.key),
                              child: Text(item.value,
                                  style: TextStyle(
                                      color: mode == item.key
                                          ? Colors.white
                                          : Colors.white70,
                                      fontWeight: mode == item.key
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                      shadows: const [
                                        Shadow(
                                            color: Colors.black54,
                                            blurRadius: 6)
                                      ]))),
                      ],
                    )))),
        SizedBox(
            width: 48,
            child: IconButton(
                tooltip: 'New reel',
                onPressed: onCreate,
                icon: const Icon(Icons.add_box_outlined, color: Colors.white))),
        const SizedBox(width: 4),
      ]);
}
