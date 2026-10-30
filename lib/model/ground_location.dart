// 수정 일 : 2026-10-30 / 작업자 : 양태건
class GroundLocation {
  const GroundLocation(this.address, this.latitude, this.longitude);
  final String address;
  final double latitude, longitude;
  factory GroundLocation.fromJson(Map<String, dynamic> data) {
    final address = data['g_address'];
    final lat = (data['g_lat'] as num?)?.toDouble();
    final lng = (data['g_lng'] as num?)?.toDouble();
    if (address is! String ||
        address.trim().isEmpty ||
        lat == null ||
        lng == null ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat.abs() > 90 ||
        lng.abs() > 180) {
      throw const FormatException('Invalid location response');
    }
    return GroundLocation(address, lat, lng);
  }
}
// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
