import 'package:flutter_test/flutter_test.dart';
import 'package:bootcamp_project_gongin_admin_app/model/ground_model.dart';

void main() {
  test('numeric ground code from API can be used by list and detail', () {
    final ground = Ground.fromJson({
      'g_code': 1,
      'g_name': '테스트 구장',
      'g_address': '테스트 주소',
      'g_num': 20,
      'g_price': 10000,
      'g_information': '구장 안내',
      'g_lat': 37.5,
      'g_lng': 127,
    });
    expect(ground.g_code, '1');
    expect(ground.g_name, '테스트 구장');
    expect(ground.g_lng, 127.0);
    expect(ground.toJson()['g_code'], '1');
  });
  test('string ground codes remain supported', () {
    expect(Ground.fromJson({'g_code': 'G001'}).g_code, 'G001');
  });
}
