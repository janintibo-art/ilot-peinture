import 'package:flutter_test/flutter_test.dart';
import 'package:ilot_peinture/main.dart';
void main() {
  testWidgets('Shows initial navigation', (tester) async {
    await tester.pumpWidget(const IlotApp());
    expect(find.text('Stocks'), findsOneWidget);
    expect(find.text('Dossiers'), findsOneWidget);
  });
}
