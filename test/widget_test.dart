import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ilot_peinture/main.dart';

void main() {
  testWidgets('La navigation principale est visible', (tester) async {
    await tester.pumpWidget(const IlotApp());
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(3));
  });
}
