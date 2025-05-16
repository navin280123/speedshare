import 'package:flutter/material.dart';
import 'package:speedshare/MainScreen.dart';
import 'package:window_size/window_size.dart' as window_size;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set fixed window size for desktop platforms
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    window_size.setWindowTitle('SpeedShare');
    window_size.setWindowMinSize(const Size( 720, 720));
    window_size.setWindowMaxSize(const Size( 720, 720));
    window_size.setWindowFrame(Rect.fromLTWH(0, 0, 720, 720));

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
    
    // Listen for settings changes
    SharedPreferences.getInstance().then((prefs) {
      prefs.reload();
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SpeedShare',
      theme: ThemeData(
        brightness: _darkMode ? Brightness.dark : Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4E6AF3),
          primary: const Color(0xFF4E6AF3),
          secondary: const Color(0xFF2AB673),
          brightness: _darkMode ? Brightness.dark : Brightness.light,
        ),
        fontFamily: 'Poppins',
        useMaterial3: true,
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 2,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        scaffoldBackgroundColor: _darkMode ? const Color(0xFF121212) : Colors.grey[50],
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4E6AF3),
          primary: const Color(0xFF4E6AF3),
          secondary: const Color(0xFF2AB673),
          brightness: Brightness.dark,
        ),
        fontFamily: 'Poppins',
        useMaterial3: true,
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 2,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
      home: const MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}