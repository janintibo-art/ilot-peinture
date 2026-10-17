import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ilot_peinture/main.dart';

void main() {
  testWidgets('L application ouvre son ecran principal sans serveur', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const IlotApp());
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('🎨 ÎLOT PEINTURE'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
