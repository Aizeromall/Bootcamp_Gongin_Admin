import '../shared/async_screen_state.dart';

// 수정 일 : 2026-10-30 / 작업자 : 양태건
// 주소·좌표 입력 대신 지도 선택을 사용하며 좌표는 화면에 표시하지 않습니다.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../vm/ground_location_notifier.dart';
import '../../vm/headquarters_notifier.dart';

typedef GroundMapBuilder = Widget Function(
  void Function(double lat, double lng) onPicked,
);
// 네이티브 지도를 Mock 지도로 교체해 위치 선택 흐름을 검증할 수 있습니다.
final groundMapBuilderProvider = Provider<GroundMapBuilder>(
  (ref) =>
      (picked) => _NativeGroundMap(onPicked: picked),
);

class GroundLocationPicker extends ConsumerWidget {
  const GroundLocationPicker({super.key, required this.staffId});
  final String staffId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(groundLocationProvider(staffId));
    return FormField<void>(
      validator: (_) => location.isLoading
          ? '주소 확인이 끝날 때까지 기다려 주세요.'
          : location.asData?.value == null
          ? '지도에서 구장 위치를 선택해 주세요.'
          : null,
      builder: (field) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('지도를 움직여 구장 위치를 눌러 주세요.'),
          const SizedBox(height: 10),
          SizedBox(
            height: 320,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ref.watch(groundMapBuilderProvider)(
                (lat, lng) => ref
                    .read(groundLocationProvider(staffId).notifier)
                    .select(lat, lng),
              ),
            ),
          ),
          const SizedBox(height: 10),
          location.when(
            loading: () => const LinearProgressIndicator(),
            error: (error, _) => Text(
              adminError(error),
              style: const TextStyle(color: Colors.red),
            ),
            data: (value) => Text(
              value == null ? '아직 선택한 위치가 없습니다.' : '선택한 주소 · ${value.address}',
            ),
          ),
          if (field.hasError)
            Text(field.errorText!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _NativeGroundMap extends ConsumerStatefulWidget {
  const _NativeGroundMap({required this.onPicked});
  final void Function(double lat, double lng) onPicked;
  @override
  ConsumerState<_NativeGroundMap> createState() => _NativeGroundMapState();
}

class _NativeGroundMapState extends ConsumerState<_NativeGroundMap>
    with AsyncScreenState<_NativeGroundMap> {
  // 수정 일 : 2026-10-30 / 작업자 : 양태건
  // 화면별 AsyncNotifier로 선택·작성 상태를 분리합니다.
  @override
  Map<String, Object?> initialScreenValues() => {
    'ready': false,
    'error': null,
    'selection': 0,
  };
  @override
  Map<String, Object?> copyScreenValues(Map<String, Object?> values) => {
    ...values,
  };

  NaverMapController? controller;
  bool get ready => screenValue<bool>('ready');
  set ready(bool value) => setScreenValue('ready', value);
  String? get error => screenValue<String?>('error');
  set error(String? value) => setScreenValue('error', value);
  int get selection => screenValue<int>('selection');
  set selection(int value) => setScreenValue('selection', value);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) initialize();
    });
  }

  Future<void> initialize() async {
    const clientId = String.fromEnvironment('NAVER_MAP_CLIENT_ID');
    if (kIsWeb ||
        ![
          TargetPlatform.android,
          TargetPlatform.iOS,
        ].contains(defaultTargetPlatform)) {
      updateScreen(() => error = '지도 선택은 Android·iOS 앱에서 사용할 수 있습니다.');
      return;
    }
    if (clientId.isEmpty) {
      updateScreen(() => error = '지도 사용 설정이 필요합니다. 관리자에게 문의해 주세요.');
      return;
    }
    try {
      await FlutterNaverMap().init(
        clientId: clientId,
        onAuthFailed: (_) {
          if (mounted) {
            updateScreen(() {
              ready = false;
              error = '지도 인증을 확인하지 못했습니다. 관리자에게 문의해 주세요.';
            });
          }
        },
      );
      if (mounted && error == null) updateScreen(() => ready = true);
    } catch (_) {
      if (mounted) updateScreen(() => error = '지도를 불러오지 못했습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    watchScreen();
    if (error != null) {
      return Center(child: Text(error!, textAlign: TextAlign.center));
    }
    if (!ready) return const Center(child: CircularProgressIndicator());
    return NaverMap(
      options: const NaverMapViewOptions(
        initialCameraPosition: NCameraPosition(
          target: NLatLng(36.5, 127.8),
          zoom: 6,
        ),
        consumeSymbolTapEvents: false,
      ),
      onMapReady: (value) => controller = value,
      onMapTapped: (_, point) async {
        widget.onPicked(point.latitude, point.longitude);
        final request = ++selection;
        final map = controller;
        if (map == null) return;
        try {
          await map.clearOverlays(type: NOverlayType.marker);
          if (mounted && request == selection) {
            await map.addOverlay(
              NMarker(id: 'selected-ground', position: point),
            );
          }
        } catch (_) {
          /* 지도 폐기 시 마커 갱신을 중단합니다. 선택 주소 상태는 provider가 관리합니다. */
        }
      },
    );
  }
}
// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건

// 최종 수정 일 : 2026-10-30 / 작업자 : 양태건
