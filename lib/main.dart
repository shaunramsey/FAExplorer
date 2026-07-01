import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app_gate.dart';
import 'persistence.dart';
import 'widgets/app_theme.dart';

export 'automata_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final themeNotifier = await AppThemeNotifier.load();

  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: themeNotifier.bg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

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

  runApp(
    ChangeNotifierProvider<AppThemeNotifier>.value(
      value: themeNotifier,
      child: MyApp(
        authService: authService,
        firebaseEnabled: firebaseEnabled,
      ),
    ),
  );
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
    final themeNotifier = context.watch<AppThemeNotifier>();
    final c = themeNotifier.data;
    final light = c.isLightTheme;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: light ? Brightness.light : Brightness.dark,
      statusBarIconBrightness: light ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: c.bg,
      systemNavigationBarIconBrightness: light ? Brightness.dark : Brightness.light,
    ));
    return MaterialApp(
      title: 'Automata Designer',
      debugShowCheckedModeBanner: false,
      theme: buildMaterialTheme(c),
      home: AppGate(
        authService: authService,
        firebaseEnabled: firebaseEnabled,
      ),
    );
  }
}