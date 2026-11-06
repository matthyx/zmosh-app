import 'package:flutter/material.dart';
import 'ui/connect_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ZmoshApp());
}

class ZmoshApp extends StatelessWidget {
  const ZmoshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'zmosh',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.dark(
          primary: Colors.blueAccent,
          secondary: Colors.cyanAccent,
          surface: Colors.grey[900]!,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          foregroundColor: Colors.white,
        ),
      ),
      home: const ConnectScreen(),
    );
  }
}
