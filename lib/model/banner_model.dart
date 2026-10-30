// 수정 일 : 2026-10-28 / 작업자 : 양태건
// 공지와 연결된 첨부파일이 아닌 서버 배너 원본입니다.
class BannerImage {
  const BannerImage({
    required this.id,
    required this.url,
    required this.chosen,
  });
  final int id;
  final String url;
  final bool chosen;
  factory BannerImage.fromJson(Map<String, dynamic> json) => BannerImage(
    id: (json['b_seq'] as num).toInt(),
    url: json['image_url'] as String,
    chosen: json['is_chosen'] == true || json['is_chosen'] == 1,
  );
}
// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건
