import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:speedshare/MainScreen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

// window_size is a desktop-only package — import it conditionally
import 'package:window_size/window_size.dart' as window_size
    if (dart.library.html) 'package:speedshare/stubs/window_size_stub.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set responsive window size for desktop platforms only
  // window_size does NOT exist on Android/iOS — guard with Platform checks
  if (!kIsWeb &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    window_size.setWindowTitle('SpeedShare');
    window_size.setWindowMinSize(const Size(360, 640));
    window_size.setWindowMaxSize(const Size(1920, 1080));
    window_size.setWindowFrame(const Rect.fromLTWH(100, 100, 1024, 768));
  }

  // Load settings
  final prefs = await SharedPreferences.getInstance();
  final bool darkMode = prefs.getBool('darkMode') ?? false;

  runApp(MyApp(darkMode: darkMode));
}

class MyApp extends StatefulWidget {
  final bool darkMode;

  const MyApp({super.key, required this.darkMode});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late bool _darkMode;

  @override
  void initState() {
    super.initState();
    _darkMode = widget.darkMode;
    _listenForThemeChanges();
  }

  void _listenForThemeChanges() async {
    while (mounted) {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        final prefs = await SharedPreferences.getInstance();
        final newDarkMode = prefs.getBool('darkMode') ?? false;
        if (newDarkMode != _darkMode && mounted) {
          setState(() {
            _darkMode = newDarkMode;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SpeedShare',
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
      home: const ResponsiveWrapper(
        child: MainScreen(),
      ),
      debugShowCheckedModeBanner: false,
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF4E6AF3),
        primary: const Color(0xFF4E6AF3),
        secondary: const Color(0xFF2AB673),
        brightness: Brightness.light,
      ),
      fontFamily: 'Poppins',
      useMaterial3: true,
      cardTheme: _buildCardTheme(),
      elevatedButtonTheme: _buildElevatedButtonTheme(),
      outlinedButtonTheme: _buildOutlinedButtonTheme(),
      scaffoldBackgroundColor: Colors.grey[50],
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF4E6AF3),
        primary: const Color(0xFF4E6AF3),
        secondary: const Color(0xFF2AB673),
        brightness: Brightness.dark,
      ),
      fontFamily: 'Poppins',
      useMaterial3: true,
      cardTheme: _buildCardTheme(),
      elevatedButtonTheme: _buildElevatedButtonTheme(),
      outlinedButtonTheme: _buildOutlinedButtonTheme(),
      scaffoldBackgroundColor: const Color(0xFF121212),
    );
  }

  CardThemeData _buildCardTheme() {
    return CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }

  ElevatedButtonThemeData _buildElevatedButtonTheme() {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 2,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  OutlinedButtonThemeData _buildOutlinedButtonTheme() {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

// ─── Responsive System ───────────────────────────────────────────────────────

class ResponsiveWrapper extends StatelessWidget {
  final Widget child;

  const ResponsiveWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double mobileBreakpoint = 600;
        const double tabletBreakpoint = 1024;
        const double desktopBreakpoint = 1440;

        ScreenType screenType;
        if (constraints.maxWidth < mobileBreakpoint) {
          screenType = ScreenType.mobile;
        } else if (constraints.maxWidth < tabletBreakpoint) {
          screenType = ScreenType.tablet;
        } else if (constraints.maxWidth < desktopBreakpoint) {
          screenType = ScreenType.desktop;
        } else {
          screenType = ScreenType.largeDesktop;
        }

        return ResponsiveProvider(
          screenType: screenType,
          screenWidth: constraints.maxWidth,
          screenHeight: constraints.maxHeight,
          child: child,
        );
      },
    );
  }
}

enum ScreenType { mobile, tablet, desktop, largeDesktop }

class ResponsiveProvider extends InheritedWidget {
  final ScreenType screenType;
  final double screenWidth;
  final double screenHeight;

  const ResponsiveProvider({
    super.key,
    required this.screenType,
    required this.screenWidth,
    required this.screenHeight,
    required super.child,
  });

  static ResponsiveProvider? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ResponsiveProvider>();
  }

  @override
  bool updateShouldNotify(ResponsiveProvider oldWidget) {
    return screenType != oldWidget.screenType ||
        screenWidth != oldWidget.screenWidth ||
        screenHeight != oldWidget.screenHeight;
  }
}

extension ResponsiveContext on BuildContext {
  ResponsiveProvider get responsive => ResponsiveProvider.of(this)!;
  ScreenType get screenType => responsive.screenType;
  double get screenWidth => responsive.screenWidth;
  double get screenHeight => responsive.screenHeight;

  bool get isMobile => screenType == ScreenType.mobile;
  bool get isTablet => screenType == ScreenType.tablet;
  bool get isDesktop => screenType == ScreenType.desktop;
  bool get isLargeDesktop => screenType == ScreenType.largeDesktop;

  EdgeInsets get responsivePadding {
    switch (screenType) {
      case ScreenType.mobile:
        return const EdgeInsets.all(16);
      case ScreenType.tablet:
        return const EdgeInsets.all(24);
      case ScreenType.desktop:
        return const EdgeInsets.all(32);
      case ScreenType.largeDesktop:
        return const EdgeInsets.all(48);
    }
  }

  double get fontSizeMultiplier {
    switch (screenType) {
      case ScreenType.mobile:
        return 0.9;
      case ScreenType.tablet:
        return 1.0;
      case ScreenType.desktop:
        return 1.1;
      case ScreenType.largeDesktop:
        return 1.2;
    }
  }

  double get maxContentWidth {
    switch (screenType) {
      case ScreenType.mobile:
        return screenWidth;
      case ScreenType.tablet:
        return screenWidth * 0.9;
      case ScreenType.desktop:
        return 1200;
      case ScreenType.largeDesktop:
        return 1400;
    }
  }
}