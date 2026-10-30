// 수정 일 : 2026-10-28 / 작업자 : 양태건
// 공지 작성 창 안에서 독립 배너 이미지를 업로드하고 노출 기간을 지정합니다.
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/banner_model.dart';
import '../../model/login_role.dart';
import '../../service/banner_service.dart';
import '../../vm/banner_notifier.dart';
import '../../vm/headquarters_notifier.dart';
import '../../vm/login_notifier.dart';
import '../shared/admin_style.dart';

class BannerEditor extends ConsumerStatefulWidget {
  const BannerEditor({super.key, required this.staffId, this.disabled = false});
  final String staffId;
  final bool disabled;
  @override
  ConsumerState<BannerEditor> createState() => _BannerEditorState();
}

class _BannerEditorState extends ConsumerState<BannerEditor> {
  BannerImage? selected;
  Uint8List? bytes;
  String? filename, message, error;
  DateTimeRange? period;
  bool picking = false;
  String date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  Future<void> pick() async {
    setState(() {
      picking = true;
      error = null;
      message = null;
    });
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: '배너 이미지',
            extensions: ['jpg', 'jpeg', 'png', 'webp'],
            uniformTypeIdentifiers: [
              'public.jpeg',
              'public.png',
              'org.webmproject.webp',
            ],
            mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
          ),
        ],
      );
      if (file == null) return;
      final length = await file.length();
      if (length == 0 || length > 10 * 1024 * 1024) {
        throw const FormatException('10MB 이하 이미지를 선택해 주세요.');
      }
      final content = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        bytes = content;
        filename = file.name;
        selected = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => error = '이미지를 선택하지 못했습니다. 10MB 이하 JPEG·PNG·WebP 파일을 확인해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Widget preview(ImageProvider image) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: Image(
      image: image,
      height: 140,
      width: double.infinity,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => const SizedBox(
        height: 80,
        child: Center(child: Text('이미지를 표시할 수 없습니다.')),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(loginProvider).asData?.value;
    final permitted =
        session?.userId == widget.staffId &&
        session?.role == LoginRole.headquarters &&
        session?.department?.trim() == '홍보팀';
    final mutation = ref.watch(bannerMutationProvider(widget.staffId));
    final busy = mutation.isLoading || widget.disabled || picking;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('배너 이미지', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text(
          '배너는 공지 첨부파일과 별도로 저장됩니다. 업로드 후 노출 기간을 지정하고 배너 적용을 눌러 주세요.',
          style: TextStyle(color: AdminStyle.muted, fontSize: 12),
        ),
        if (!permitted)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('배너 등록·선택은 홍보팀 직원만 가능합니다.'),
          ),
        if (permitted) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: busy ? null : pick,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(picking ? '이미지 읽는 중…' : '기기에서 이미지 선택'),
          ),
          if (bytes != null) ...[
            preview(MemoryImage(bytes!)),
            Text(filename!, maxLines: 1, overflow: TextOverflow.ellipsis),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      final image = await ref
                          .read(bannerMutationProvider(widget.staffId).notifier)
                          .upload(filename!, bytes!);
                      if (!mounted || image == null) return;
                      setState(() {
                        selected = image;
                        bytes = null;
                        filename = null;
                        error = null;
                        message = '이미지를 업로드했습니다. 기간을 정하고 배너를 적용해 주세요.';
                      });
                    },
              child: Text(mutation.isLoading ? '처리 중…' : '선택 이미지 업로드'),
            ),
          ],
        ],
        ref
            .watch(bannerListProvider(widget.staffId))
            .when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => Row(
                children: [
                  const Expanded(child: Text('배너 목록을 불러오지 못했습니다.')),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => ref.invalidate(
                            bannerListProvider(widget.staffId),
                          ),
                    child: const Text('다시 시도'),
                  ),
                ],
              ),
              data: (images) => images.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('등록된 배너 이미지가 없습니다.'),
                    )
                  : DropdownButtonFormField<int>(
                      key: ValueKey(
                        '${selected?.id}:${images.map((e) => e.id).join(',')}',
                      ),
                      initialValue:
                          images.any((image) => image.id == selected?.id)
                          ? selected?.id
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '등록된 배너 이미지 선택',
                      ),
                      items: [
                        for (final image in images)
                          DropdownMenuItem(
                            value: image.id,
                            child: Text(
                              '배너 ${image.id}${image.chosen ? ' · 현재 노출 중' : ''}',
                            ),
                          ),
                      ],
                      onChanged: !permitted || busy
                          ? null
                          : (id) => setState(() {
                              selected = images.firstWhere(
                                (image) => image.id == id,
                              );
                              bytes = null;
                              filename = null;
                              message = null;
                              error = null;
                            }),
                    ),
            ),
        if (selected != null) ...[
          const SizedBox(height: 10),
          preview(NetworkImage(BannerService.imageUrl(selected!.url))),
          if (permitted) ...[
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      final today = DateUtils.dateOnly(
                        DateTime.now().toUtc().add(const Duration(hours: 9)),
                      );
                      final value = await showDateRangePicker(
                        context: context,
                        firstDate: today,
                        lastDate: DateTime(today.year + 10, 12, 31),
                        initialDateRange:
                            period != null && !period!.start.isBefore(today)
                            ? period
                            : null,
                      );
                      if (!mounted || value == null) return;
                      setState(() {
                        period = value;
                        message = null;
                      });
                    },
              icon: const Icon(Icons.date_range),
              label: Text(
                period == null
                    ? '배너 노출 기간 선택'
                    : '${date(period!.start)} ~ ${date(period!.end)}',
              ),
            ),
            FilledButton(
              onPressed: busy || period == null
                  ? null
                  : () async {
                      final saved = await ref
                          .read(bannerMutationProvider(widget.staffId).notifier)
                          .choose(
                            selected!.id,
                            date(period!.start),
                            date(period!.end),
                          );
                      if (!mounted || !saved) return;
                      setState(() {
                        error = null;
                        message = '배너 노출 설정을 저장했습니다. 공지 등록과는 별도입니다.';
                      });
                    },
              child: Text(mutation.isLoading ? '처리 중…' : '배너 적용'),
            ),
          ],
        ],
        if (error != null)
          Text(error!, style: const TextStyle(color: AdminStyle.red)),
        if (mutation.hasError)
          Text(
            adminError(mutation.error!),
            style: const TextStyle(color: AdminStyle.red),
          ),
        if (message != null)
          Text(message!, style: const TextStyle(color: AdminStyle.blue)),
      ],
    );
  }
}
// 최종 수정 일 : 2026-10-28 / 작업자 : 양태건
