import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ilot_peinture/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Le serveur doit etre configure avant toute demande API', () async {
    SharedPreferences.setMockInitialValues({});
    final api = Api();
    await api.load();

    expect(api.url, isEmpty);
    expect(api.token, isEmpty);
    await expectLater(
      api.request('GET', '/products'),
      throwsA(isA<Exception>().having(
        (error) => error.toString(),
        'explication',
        contains('Configurez le serveur'),
      )),
    );
  });
}
