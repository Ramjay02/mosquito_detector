import 'package:flutter_test/flutter_test.dart';
import 'package:mosquito_detector/src/constants.dart';

void main() {
  test('Ozamiz barangay list has 51 unique entries', () {
    expect(kOzamizBarangays, hasLength(51));
    expect(kOzamizBarangays.toSet(), hasLength(51));
  });
}
