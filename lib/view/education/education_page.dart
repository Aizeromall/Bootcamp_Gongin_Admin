import '../shared/async_screen_state.dart';

// 수정 일 : 2026-10-27 / 작업자 : 양태건
// Figma 3:32의 교육 목록·상세·이수 현황을 실제 교육 API에 연결합니다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/education_model.dart';
import '../../vm/education_notifier.dart';
import '../shared/admin_style.dart';
import 'education_manager_context.dart';

String educationDate(String? text) {
  final date = DateTime.tryParse(text ?? '');
  if (date == null) return '일정 미기록';
  return '${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')} (${'월화수목금토일'[date.weekday - 1]})${text!.contains('T') ? ' ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}' : ''}';
}

String educationDuration(int? minutes) => minutes == null
    ? '시간 미기록'
    : minutes % 60 == 0
    ? '${minutes ~/ 60}시간'
    : '$minutes분';
Widget _pill(String text, {Color? ink, Color? fill}) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  decoration: BoxDecoration(
    color: fill ?? AdminStyle.canvas,
    borderRadius: BorderRadius.circular(11),
  ),
  child: Text(
    text,
    style: TextStyle(
      color: ink ?? AdminStyle.muted,
      fontSize: 11.5,
      fontWeight: FontWeight.bold,
    ),
  ),
);
Widget _category(String? category) => _pill(
  category ?? '교육',
  ink: category == '필수'
      ? AdminStyle.red
      : category == '재교육'
      ? const Color(0xFFB26A00)
      : AdminStyle.blue,
  fill: category == '필수'
      ? const Color(0xFFFDE8EB)
      : category == '재교육'
      ? const Color(0xFFFFF1DB)
      : AdminStyle.selected,
);
Widget _box({required Widget child}) => Container(
  margin: const EdgeInsets.only(bottom: 14),
  padding: const EdgeInsets.all(18),
  decoration: BoxDecoration(
    color: Colors.white,
    border: Border.all(color: AdminStyle.line),
    borderRadius: BorderRadius.circular(14),
  ),
  child: child,
);
Widget _error(Object error, VoidCallback retry) => Center(
  child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_outlined, color: AdminStyle.muted),
        const SizedBox(height: 12),
        Text(educationError(error), textAlign: TextAlign.center),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: retry, child: const Text('다시 시도')),
      ],
    ),
  ),
);

class EducationPage extends ConsumerStatefulWidget {
  const EducationPage({super.key, required this.staffId, this.onLogout});
  final String staffId;
  final VoidCallback? onLogout;
  @override
  ConsumerState<EducationPage> createState() => _EducationPageState();
}

