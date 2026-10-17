import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ilot_peinture/demo_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Le mode demo recherche client et emplacement', () async {
    final demo = DemoStore();
    final files = await demo.request('GET', '/files?q=Métal', null) as List;
    expect(files.length, 1);
    expect(files.first['location'], 'Zone peinture / Chariot 2');
    final rack = await demo.request('GET', '/files?q=Rack%20C', null) as List;
    expect(rack.length, 1);
  });

  test('Le mouvement de stock est conservé et ne peut pas devenir négatif', () async {
    final demo = DemoStore();
    await demo.request('POST', '/products/1/movement', {'delta': -2.0, 'reason': 'Essai'});
    final products = await DemoStore().request('GET', '/products', null) as List;
    expect(products.first['quantity'], 16.5);
    final history = await demo.request('GET', '/products/1/history', null) as List;
    expect(history.length, 1);
    await expectLater(demo.request('POST', '/products/1/movement', {'delta': -999.0}), throwsException);
  });

  test('Le deplacement d un dossier est historise', () async {
    final demo = DemoStore();
    await demo.request('PUT', '/files/1', {'reference': 'DEMO-2026-041', 'client':'Ateliers Exemple', 'location':'Rack Z', 'status':'En attente', 'notes':''});
    final history = await demo.request('GET', '/files/1/history', null) as List;
    expect(history.single['new_location'], 'Rack Z');
  });
}
