// 작업자 : 최현준 / 작업 일 : 2026-10-24
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../service/operations_api.dart';

class RecordsView extends ConsumerWidget {
  const RecordsView({super.key, required this.path, required this.builder});
  final String path;
  final Widget Function(Map<String, dynamic>) builder;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(operationsDataProvider(path))
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 40),
                const SizedBox(height: 16),
                Text(
                  error.toString().replaceFirst('Exception: ', ''),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => ref.invalidate(operationsDataProvider(path)),
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          ),
        ),
        data: builder,
      );
}

class RecordDetails extends StatelessWidget {
  const RecordDetails({super.key, required this.record});
  final Map<String, dynamic> record;
  static const labels = {
    'c_id_seq': '회원 ID',
    'c_name': '회원 이름',
    'c_phone': '연락처',
    'c_gender': '성별',
    'c_birthday': '생년월일',
    'c_address': '주소',
    'c_prefer_stock': '선호 종목',
    'c_position': '포지션',
    'c_team': '소속팀',
    'c_signupdate': '가입일',
    'c_deletdate': '탈퇴일',
    'match_count': '참여 경기',
    'warning_count': '유효 경고',
    'received_report_count': '받은 신고',
    'sent_report_count': '보낸 신고',
    'm_id': '매니저 ID',
    'm_name': '매니저 이름',
    'm_phone': '연락처',
    'm_gender': '성별',
    'm_workplace': '근무지',
    'sanction_count': '제재 건수',
    'assigns': '구장 배정 이력',
    'evaluates': '평가 이력',
    'sanctions': '제재 이력',
    'hires': '채용 이력',
    'received_reports': '받은 신고 이력',
    'g_name': '구장명',
    'g_code': '구장 코드',
    'a_start': '배정 시작',
    'a_end': '배정 종료',
    'e_date': '평가일',
    'e_detail': '평가 내용',
    's_date': '제재일',
    's_detail': '제재 내용',
    'cs_date': '제재일',
    'cs_detail': '제재 내용',
    'h_date': '채용일',
    'r_reason': '신고 사유',
    'r_date': '일자',
    'state': '처리 상태',
    'status': '상태',
    'g_address': '주소',
    'g_num': '수용 인원',
    'g_price': '이용 금액',
    'g_information': '이용 정보',
  };
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: record.entries
        .where((entry) => !entry.key.endsWith('_pw'))
        .map(
          (entry) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: entry.value is List
                ? ExpansionTile(
                    title: Text(labels[entry.key] ?? entry.key),
                    children: (entry.value as List).isEmpty
                        ? [const ListTile(title: Text('이력이 없습니다.'))]
                        : (entry.value as List)
                              .whereType<Map>()
                              .map(
                                (item) => Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: RecordDetails(
                                    record: Map<String, dynamic>.from(item),
                                  ),
                                ),
                              )
                              .toList(),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 130,
                        child: Text(
                          labels[entry.key] ?? entry.key,
                          style: const TextStyle(color: Color(0xFF68756C)),
                        ),
                      ),
                      Expanded(child: Text('${entry.value ?? '—'}')),
                    ],
                  ),
          ),
        )
        .toList(),
  );
}
// 최종 수정일 : 2026-10-24
