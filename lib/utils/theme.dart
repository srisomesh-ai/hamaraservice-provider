import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Brand palette (same colours as hamaraservice.com).
class AppColors {
  static const brand     = Color(0xFFE8651A); // orange — secondary / accents
  static const teal      = Color(0xFF1B6B7A); // primary
  static const teal2     = Color(0xFF134F5C); // dark primary (status bar / hero)
  static const tealSoft  = Color(0xFFE3F1F3);
  static const ink       = Color(0xFF13262B);
  static const ink2      = Color(0xFF3B4D53);
  static const muted     = Color(0xFF6B7F87);
  static const line      = Color(0xFFDDE7EA);
  static const bg        = Color(0xFFF3F7F8);
  static const white     = Color(0xFFFFFFFF);
  static const green     = Color(0xFF16A34A);
  static const greenSoft = Color(0xFFE6F6EC);
  static const yellow    = Color(0xFFD97706);
  static const yellowSoft= Color(0xFFFFF4DE);
  static const red       = Color(0xFFDC2626);
  static const redSoft   = Color(0xFFFDECEC);
  static const blueSoft  = Color(0xFFE0F0F7);
}

/// Booking status → label + colours, shared by every screen so the wording
/// matches the website (badge = status with "_" → " ").
class StatusStyle {
  final String label;
  final Color fg;
  final Color bg;
  const StatusStyle(this.label, this.fg, this.bg);

  static StatusStyle of(String status, {String paymentStatus = ''}) {
    switch (status) {
      case 'searching':
        return const StatusStyle('Searching', Color(0xFF8A6D00), Color(0xFFFFF3CD));
      case 'price_quoted':
        return const StatusStyle('Price quoted', Color(0xFF0F6D33), Color(0xFFD1F2DD));
      case 'negotiating':
        return const StatusStyle('Negotiating', Color(0xFF9A4C00), Color(0xFFFDE8D0));
      case 'negotiation_final':
        return const StatusStyle('Final offer sent', Color(0xFF9A4C00), Color(0xFFFDE8D0));
      case 'confirmed':
        return const StatusStyle('Confirmed', Color(0xFF0F6D33), Color(0xFFD1F2DD));
      case 'active':
        return const StatusStyle('In progress', Color(0xFF0B5A77), Color(0xFFCFE9F5));
      case 'completed':
        return paymentStatus == 'paid'
            ? const StatusStyle('Paid', Color(0xFF0F6D33), Color(0xFFD1F2DD))
            : const StatusStyle('Payment pending', Color(0xFF8A6D00), Color(0xFFFFF3CD));
      case 'cancelled':
        return const StatusStyle('Cancelled', AppColors.red, AppColors.redSoft);
      case 'pending':
        return const StatusStyle('Pending', Color(0xFF8A6D00), Color(0xFFFFF3CD));
      case 'approved':
        return const StatusStyle('Approved', Color(0xFF0F6D33), Color(0xFFD1F2DD));
      case 'rejected':
        return const StatusStyle('Rejected', AppColors.red, AppColors.redSoft);
      default:
        return StatusStyle(status.replaceAll('_', ' '), const Color(0xFF334155),
            const Color(0xFFE2E8F0));
    }
  }
}

