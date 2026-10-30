// 수정 일 : 2026-10-27 / 작업자 : 양태건
// 기존 양식·결재자·소유주·매니저 조회를 사용해 네 종류의 품의를 작성합니다.
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/headquarters_model.dart';
import '../../service/headquarters_service.dart';
import '../../vm/headquarters_notifier.dart';
import 'admin_components.dart';

class ApprovalWriter extends ConsumerStatefulWidget {
  const ApprovalWriter({super.key, required this.staffId});
  final String staffId;
  @override
  ConsumerState<ApprovalWriter> createState() => _ApprovalWriterState();
}

class _ApprovalWriterState extends ConsumerState<ApprovalWriter> {
  final form = GlobalKey<FormState>();
  final inputs = <String, TextEditingController>{};
  int? template, ground, contract, owner;
  String? kind, deputy;
  String ownerMode = '신규', sport = '축구';
  final approvers = <String, String>{};
  final photos = <String>[];
  final assignments = <AdminRow>[];
  bool picking = false;
  String? localError, success;
  TextEditingController control(String key) =>
      inputs.putIfAbsent(key, () => TextEditingController());
  @override
  void dispose() {
    for (final c in inputs.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mutation = ref.watch(adminMutationProvider(widget.staffId));
    final busy = mutation.isLoading || picking;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: AbsorbPointer(
        absorbing: busy,
        child: Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    adminTitle('품의서 작성'),
                    const SizedBox(height: 16),
                    AdminData(
                      staffId: widget.staffId,
                      path: '/approval/templates',
                      builder: (p) {
                        final templates = p.rows
                            .where((r) => approvalKind(r['m_content']) != null)
                            .toList();
                        return templates.isEmpty
                            ? const Text('사용 가능한 품의 양식이 없습니다.')
                            : DropdownButtonFormField<int>(
                                key: ValueKey('template:$template'),
                                initialValue: template,
                                decoration: const InputDecoration(
                                  labelText: '품의 양식',
                                ),
                                isExpanded: true,
                                items: [
                                  for (final r in templates)
                                    DropdownMenuItem(
                                      value: adminInt(r['m_code']),
                                      child: Text(
                                        '${approvalKind(r['m_content'])} · 양식 ${r['m_code']}',
                                      ),
                                    ),
                                ],
                                onChanged: (v) => setState(() {
                                  template = v;
                                  kind = approvalKind(
                                    templates.firstWhere(
                                      (r) => adminInt(r['m_code']) == v,
                                    )['m_content'],
                                  );
                                  approvers.clear();
                                  localError = null;
                                  success = null;
                                }),
                                validator: (v) =>
                                    v == null ? '양식을 선택해 주세요.' : null,
                              );
                      },
                    ),
                    const SizedBox(height: 12),
                    _field('reason', '품의 사유', max: 10000, lines: 3),
                  ],
                ),
              ),
              if (template != null) ...[
                AdminCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      adminTitle('결재선 · 사원 → 팀장 → 임원'),
                      const SizedBox(height: 16),
                      AdminData(
                        staffId: widget.staffId,
                        path: '/approval/approvers?m_code=$template',
                        builder: (p) => Column(
                          children: [
                            for (final position in ['사원', '팀장', '임원'])
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _options(
                                  '결재 $position',
                                  p.rows
                                      .where(
                                        (r) =>
                                            '${r['h_position']}'.trim() ==
                                            position,
                                      )
                                      .toList(),
                                  'h_id',
                                  'h_name',
                                  approvers[position],
                                  (v) =>
                                      setState(() => approvers[position] = v!),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (kind == '휴가')
                  AdminCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        adminTitle('휴가 일정'),
                        const SizedBox(height: 16),
                        _date('start', '시작일'),
                        _date('end', '종료일'),
                        AdminData(
                          staffId: widget.staffId,
                          path: adminPath('/approval/vacation/deputies', {
                            'h_id': widget.staffId,
                          }),
                          builder: (p) => _options(
                            '대리인',
                            p.rows,
                            'h_id',
                            'h_name',
                            deputy,
                            (v) => setState(() => deputy = v),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (kind == '재계약')
                  AdminCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        adminTitle('재계약 구장'),
                        const SizedBox(height: 16),
                        AdminData(
                          staffId: widget.staffId,
                          path: '/match/ground',
                          builder: (p) => _intOptions(
                            '구장',
                            p.rows,
                            'g_code',
                            'g_name',
                            ground,
                            (v) => setState(() => ground = v),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _field('treaty', '계약 조건', max: 10000, lines: 3),
                        _field('rental', '계약 대관료 (원)', number: true),
                      ],
                    ),
                  ),
                if (kind == '해지')
                  AdminCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        adminTitle('해지할 계약'),
                        const SizedBox(height: 16),
                        AdminData(
                          staffId: widget.staffId,
                          path: '/approval/contracts',
                          builder: (p) => _intOptions(
                            '계약',
                            p.rows,
                            'c_seq',
                            'c_treaty',
                            contract,
                            (v) => setState(() => contract = v),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (kind == '신규 계약') ..._newGround(),
                if (localError != null)
                  Text(localError!, style: const TextStyle(color: Colors.red)),
                if (mutation.hasError)
                  Text(
                    adminError(mutation.error!),
                    style: const TextStyle(color: Colors.red),
                  ),
                if (success != null)
                  Text(success!, style: const TextStyle(color: Colors.green)),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: busy ? null : _submit,
                    child: Text(busy ? '처리 중…' : '품의 상신'),
                  ),
                ),
              ],
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    String key,
    String label, {
    int max = 200,
    int lines = 1,
    bool number = false,
    bool optional = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: control(key),
      maxLength: max,
      minLines: lines,
      maxLines: lines,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(labelText: label),
      validator: (v) {
        if (optional && v!.trim().isEmpty) return null;
        if (v!.trim().isEmpty) return '$label 입력이 필요합니다.';
        if (number && (int.tryParse(v) == null || int.parse(v) < 0)) {
          return '0 이상의 정수를 입력해 주세요.';
        }
        return null;
      },
    ),
  );
  Widget _date(String key, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: control(key),
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.calendar_month),
      ),
      validator: (v) => v!.isEmpty ? '날짜를 선택해 주세요.' : null,
      onTap: () async {
        final now = DateTime.now();
        final d = await showDatePicker(
          context: context,
          initialDate: DateTime.tryParse(control(key).text) ?? now,
          firstDate: DateTime(now.year, now.month, now.day),
          lastDate: DateTime(now.year + 3),
          confirmText: '선택',
          cancelText: '취소',
        );
        if (d != null && mounted) {
          setState(
            () => control(key).text = d.toIso8601String().split('T').first,
          );
        }
      },
    ),
  );
  Widget _options(
    String label,
    List<AdminRow> rows,
    String id,
    String name,
    String? value,
    ValueChanged<String?> changed,
  ) => DropdownButtonFormField<String>(
    key: ValueKey('$template:$label'),
    initialValue: rows.any((r) => '${r[id]}' == value) ? value : null,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final r in rows)
        DropdownMenuItem(
          value: '${r[id]}',
          child: Text(
            '${adminText(r[name])} · ${adminText(r[id])}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: changed,
    validator: (v) => v == null ? '$label 선택이 필요합니다.' : null,
  );
  Widget _intOptions(
    String label,
    List<AdminRow> rows,
    String id,
    String name,
    int? value,
    ValueChanged<int?> changed,
  ) => DropdownButtonFormField<int>(
    key: ValueKey('$template:$label'),
    initialValue: rows.any((r) => adminInt(r[id]) == value) ? value : null,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final r in rows)
        DropdownMenuItem(
          value: adminInt(r[id]),
          child: Text(
            '${adminText(r[name])} · ${adminText(r[id])}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: changed,
    validator: (v) => v == null ? '$label 선택이 필요합니다.' : null,
  );
  List<Widget> _newGround() => [
    AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          adminTitle('소유주'),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: '신규', label: Text('신규 소유주')),
              ButtonSegment(value: '기존', label: Text('기존 소유주')),
            ],
            selected: {ownerMode},
            onSelectionChanged: (v) => setState(() => ownerMode = v.first),
          ),
          const SizedBox(height: 12),
          if (ownerMode == '신규') ...[
            _field('ownerName', '소유주 이름', max: 100),
            _field('ownerPhone', '연락처 (선택)', max: 20, optional: true),
          ] else
            AdminData(
              staffId: widget.staffId,
              path: '/approval/grounds/owners',
              builder: (p) => _intOptions(
                '소유주',
                p.rows,
                'o_seq',
                'o_name',
                owner,
                (v) => setState(() => owner = v),
              ),
            ),
        ],
      ),
    ),
    AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          adminTitle('구장 정보'),
          const SizedBox(height: 12),
          _field('groundName', '구장명', max: 100),
          DropdownButtonFormField<String>(
            initialValue: sport,
            decoration: const InputDecoration(labelText: '종목'),
            items: [
              for (final s in ['축구', '농구', '배구', '야구'])
                DropdownMenuItem(value: s, child: Text(s)),
            ],
            onChanged: (v) => setState(() => sport = v!),
          ),
          const SizedBox(height: 12),
          _field('address', '전체 주소', max: 255),
          _field('lat', '위도', max: 30),
          _field('lng', '경도', max: 30),
          _field('capacity', '수용 인원', number: true),
          _field('price', '이용 금액 (원)', number: true),
          _field('time', '운영 시간 (예: 09:00~22:00)', max: 100),
          _field('information', '구장 이용 정보', max: 10000, lines: 3),
          _field('treaty', '계약 조건', max: 10000, lines: 3),
          _field('rental', '계약 대관료 (원)', number: true),
        ],
      ),
    ),
    AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          adminTitle('구장 사진'),
          const SizedBox(height: 12),
          const Text('JPEG · PNG · WebP / 장당 10MB 이하, 최대 20장'),
          for (final name in photos)
            ListTile(
              title: Text('첨부 사진 ${photos.indexOf(name) + 1}'),
              trailing: IconButton(
                tooltip: '첨부 제외',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => photos.remove(name)),
              ),
            ),
          OutlinedButton.icon(
            onPressed: photos.length >= 20 ? null : _photo,
            icon: const Icon(Icons.attach_file),
            label: const Text('사진 첨부'),
          ),
        ],
      ),
    ),
    AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          adminTitle('매니저 근무 배정'),
          const SizedBox(height: 12),
          for (var i = 0; i < assignments.length; i++)
            ListTile(
              title: Text(
                '${assignments[i]['m_id']} · ${(assignments[i]['a_day'] as List).join('/')}',
              ),
              subtitle: Text(
                '${assignments[i]['a_period']} · ${assignments[i]['a_start']}~${assignments[i]['a_end']}',
              ),
              trailing: IconButton(
                tooltip: '배정 제외',
                onPressed: () => setState(() => assignments.removeAt(i)),
                icon: const Icon(Icons.close),
              ),
            ),
          AdminData(
            staffId: widget.staffId,
            path: '/approval/grounds/managers',
            builder: (p) => OutlinedButton(
              onPressed: assignments.length >= 50
                  ? null
                  : () async {
                      final value = await showDialog<AdminRow>(
                        context: context,
                        builder: (_) => _AssignmentDialog(managers: p.rows),
                      );
                      if (value != null && mounted) {
                        setState(() => assignments.add(value));
                      }
                    },
              child: const Text('+ 근무 배정'),
            ),
          ),
        ],
      ),
    ),
  ];
  Future<void> _photo() async {
    setState(() => picking = true);
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: '구장 사진',
            extensions: ['jpg', 'jpeg', 'png', 'webp'],
            uniformTypeIdentifiers: [
              'public.jpeg',
              'public.png',
              'org.webmproject.webp',
            ],
          ),
        ],
      );
      if (file == null || !mounted) return;
      if (await file.length() > 10 * 1024 * 1024) {
        if (mounted) setState(() => localError = '사진은 10MB 이하로 선택해 주세요.');
        return;
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final name = await ref
          .read(adminMutationProvider(widget.staffId).notifier)
          .upload(file.name, bytes);
      if (name != null && mounted) setState(() => photos.add(name));
    } catch (_) {
      if (mounted) setState(() => localError = '사진을 선택하지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> _submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      localError = null;
      success = null;
    });
    AdminRow data;
    switch (kind) {
      case '휴가':
        if (control('end').text.compareTo(control('start').text) < 0) {
          setState(() => localError = '종료일은 시작일 이후로 선택해 주세요.');
          return;
        }
        data = {
          'h_start': control('start').text,
          'h_end': control('end').text,
          'h_deputy': deputy,
        };
      case '재계약':
        data = {
          'g_code': ground,
          'c_treaty': control('treaty').text.trim(),
          'c_rentalfee': int.parse(control('rental').text),
        };
      case '해지':
        data = {'c_seq': contract};
      case '신규 계약':
        final lat = double.tryParse(control('lat').text),
            lng = double.tryParse(control('lng').text);
        if (lat == null ||
            !lat.isFinite ||
            lat.abs() > 90 ||
            lng == null ||
            !lng.isFinite ||
            lng.abs() > 180 ||
            int.parse(control('capacity').text) < 1 ||
            photos.isEmpty ||
            assignments.isEmpty) {
          setState(
            () => localError = '좌표·수용 인원을 확인하고 사진과 근무 배정을 하나 이상 추가해 주세요.',
          );
          return;
        }
        data = {
          'owner_mode': ownerMode,
          if (ownerMode == '기존')
            'o_seq': owner
          else ...{
            'o_name': control('ownerName').text.trim(),
            if (control('ownerPhone').text.trim().isNotEmpty)
              'o_phone': control('ownerPhone').text.trim(),
          },
          'g_name': control('groundName').text.trim(),
          'e_code': sport,
          'g_address': control('address').text.trim(),
          'g_lat': lat,
          'g_lng': lng,
          'g_num': int.parse(control('capacity').text),
          'g_price': int.parse(control('price').text),
          'g_information': control('information').text.trim(),
          'g_time': control('time').text.trim(),
          'c_treaty': control('treaty').text.trim(),
          'c_rentalfee': int.parse(control('rental').text),
          's_image': photos.toList(),
          'assignments': assignments.toList(),
        };
      default:
        return;
    }
    if (approvers.length != 3 || approvers.values.toSet().length != 3) {
      setState(() => localError = '서로 다른 사원·팀장·임원 결재자를 선택해 주세요.');
      return;
    }
    if (!await adminConfirm(context, '품의 상신', '작성한 품의서를 결재 요청할까요?')) return;
    if (!mounted) return;
    final saved = await ref
        .read(adminMutationProvider(widget.staffId).notifier)
        .save('/approval/requests', {
          'h_id': widget.staffId,
          'm_code': template,
          'a_reason': control('reason').text.trim(),
          'approver_ids': [
            for (final p in ['사원', '팀장', '임원']) approvers[p],
          ],
          'data': data,
        });
    if (saved && mounted) {
      setState(() {
        success = '품의서를 상신했습니다. 품의 내역에서 확인해 주세요.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(success!)));
        template = null;
        kind = null;
        approvers.clear();
        photos.clear();
        assignments.clear();
        for (final c in inputs.values) {
          c.clear();
        }
      });
    }
  }
}