class _EducationPageState extends ConsumerState<EducationPage>
    with AsyncScreenState<EducationPage> {
  // 수정 일 : 2026-10-30 / 작업자 : 양태건
  // 화면별 AsyncNotifier로 선택·작성 상태를 분리합니다.
  @override
  Map<String, Object?> initialScreenValues() => {'selected': null};
  @override
  Map<String, Object?> copyScreenValues(Map<String, Object?> values) => {
    ...values,
  };

  String? get selected => screenValue<String?>('selected');
  set selected(String? value) => setScreenValue('selected', value);
  Future<void> openCreate([String category = '필수', String? managerId]) async {
    final id = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EducationCreateDialog(
        staffId: widget.staffId,
        category: category,
        initialManagerId: managerId,
      ),
    );
    if (id != null && mounted) {
      updateScreen(() => selected = id);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('교육을 개설했습니다.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    watchScreen();
    final async = ref.watch(educationListProvider(widget.staffId));
    final value = async.asData?.value;
    return ColoredBox(
      color: AdminStyle.canvas,
      child: Column(
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 58),
            padding: const EdgeInsets.symmetric(horizontal: 22),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: AdminStyle.line)),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '매니저 교육',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: AdminStyle.ink,
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    '과정 ${value?.total ?? '—'}개 · 미이수 필수 ${value?.requiredPending ?? '—'}과정',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AdminStyle.muted,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '교육 새로고침',
                  onPressed: () =>
                      ref.invalidate(educationListProvider(widget.staffId)),
                  icon: const Icon(
                    Icons.refresh,
                    size: 18,
                    color: AdminStyle.muted,
                  ),
                ),
                if (MediaQuery.sizeOf(context).width < 760 &&
                    widget.onLogout != null)
                  IconButton(
                    tooltip: '로그아웃',
                    onPressed: widget.onLogout,
                    icon: const Icon(Icons.logout, size: 18),
                  ),
              ],
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _error(
                e,
                () => ref.invalidate(educationListProvider(widget.staffId)),
              ),
              data: (collection) => LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 860;
                  final course =
                      collection.courses
                          .where((c) => c.id == selected)
                          .firstOrNull ??
                      (wide ? collection.courses.firstOrNull : null);
                  final list = ColoredBox(
                    color: Colors.white,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: AdminStyle.line),
                            ),
                          ),
                          child: Row(
                            children: [
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AdminStyle.text,
                                  side: const BorderSide(
                                    color: AdminStyle.line,
                                  ),
                                  minimumSize: const Size(0, 35),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onPressed: () => openCreate(),
                                child: const Text(
                                  '+ 교육 개설',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Flexible(
                                child: Text(
                                  '필수 · 정기 · 재교육',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AdminStyle.muted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: collection.courses.isEmpty
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(20),
                                    child: Text(
                                      '등록된 교육이 없습니다.\n교육을 개설하고 대상 매니저를 배정해 주세요.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: AdminStyle.muted,
                                        height: 1.7,
                                      ),
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: collection.courses.length,
                                  separatorBuilder: (_, _) => const Divider(
                                    height: 1,
                                    color: AdminStyle.line,
                                  ),
                                  itemBuilder: (context, index) {
                                    final item = collection.courses[index];
                                    return Material(
                                      color: course?.id == item.id
                                          ? AdminStyle.selected
                                          : Colors.white,
                                      child: InkWell(
                                        onTap: () => updateScreen(
                                          () => selected = item.id,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            16,
                                            13,
                                            16,
                                            12,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  _category(item.category),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      '${item.format ?? '방식 미기록'} · ${educationDate(item.date)}',
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: AdminStyle.muted,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  _pill(
                                                    '${item.completed}/${item.total} 이수',
                                                    ink:
                                                        item.total > 0 &&
                                                            item.completed ==
                                                                item.total
                                                        ? const Color(
                                                            0xFF079447,
                                                          )
                                                        : null,
                                                    fill:
                                                        item.total > 0 &&
                                                            item.completed ==
                                                                item.total
                                                        ? const Color(
                                                            0xFFDEF7E9,
                                                          )
                                                        : null,
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                item.title,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 14.5,
                                                  color: AdminStyle.ink,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 5),
                                              Text(
                                                '${educationDuration(item.duration)} · ${item.location ?? '장소 미기록'}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 12.5,
                                                  color: AdminStyle.muted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  );
                  if (!wide && course == null) return list;
                  final detail = course == null
                      ? const Center(
                          child: Text(
                            '교육 과정을 선택해 주세요.',
                            style: TextStyle(color: AdminStyle.muted),
                          ),
                        )
                      : _EducationDetail(
                          key: ValueKey(course.id),
                          course: course,
                          staffId: widget.staffId,
                          onBack: wide
                              ? null
                              : () => updateScreen(() => selected = null),
                          onRetraining: () => openCreate('재교육'),
                          onManagerRetraining: (id) => openCreate('재교육', id),
                        );
                  return wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(width: 400, child: list),
                            const VerticalDivider(
                              width: 1,
                              color: AdminStyle.line,
                            ),
                            Expanded(child: detail),
                          ],
                        )
                      : detail;
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EducationDetail extends ConsumerWidget {
  const _EducationDetail({
    super.key,
    required this.course,
    required this.staffId,
    required this.onRetraining,
    required this.onManagerRetraining,
    this.onBack,
  });
  final EducationCourse course;
  final String staffId;
  final VoidCallback onRetraining;
  final ValueChanged<String> onManagerRetraining;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mutation = ref.watch(educationMutationProvider(staffId));
    return ListView(
      key: const ValueKey('education-detail-scroll'),
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
      children: [
        if (onBack != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
              label: const Text('교육 목록으로'),
            ),
          ),
        _box(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      course.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AdminStyle.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _category(course.category),
                ],
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final cells = [
                    _fact('일정', educationDate(course.date)),
                    _fact(
                      '방식',
                      '${course.format ?? '미기록'} ·\n${educationDuration(course.duration)}',
                    ),
                    _fact(
                      '장소 · 형태',
                      [
                        course.location,
                        course.instructor,
                      ].whereType<String>().join(' · '),
                    ),
                    _fact(
                      '이수율',
                      '${course.completed}/${course.total} (${course.total == 0 ? '—' : (course.completed * 100 / course.total).round()}%)',
                    ),
                  ];
                  return constraints.maxWidth >= 420
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < cells.length; i++) ...[
                              if (i > 0) const SizedBox(width: 10),
                              Expanded(child: cells[i]),
                            ],
                          ],
                        )
                      : Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final cell in cells)
                              SizedBox(
                                width: (constraints.maxWidth - 10) / 2,
                                child: cell,
                              ),
                          ],
                        );
                },
              ),
              if (course.description != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: AdminStyle.canvas,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    course.description!,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: AdminStyle.ink,
                      height: 1.7,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        _box(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                runSpacing: 8,
                children: [
                  const Text(
                    '대상 매니저 · 이수 현황',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AdminStyle.ink,
                    ),
                  ),
                  const Text(
                    '출석부 · 퀴즈 결과 확인 후 이수 처리',
                    style: TextStyle(fontSize: 12, color: AdminStyle.muted),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // 수정 일 : 2026-10-27 / 작업자 : 양태건
              // 넓은 화면의 표는 카드 폭을 채우고 작은 화면에서는 가로 스크롤합니다.
              LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: DataTable(
                      horizontalMargin: 8,
                      columnSpacing: 14,
                      headingRowHeight: 32,
                      dataRowMinHeight: 52,
                      dataRowMaxHeight: 64,
                      dividerThickness: 1,
                      border: const TableBorder(
                        horizontalInside: BorderSide(color: AdminStyle.line),
                      ),
                      headingTextStyle: const TextStyle(
                        fontFamily: 'IBM Plex Sans KR',
                        fontSize: 11.5,
                        color: AdminStyle.muted,
                      ),
                      dataTextStyle: const TextStyle(
                        fontFamily: 'IBM Plex Sans KR',
                        fontSize: 13,
                        color: Color(0xFF11151F),
                      ),
                      columns: const [
                        DataColumn(label: Text('매니저')),
                        DataColumn(label: Text('담당 종목')),
                        DataColumn(label: Text('평가 이력')),
                        DataColumn(label: Text('상태')),
                        DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final manager in course.managers)
                          DataRow(
                            cells: [
                              DataCell(
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      manager.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      manager.id,
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        color: AdminStyle.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              DataCell(
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 95,
                                  ),
                                  child: EducationAssignedSports(
                                    staffId: staffId,
                                    managerId: manager.id,
                                  ),
                                ),
                              ),
                              DataCell(
                                TextButton(
                                  key: ValueKey('evaluation:${manager.id}'),
                                  onPressed: () => showEducationEvaluations(
                                    context,
                                    staffId: staffId,
                                    manager: manager,
                                    onRetraining: () =>
                                        onManagerRetraining(manager.id),
                                  ),
                                  child: const Text(
                                    '기록 보기',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                              DataCell(
                                _pill(
                                  manager.completed == true
                                      ? '이수'
                                      : manager.completed == false
                                      ? '미이수'
                                      : '미확인',
                                  ink: manager.completed == true
                                      ? const Color(0xFF079447)
                                      : AdminStyle.red,
                                  fill: manager.completed == true
                                      ? const Color(0xFFDEF7E9)
                                      : const Color(0xFFFDE8EB),
                                ),
                              ),
                              DataCell(
                                manager.completed == true
                                    ? const Icon(
                                        Icons.check_circle_outline,
                                        color: Color(0xFF079447),
                                        size: 18,
                                      )
                                    : FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: AdminStyle.ink,
                                          foregroundColor: Colors.white,
                                          minimumSize: const Size(72, 33),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                        ),
                                        onPressed:
                                            mutation.isLoading ||
                                                manager.trainingId == null
                                            ? null
                                            : () async {
                                                final confirm = await showDialog<bool>(
                                                  context: context,
                                                  builder: (context) => AlertDialog(
                                                    title: const Text('이수 처리'),
                                                    content: Text(
                                                      '${manager.name} 매니저의 출석부 또는 퀴즈 결과를 확인했나요?',
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                              context,
                                                              false,
                                                            ),
                                                        child: const Text('취소'),
                                                      ),
                                                      FilledButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                              context,
                                                              true,
                                                            ),
                                                        child: const Text(
                                                          '이수 확정',
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                                if (confirm != true ||
                                                    !context.mounted) {
                                                  return;
                                                }
                                                final success = await ref
                                                    .read(
                                                      educationMutationProvider(
                                                        staffId,
                                                      ).notifier,
                                                    )
                                                    .complete(
                                                      manager.trainingId!,
                                                    );
                                                if (success &&
                                                    context.mounted) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            '이수 처리를 완료했습니다.',
                                                          ),
                                                        ),
                                                      );
                                                }
                                              },
                                        child: const Text(
                                          '이수 처리',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (mutation.isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
              if (mutation.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    educationError(mutation.error!),
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
        _box(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '재교육 배정',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AdminStyle.ink,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '재교육이 필요한 매니저에게 과정을 개설해 배정할 수 있습니다.',
                style: TextStyle(
                  fontSize: 12,
                  color: AdminStyle.muted,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final manager in course.managers)
                    ActionChip(
                      key: ValueKey('retraining:${manager.id}'),
                      label: Text('${manager.name} 배정'),
                      onPressed: mutation.isLoading
                          ? null
                          : () => onManagerRetraining(manager.id),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: mutation.isLoading ? null : onRetraining,
                  child: const Text('재교육 개설'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Widget _fact(String label, String value) => Container(
  constraints: const BoxConstraints(minHeight: 100),
  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
  decoration: BoxDecoration(
    color: AdminStyle.canvas,
    borderRadius: BorderRadius.circular(10),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 11.5, color: AdminStyle.muted),
      ),
      const SizedBox(height: 6),
      Text(
        value.isEmpty ? '미기록' : value,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: AdminStyle.ink,
          height: 1.5,
        ),
      ),
    ],
  ),
);

class EducationCreateDialog extends ConsumerStatefulWidget {
  const EducationCreateDialog({
    super.key,
    required this.staffId,
    required this.category,
    this.initialManagerId,
  });
  final String staffId, category;
  final String? initialManagerId;
  @override
  ConsumerState<EducationCreateDialog> createState() =>
      _EducationCreateDialogState();
}

class _EducationCreateDialogState extends ConsumerState<EducationCreateDialog>
    with AsyncScreenState<EducationCreateDialog> {
  // 수정 일 : 2026-10-30 / 작업자 : 양태건
  // 화면별 AsyncNotifier로 선택·작성 상태를 분리합니다.
  @override
  Map<String, Object?> initialScreenValues() => {
    'category': widget.category,
    'format': '오프라인',
    'scheduled': null,
    'managerIds': <String>{
      if (widget.initialManagerId != null) widget.initialManagerId!,
    },
    'validation': null,
  };
  @override
  Map<String, Object?> copyScreenValues(Map<String, Object?> values) => {
    ...values,
    'managerIds': Set<String>.from(values['managerIds'] as Set),
  };

  final form = GlobalKey<FormState>();
  late final title = screenTextController('title'),
      location = screenTextController('location'),
      instructor = screenTextController('instructor'),
      description = screenTextController('description'),
      duration = screenTextController('duration', text: '60');
  String get category => screenValue<String>('category');
  set category(String value) => setScreenValue('category', value);
  String get format => screenValue<String>('format');
  set format(String value) => setScreenValue('format', value);
  DateTime? get scheduled => screenValue<DateTime?>('scheduled');
  set scheduled(DateTime? value) => setScreenValue('scheduled', value);
  Set<String> get managerIds => screenValue<Set<String>>('managerIds');
  set managerIds(Set<String> value) => setScreenValue('managerIds', value);

  String? get validation => screenValue<String?>('validation');
  set validation(String? value) => setScreenValue('validation', value);
  @override
  void dispose() {
    for (final c in [title, location, instructor, description, duration]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    watchScreen();
    final managers = ref.watch(educationManagersProvider(widget.staffId));
    final mutation = ref.watch(educationMutationProvider(widget.staffId));
    return PopScope(
      canPop: !mutation.isLoading,
      child: AlertDialog(
        title: const Text('교육 개설'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: title,
                    maxLength: 200,
                    enabled: !mutation.isLoading,
                    decoration: const InputDecoration(labelText: '교육 제목'),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? '교육 제목을 입력해 주세요.' : null,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: '교육 구분'),
                    items: [
                      for (final item in ['필수', '정기', '재교육'])
                        DropdownMenuItem(value: item, child: Text(item)),
                    ],
                    onChanged: mutation.isLoading
                        ? null
                        : (v) => updateScreen(() => category = v!),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: format,
                    decoration: const InputDecoration(labelText: '교육 방식'),
                    items: [
                      for (final item in ['오프라인', '온라인'])
                        DropdownMenuItem(value: item, child: Text(item)),
                    ],
                    onChanged: mutation.isLoading
                        ? null
                        : (v) => updateScreen(() => format = v!),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: mutation.isLoading
                        ? null
                        : () async {
                            final now = DateTime.now();
                            final date = await showDatePicker(
                              context: context,
                              initialDate: scheduled ?? now,
                              confirmText: '선택',
                              cancelText: '취소',
                              helpText: '교육 날짜 선택',
                              firstDate: DateTime(2020),
                              lastDate: DateTime(now.year + 5),
                            );
                            if (date == null || !context.mounted) return;
                            final time = await showTimePicker(
                              context: context,
                              confirmText: '선택',
                              cancelText: '취소',
                              helpText: '교육 시간 선택',
                              initialTime: scheduled == null
                                  ? const TimeOfDay(hour: 14, minute: 0)
                                  : TimeOfDay.fromDateTime(scheduled!),
                            );
                            if (time != null && mounted) {
                              updateScreen(
                                () => scheduled = DateTime(
                                  date.year,
                                  date.month,
                                  date.day,
                                  time.hour,
                                  time.minute,
                                ),
                              );
                            }
                          },
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(
                      scheduled == null
                          ? '교육 일정 선택'
                          : educationDate(scheduled!.toIso8601String()),
                    ),
                  ),
                  TextFormField(
                    controller: duration,
                    enabled: !mutation.isLoading,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '교육 시간 (분)'),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return n == null || n < 15 || n > 1440
                          ? '15~1440분으로 입력해 주세요.'
                          : null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: location,
                    enabled: !mutation.isLoading,
                    maxLength: 200,
                    decoration: InputDecoration(
                      labelText: format == '온라인' ? '온라인 교육 주소·안내' : '교육 장소',
                    ),
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? '교육 장소 또는 안내를 입력해 주세요.'
                        : null,
                  ),
                  TextFormField(
                    controller: instructor,
                    enabled: !mutation.isLoading,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: '강사·교육 형태 (선택)',
                    ),
                  ),
                  TextFormField(
                    controller: description,
                    enabled: !mutation.isLoading,
                    maxLines: 3,
                    maxLength: 8000,
                    decoration: const InputDecoration(labelText: '교육 안내 (선택)'),
                  ),
                  const Text(
                    '대상 매니저',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: mutation.isLoading
                          ? null
                          : () => updateScreen(() => managerIds.clear()),
                      child: const Text('대상 선택 초기화'),
                    ),
                  ),
                  managers.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                    error: (e, _) => Column(
                      children: [
                        Text(educationError(e)),
                        TextButton(
                          onPressed: () => ref.invalidate(
                            educationManagersProvider(widget.staffId),
                          ),
                          child: const Text('대상 다시 불러오기'),
                        ),
                      ],
                    ),
                    data: (items) => items.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('배정 가능한 매니저가 없습니다.'),
                          )
                        : Column(
                            children: [
                              for (final m in items)
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(m.name),
                                  subtitle: Text(m.workplace ?? m.id),
                                  value: managerIds.contains(m.id),
                                  onChanged: mutation.isLoading
                                      ? null
                                      : (v) => updateScreen(() {
                                          if (v == true) {
                                            managerIds.add(m.id);
                                          } else {
                                            managerIds.remove(m.id);
                                          }
                                        }),
                                ),
                            ],
                          ),
                  ),
                  if (validation != null)
                    Text(
                      validation!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  if (mutation.hasError)
                    Text(
                      educationError(mutation.error!),
                      style: const TextStyle(color: Colors.red),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: mutation.isLoading ? null : () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: mutation.isLoading
                ? null
                : () async {
                    if (!form.currentState!.validate()) return;
                    if (scheduled == null || managerIds.isEmpty) {
                      updateScreen(
                        () => validation = '교육 일정과 대상 매니저를 선택해 주세요.',
                      );
                      return;
                    }
                    // 수정 일 : 2026-10-27 / 작업자 : 양태건
                    // 과거 교육 대상이 현재 배정 가능한 명단에서 제외됐으면 저장을 막습니다.
                    final allowed = ref
                        .read(educationManagersProvider(widget.staffId))
                        .asData
                        ?.value
                        .map((m) => m.id)
                        .toSet();
                    if (allowed == null ||
                        managerIds.any((id) => !allowed.contains(id))) {
                      updateScreen(
                        () => validation =
                            '현재 배정 가능한 매니저만 선택해 주세요. 선택을 초기화한 뒤 다시 선택할 수 있습니다.',
                      );
                      return;
                    }
                    updateScreen(() => validation = null);
                    final success = await ref
                        .read(
                          educationMutationProvider(widget.staffId).notifier,
                        )
                        .create({
                          'title': title.text.trim(),
                          'category': category,
                          'format': format,
                          'scheduled_at': scheduled!.toIso8601String(),
                          'duration_minutes': int.parse(duration.text),
                          'location': location.text.trim(),
                          'instructor': instructor.text.trim(),
                          'description': description.text.trim(),
                          'manager_ids': managerIds.toList(),
                        });
                    if (success && context.mounted) {
                      Navigator.pop(
                        context,
                        ref
                            .read(educationMutationProvider(widget.staffId))
                            .value,
                      );
                    }
                  },
            child: Text(mutation.isLoading ? '개설 중…' : '교육 개설'),
          ),
        ],
      ),
    );
  }
}
// 최종 수정 일 : 2026-10-27 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
