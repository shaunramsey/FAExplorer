import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_gate.dart';
import 'auth/auth_service.dart';
import 'firebase_options.dart';

export 'automata_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  var firebaseEnabled = false;
  if (DefaultFirebaseOptions.isConfigured) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      firebaseEnabled = true;
    } catch (e) {
      debugPrint('Firebase initialization failed: $e');
    }
  }

  final authService = AuthService(firebaseEnabled: firebaseEnabled);

  runApp(MyApp(
    authService: authService,
    firebaseEnabled: firebaseEnabled,
  ));
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.authService,
    required this.firebaseEnabled,
  });

  final AuthService authService;
  final bool firebaseEnabled;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Automata Designer',
      theme: ThemeData(
        textTheme: GoogleFonts.courierPrimeTextTheme(),
        primaryTextTheme: GoogleFonts.courierPrimeTextTheme(),
      ),
      home: AppGate(
        authService: authService,
        firebaseEnabled: firebaseEnabled,
      ),
    );
  }
}
