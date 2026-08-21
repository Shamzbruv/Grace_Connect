import 'package:flutter/material.dart';

/// Colors for data visualizations (bar/line charts, breakdowns).
///
/// These are a categorical set, not [AppColors.success]/[warning]/[error] --
/// status colors are tuned for icon+label pairing and deliberately fail
/// lightness/contrast checks when used as bare chart fills (validated via
/// dataviz's palette validator). These four hues are pulled from the
/// dataviz skill's own validated 8-color categorical theme, chosen for their
/// semantic fit (present=green, late=amber, remote=blue, absent=red) and
/// re-validated together as a 4-slot set for both light and dark surfaces.
class ChartPalette {
  ChartPalette._();

  static Color present(Brightness brightness) =>
      brightness == Brightness.dark
          ? const Color(0xFF199E70)
          : const Color(0xFF1BAF7A);

  static Color late(Brightness brightness) => brightness == Brightness.dark
      ? const Color(0xFFC98500)
      : const Color(0xFFEDA100);

  static Color remote(Brightness brightness) => brightness == Brightness.dark
      ? const Color(0xFF3987E5)
      : const Color(0xFF2A78D6);

  static Color absent(Brightness brightness) => brightness == Brightness.dark
      ? const Color(0xFFE66767)
      : const Color(0xFFE34948);

  /// Recessive grid/axis ink -- never the loudest thing in the chart.
  static Color axis(Brightness brightness) => brightness == Brightness.dark
      ? Colors.white.withValues(alpha: 0.14)
      : Colors.black.withValues(alpha: 0.10);
}
