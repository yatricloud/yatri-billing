import 'package:flutter_test/flutter_test.dart';
import 'package:invoiso/constants.dart';

void main() {
  test('AppConfig smoke test', () {
    expect(AppConfig.name, 'Yatri Billing');
    expect(AppConfig.version, isNotEmpty);
  });
}
