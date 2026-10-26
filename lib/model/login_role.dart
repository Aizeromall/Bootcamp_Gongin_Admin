// 작업자 : 최현준 / 작업 일 : 2026-10-24
enum LoginRole {
  // 작업자 : 양태건
  // 수정일 : 2026-10-26
  // 본사 직원은 headquarter 계정으로 인증합니다.
  headquarters('본사 직원', 'admin', 'h'),
  manager('매니저', 'manager', 'm');

  const LoginRole(this.label, this.path, this.fieldPrefix);
  final String label;
  final String path;
  final String fieldPrefix;
}
// 최종 수정일 : 2026-10-24
