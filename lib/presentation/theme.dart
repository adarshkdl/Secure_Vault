import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'widgets/app_logo.dart';

/// Brand gradient (blue to violet) used for primary buttons, numbers and the
/// active navigation marker. Both ends keep >= 4:1 contrast with white text.
const brandGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF5B7CF5), Color(0xFF8F5BF0)],
);

const _bgDark = Color(0xFF0A0E1A);
const _glass = Color(0x12FFFFFF); // 7% white
const _glassBorder = Color(0x1FFFFFFF); // 12% white
const _textDark = Color(0xFFEAF0FF);
const _mutedDark = Color(0xFF9AA6C4);

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final base = ColorScheme.fromSeed(
    seedColor: const Color(0xFF3B6CF6),
    brightness: b,
  );
  final scheme = dark
      ? base.copyWith(
          primary: const Color(0xFF7C98FF),
          onPrimary: const Color(0xFF0A0E1A),
          secondary: const Color(0xFFA46BFF),
          surface: _bgDark,
          onSurface: _textDark,
          onSurfaceVariant: _mutedDark,
          surfaceContainerLowest: _bgDark,
          surfaceContainerLow: const Color(0xFF121829),
          surfaceContainer: const Color(0xFF151B2E),
          surfaceContainerHigh: const Color(0xFF1A2138),
          surfaceContainerHighest: const Color(0xFF212944),
          outline: _mutedDark,
          outlineVariant: const Color(0xFF2A3350),
          error: const Color(0xFFFF6B7A),
          errorContainer: const Color(0xFF4A1D27),
          onErrorContainer: const Color(0xFFFFD9DD),
        )
      : base.copyWith(
          primary: brandBlue,
          onPrimary: Colors.white,
          secondary: const Color(0xFF3949AB),
          surface: Colors.white,
          surfaceContainerLowest: const Color(0xFFEEF3FB),
          surfaceContainerLow: Colors.white,
          surfaceContainerHighest: const Color(0xFFE3EAF7),
          outlineVariant: const Color(0xFFDDE5F3),
        );
  final cardColor = dark ? _glass : Colors.white;
  final border = dark ? _glassBorder : const Color(0xFFE3E8F0);
  final radius = BorderRadius.circular(16);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? _bgDark : const Color(0xFFEEF3FB),
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: dark ? _bgDark : brandDeepBlue,
      foregroundColor: dark ? scheme.onSurface : Colors.white,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: dark ? scheme.onSurface : Colors.white,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: border),
      ),
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0x0FFFFFFF) : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    // Gradient fill; disabled buttons fade. White text on both gradient ends.
    filledButtonTheme: FilledButtonThemeData(
      style:
          FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            foregroundColor: Colors.white,
            backgroundColor: dark ? Colors.transparent : brandBlue,
            disabledBackgroundColor: dark ? Colors.transparent : null,
            shadowColor: Colors.transparent,
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ).copyWith(
            backgroundBuilder: (context, states, child) => !dark
                ? child!
                : Opacity(
                    opacity: states.contains(WidgetState.disabled) ? 0.4 : 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: brandGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: child,
                    ),
                  ),
          ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: dark
          ? const Color(0xF2121829)
          : Colors.white.withValues(alpha: 0.96),
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: dark ? 0.28 : 0.18),
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: dark ? const Color(0x1AFFFFFF) : null,
      side: BorderSide(color: border),
      shape: const StadiumBorder(),
    ),
    searchBarTheme: SearchBarThemeData(
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: WidgetStatePropertyAll(
        dark ? const Color(0x0FFFFFFF) : Colors.white,
      ),
      side: WidgetStatePropertyAll(BorderSide(color: border)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    dividerTheme: DividerThemeData(color: border),
  );
}

const categoryIcons = <String, IconData>{
  'email': Icons.email_outlined,
  'language': Icons.language,
  'lan': Icons.lan_outlined,
  'wifi': Icons.wifi,
  'dns': Icons.dns_outlined,
  'storage': Icons.storage,
  'cloud': Icons.cloud_outlined,
  'folder': Icons.folder_outlined,
  'key': Icons.vpn_key_outlined,
  'lock': Icons.lock_outline,
  'card': Icons.credit_card,
  'bank': Icons.account_balance_outlined,
  'phone': Icons.smartphone,
  'laptop': Icons.laptop,
  'work': Icons.work_outline,
  'shopping': Icons.shopping_bag_outlined,
  'game': Icons.sports_esports_outlined,
  'school': Icons.school_outlined,
  'health': Icons.favorite_border,
  'travel': Icons.flight_outlined,
};

const categoryColors = <String, Color>{
  'blue': Color(0xFF1E4DB7),
  'teal': Color(0xFF00796B),
  'indigo': Color(0xFF3949AB),
  'green': Color(0xFF2E7D32),
  'orange': Color(0xFFE65100),
  'purple': Color(0xFF6A1B9A),
  'red': Color(0xFFC62828),
  'pink': Color(0xFFAD1457),
  'brown': Color(0xFF4E342E),
  'grey': Color(0xFF455A64),
};

IconData iconFor(String key) => categoryIcons[key] ?? Icons.folder_outlined;
Color colorFor(String key) => categoryColors[key] ?? categoryColors['blue']!;
