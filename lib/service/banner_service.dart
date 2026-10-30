// 수정 일 : 2026-10-28 / 작업자 : 양태건
// 독립 배너 업로드와 기간 선택 API를 사용합니다.
import '../model/banner_model.dart';
import '../vm/login_notifier.dart';
import 'operations_api.dart';

class BannerService {
  BannerService(this.api);
  final OperationsApi api;
  Future<List<BannerImage>> list() async {
    final data = await api.request('/images/banner');
    return (data['results'] as List)
        .map(
          (row) => BannerImage.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<BannerImage> upload(
    String staffId,
    String name,
    List<int> bytes,
  ) async => BannerImage.fromJson(await api.uploadBanner(staffId, name, bytes));
  Future<void> choose(String staffId, int id, String start, String end) async {
    final data = await api.request(
      '/images/banner-select',
      json: {'h_id': staffId, 'b_seq': id, 'c_start': start, 'c_end': end},
    );
    if (data['c_image_seq'] is! num || data['c_boolean'] != true) {
      throw const OperationsApiException(
        502,
        '배너 적용 결과를 확인할 수 없습니다. 내역을 새로고침해 주세요.',
      );
    }
  }

  static String imageUrl(String path) =>
      Uri.parse('${LoginNotifier.baseUrl.replaceFirst(RegExp(r'/+$'), '')}/')
          .resolve(path)
          .toString();
}
// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건
