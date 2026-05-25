import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'automata_screen.dart';

export 'automata_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Automata Designer',
      theme: ThemeData(
        textTheme: GoogleFonts.courierPrimeTextTheme(),
        primaryTextTheme: GoogleFonts.courierPrimeTextTheme(),
      ),
      home: const AutomataScreen(),
    );
  }
}