class AppTheme {
  /// Light status bar icons on the teal app bar.
  static const SystemUiOverlayStyle overlay = SystemUiOverlayStyle(
    statusBarColor: AppColors.teal,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  static ThemeData get theme => build();

  /// [fontFamily] / [fontFamilyFallback] are only set by the screenshot
  /// tests (real fonts); the app uses the platform font (Roboto on Android).
  static ThemeData build({String? fontFamily, List<String>? fontFamilyFallback}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.teal,
      primary: AppColors.teal,
      onPrimary: Colors.white,
      primaryContainer: AppColors.tealSoft,
      onPrimaryContainer: AppColors.teal2,
      secondary: AppColors.brand,
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFFDE6D8),
      onSecondaryContainer: const Color(0xFF7A3000),
      tertiary: AppColors.teal2,
      error: AppColors.red,
      surface: Colors.white,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.muted,
      outline: const Color(0xFFB9C8CD),
      outlineVariant: AppColors.line,
      background: AppColors.bg,
      surfaceTint: Colors.transparent,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: fontFamily);
    var text = base.textTheme.copyWith(
      headlineSmall: base.textTheme.headlineSmall
          ?.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
      titleLarge: base.textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
      titleMedium: base.textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
      titleSmall: base.textTheme.titleSmall
          ?.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(color: AppColors.ink),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(color: AppColors.ink2),
      bodySmall: base.textTheme.bodySmall?.copyWith(color: AppColors.muted),
      labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );
    if (fontFamilyFallback != null) text = text.apply(fontFamilyFallback: fontFamilyFallback);

    final btnShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    final btnText = TextStyle(fontFamily: fontFamily, fontFamilyFallback: fontFamilyFallback, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.1);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
        systemOverlayStyle: overlay,
        titleTextStyle: text.titleLarge?.copyWith(color: Colors.white, fontSize: 20),
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 3,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black,
        indicatorColor: AppColors.tealSoft,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: MaterialStateProperty.resolveWith((s) => IconThemeData(
            size: 24,
            color: s.contains(MaterialState.selected) ? AppColors.teal2 : AppColors.muted)),
        labelTextStyle: MaterialStateProperty.resolveWith((s) => TextStyle(fontFamily: fontFamily, fontFamilyFallback: fontFamilyFallback, 
            fontSize: 12,
            fontWeight: s.contains(MaterialState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(MaterialState.selected) ? AppColors.teal2 : AppColors.muted)),
      ),
      cardTheme: CardTheme(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: btnShape,
          textStyle: btnText,
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.teal,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 52),
          shape: btnShape,
          textStyle: btnText,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.teal,
          minimumSize: const Size(64, 52),
          shape: btnShape,
          textStyle: btnText,
          side: const BorderSide(color: Color(0xFFB9C8CD)),
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.teal,
          textStyle: btnText,
          shape: btnShape,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFC5D3D7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFC5D3D7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.teal, width: 2),
        ),
        labelStyle: TextStyle(fontFamily: fontFamily, fontFamilyFallback: fontFamilyFallback, color: AppColors.muted),
        hintStyle: TextStyle(fontFamily: fontFamily, fontFamilyFallback: fontFamilyFallback, color: Color(0xFF9AABB1)),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: Colors.white,
        selectedColor: AppColors.tealSoft,
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: TextStyle(fontFamily: fontFamily, fontFamilyFallback: fontFamilyFallback, fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.ink2),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.standard,
          backgroundColor: MaterialStateProperty.resolveWith((s) =>
              s.contains(MaterialState.selected) ? AppColors.tealSoft : Colors.white),
          foregroundColor: MaterialStateProperty.resolveWith((s) =>
              s.contains(MaterialState.selected) ? AppColors.teal2 : AppColors.ink2),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith((s) =>
            s.contains(MaterialState.selected) ? Colors.white : const Color(0xFF7D8F95)),
        trackColor: MaterialStateProperty.resolveWith((s) =>
            s.contains(MaterialState.selected) ? AppColors.green : const Color(0xFFE3EAEC)),
        trackOutlineColor: MaterialStateProperty.resolveWith((s) =>
            s.contains(MaterialState.selected) ? AppColors.green : const Color(0xFF9AABB1)),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.teal,
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
        minVerticalPadding: 12,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1E3238),
        contentTextStyle: TextStyle(fontFamily: fontFamily, fontFamilyFallback: fontFamilyFallback, color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.teal),
      sliderTheme: base.sliderTheme.copyWith(activeTrackColor: AppColors.teal, thumbColor: AppColors.teal),
    );
  }
}
