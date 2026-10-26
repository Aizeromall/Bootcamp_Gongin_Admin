import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bootcamp_project_gongin_admin_app/model/login_role.dart';
import 'package:bootcamp_project_gongin_admin_app/vm/login_notifier.dart';

void main() {
  ProviderContainer containerFor(
    Set<LoginRole> accepted, {
    bool serverError = false,
  }) {
    final client = MockClient((request) async {
      final role = request.url.path == '/admin/login'
          ? LoginRole.headquarters
          : LoginRole.manager;
      if (serverError) return http.Response('{}', 503);
      if (!accepted.contains(role)) return http.Response('{}', 401);
      return http.Response(
        jsonEncode({
          'result': 'OK',
          '${role.fieldPrefix}_id': 'staff01',
          if (role == LoginRole.headquarters) ...{
            'role': 'headquarters',
            'h_name': 'HQ Staff',
          },
        }),
        200,
      );
    });
    final container = ProviderContainer(
      overrides: [loginClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    addTearDown(client.close);
    return container;
  }

  for (final role in LoginRole.values) {
    test(
      '${role.name} authentication sets only the authenticated role; logout clears it',
      () async {
        final container = containerFor({role});
        await container
            .read(loginProvider.notifier)
            .login('staff01', 'password');
        final session = container.read(loginProvider).requireValue!;
        expect(session.role, role);
        expect(session.userId, 'staff01');
        if (role == LoginRole.headquarters) expect(session.name, 'HQ Staff');
        container.read(loginProvider.notifier).reset();
        expect(container.read(loginProvider).requireValue, isNull);
      },
    );
  }
  test('invalid credentials do not create a session', () async {
    final container = containerFor({});
    await container.read(loginProvider.notifier).login('unknown', 'password');
    expect(container.read(loginProvider).hasError, isTrue);
    expect(container.read(loginProvider).asData, isNull);
  });
  test('ambiguous credentials do not grant headquarters access', () async {
    final container = containerFor(LoginRole.values.toSet());
    await container.read(loginProvider.notifier).login('staff01', 'password');
    expect(container.read(loginProvider).hasError, isTrue);
  });
  test('server errors do not create a session', () async {
    final container = containerFor({}, serverError: true);
    await container.read(loginProvider.notifier).login('staff01', 'password');
    expect(container.read(loginProvider).hasError, isTrue);
  });
}
