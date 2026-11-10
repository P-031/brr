import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:brr/main.dart';
import 'package:brr/features/auth/models/auth_session.dart';
import 'package:brr/features/auth/data/session_store.dart';
import 'package:brr/features/auth/viewmodels/auth_viewmodel.dart';

/// In-memory store — no platform channels.
class FakeSessionStore extends SessionStore {
  @override
  Future<void> save(AuthSession session) async {}

  @override
  Future<({String refreshToken, String? idToken})?> read() async => null;

  @override
  Future<void> clear() async {}
}

void main() {
  testWidgets('shows Keycloak login button', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthViewModel(sessionStore: FakeSessionStore()),
        child: const MyApp(),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('BRR'), findsOneWidget);
    expect(find.text('บัญชีผู้ใช้'), findsOneWidget);
    expect(find.text('รหัสผ่าน'), findsOneWidget);
    expect(find.text('เข้าสู่ระบบ'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
  });
}
