// 작업자 : 최현준 / 작업 일 : 2026-10-24
enum LoginRole {
  headquarters('본사 관리자', 'admin', 'h'),
  manager('매니저', 'manager', 'm');

  const LoginRole(this.label, this.path, this.fieldPrefix);
  final String label;
  final String path;
  final String fieldPrefix;
}
// 최종 수정일 : 2026-10-24
