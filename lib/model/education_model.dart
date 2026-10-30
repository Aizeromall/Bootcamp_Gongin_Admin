// 수정 일 : 2026-10-27 / 작업자 : 양태건
// 기존 training 행을 묶어 반환하는 교육 API의 실제 응답 모델입니다.
int? educationInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value');
String? educationText(Object? value) =>
    value == null || '$value'.trim().isEmpty ? null : '$value';

class EducationManager {
  EducationManager.fromJson(Map<String, dynamic> json)
    : id = '${json['m_id']}',
      name =
          educationText(json['name']) ??
          educationText(json['m_name']) ??
          '${json['m_id']}',
      workplace =
          educationText(json['workplace']) ??
          educationText(json['m_workplace']),
      trainingId = educationInt(json['training_seq']),
      completed = json['completed'] is bool ? json['completed'] : null;
  final String id, name;
  final String? workplace;
  final int? trainingId;
  final bool? completed;
}

class EducationCourse {
  EducationCourse.fromJson(Map<String, dynamic> json)
    : id = '${json['course_id']}',
      title = educationText(json['title']) ?? '교육 기록',
      category = educationText(json['category']),
      format = educationText(json['format']),
      date = educationText(json['scheduled_at']) ?? educationText(json['date']),
      location = educationText(json['location']),
      instructor = educationText(json['instructor']),
      description = educationText(json['description']),
      duration = educationInt(json['duration_minutes']),
      completed = educationInt(json['completed_count']) ?? 0,
      total = educationInt(json['total']) ?? 0,
      managers = (json['managers'] as List? ?? [])
          .map(
            (m) =>
                EducationManager.fromJson(Map<String, dynamic>.from(m as Map)),
          )
          .toList();
  final String id, title;
  final String? category, format, date, location, instructor, description;
  final int? duration;
  final int completed, total;
  final List<EducationManager> managers;
}

class EducationCollection {
  EducationCollection.fromJson(Map<String, dynamic> json)
    : courses = (json['results'] as List? ?? [])
          .map(
            (v) =>
                EducationCourse.fromJson(Map<String, dynamic>.from(v as Map)),
          )
          .toList(),
      requiredPending = educationInt(json['required_pending']),
      total = educationInt(json['total']);
  final List<EducationCourse> courses;
  final int? requiredPending, total;
}

// 수정 일 : 2026-10-27 / 작업자 : 양태건
// 평가 원문에는 등급 계약이 없으므로 날짜와 내용만 변환합니다.
class EducationEvaluation {
  EducationEvaluation.fromJson(Map<String, dynamic> json)
    : date = educationText(json['e_date']),
      description = educationText(json['e_detail']);
  final String? date, description;
}
// 최종 수정 일 : 2026-10-27 / 작업자 : 양태건
