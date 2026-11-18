import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:brr/features/auth/views/auth_gate.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AuthViewModel(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BRR',
      theme: AppTheme.theme,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('th'), Locale('en')],
      locale: const Locale('th'),
      home: const AuthGate(),
      // Scale UI density with screen width — design baseline is
      // ~390 logical px (typical phone). Text scales up on tablets /
      // down on small phones; clamped so extremes stay usable.
      // NOTE: multiplies the user's system font scale, not replaces it.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final scale = (mq.size.width / 390).clamp(0.85, 1.35).toDouble();
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(
              scale * mq.textScaler.scale(1),
            ),
          ),
          child: child!,
        );
      },
    );
  }
}