class _AssignmentDialog extends StatefulWidget {
  const _AssignmentDialog({required this.managers});
  final List<AdminRow> managers;
  @override
  State<_AssignmentDialog> createState() => _AssignmentDialogState();
}

class _AssignmentDialogState extends State<_AssignmentDialog> {
  String? manager;
  String period = '오전';
  final days = <String>{};
  final start = TextEditingController(), end = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    start.dispose();
    end.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('매니저 근무 배정'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                isExpanded: true,
                decoration: const InputDecoration(labelText: '매니저'),
                items: [
                  for (final r in widget.managers)
                    DropdownMenuItem(
                      value: '${r['m_id']}',
                      child: Text('${r['m_name']} · ${r['m_id']}'),
                    ),
                ],
                onChanged: (v) => setState(() => manager = v),
                validator: (v) => v == null ? '매니저를 선택해 주세요.' : null,
              ),
              Wrap(
                children: [
                  for (final d in '월화수목금토일'.split(''))
                    FilterChip(
                      label: Text(d),
                      selected: days.contains(d),
                      onSelected: (s) =>
                          setState(() => s ? days.add(d) : days.remove(d)),
                    ),
                ],
              ),
              DropdownButton<String>(
                value: period,
                items: [
                  for (final p in ['오전', '오후'])
                    DropdownMenuItem(value: p, child: Text(p)),
                ],
                onChanged: (v) => setState(() => period = v!),
              ),
              TextFormField(
                controller: start,
                decoration: const InputDecoration(labelText: '시작 시간 (09:00)'),
                validator: (v) =>
                    RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(v ?? '')
                    ? null
                    : 'HH:mm 형식으로 입력해 주세요.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: end,
                decoration: const InputDecoration(labelText: '종료 시간 (12:00)'),
                validator: (v) =>
                    RegExp(r'^(([01]\d|2[0-3]):[0-5]\d|24:00)$')
                        .hasMatch(v ?? '')
                    ? null
                    : 'HH:mm 형식으로 입력해 주세요.',
              ),
              const SizedBox(height: 12),
              const Text('근무 중복과 운영 시간은 상신 시 서버에서 검증합니다.'),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate() && days.isNotEmpty) {
            Navigator.pop(context, {
              'm_id': manager,
              'a_day': days.toList(),
              'a_period': period,
              'a_start': start.text,
              'a_end': end.text,
            });
          }
        },
        child: const Text('배정 추가'),
      ),
    ],
  );
}
// 최종 수정 일 : 2026-10-27 / 작업자 : 양태건
