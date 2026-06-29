import 'package:flutter/material.dart';

class NotificationSectionIcon extends StatelessWidget {
  const NotificationSectionIcon({
    super.key,
    this.size = 26,
  });

  static const assetPath = 'assets/notification_section_icon.png';

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
}
