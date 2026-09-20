import 'package:flutter/material.dart';

/// The Paytm-inspired palette: signature deep navy (#002970), Paytm cyan blue (#00BAF2),
/// vibrant verified green (#00B97A), and clean ice-blue surface (#F4F8FC).
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF002970); // Paytm Deep Navy
  static const Color primaryDark = Color(0xFF001A4A);
  static const Color accent = Color(0xFF00BAF2); // Paytm Cyan Blue
  static const Color danger = Color(0xFFEA4335);
  static const Color success = Color(0xFF00B97A); // Paytm Verified Green
  static const Color pending = Color(0xFF94A3B8);
  static const Color surface = Color(0xFFF4F8FC); // Paytm Soft Ice Blue
  static const Color card = Colors.white;
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.accent,
        error: AppColors.danger,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: AppColors.surface,
      fontFamily: 'Roboto',
    );
    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2EEF8), width: 1),
        ),
        margin: const EdgeInsets.symmetric(vertical: 6),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2EEF8)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2EEF8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Color(0xFF94A3B8),
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        elevation: 8,
      ),
    );
  }
}

/// Colour for a status pill, shared by application, exception and gap lists.
Color statusColor(String status) {
  switch (status) {
    case 'DRAFT':
      return AppColors.pending;
    case 'SUBMITTED':
    case 'UNDER_VERIFICATION':
    case 'OPEN':
    case 'PENDING_PUSH':
      return AppColors.accent;
    case 'DEFICIENCY':
    case 'MISMATCH':
    case 'HIGH':
      return AppColors.danger;
    case 'VERIFIED':
    case 'MATCH':
    case 'RESOLVED':
    case 'SENT':
      return AppColors.primary;
    case 'SANCTIONED':
    case 'DBT_PAID':
    case 'APPLIED':
    case 'CONFIRMED_OK':
      return AppColors.success;
    case 'REJECTED':
    case 'DISMISSED':
      return AppColors.danger;
    default:
      return AppColors.pending;
  }
}
