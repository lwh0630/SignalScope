import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_application/app.dart';
import 'package:flutter_application/core/providers.dart';
import 'package:flutter_application/data/platform/unsupported_platform.dart';
import 'package:flutter_application/features/latency/application/latency_controller.dart';
import 'package:flutter_application/features/latency/data/latency_probe.dart';
import 'package:flutter_application/features/latency/data/latency_targets.dart';
import 'package:flutter_application/features/settings/domain/app_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deterministic probe: results come from a table, nothing touches the network.
class FakeProbe implements LatencyProbe {
  FakeProbe(this.table);

  final Map<String, LatencyMeasurement> table;
  final List<String> measured = [];
  int active = 0;
  int maxActive = 0;

  @override
  Future<LatencyMeasurement> measure(
    LatencyTarget target, {
    required int samples,
    required Duration timeout,
    required bool Function() isCancelled,
  }) async {
    measured.add(target.host);
    active++;
    if (active > maxActive) maxActive = active;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    active--;
    return table[target.host] ??
        const LatencyMeasurement(dnsMs: 5, tcpMs: [20, 22, 24, 26]);
  }
}

void main() {
  group('LatencyStats', () {
    test('min / avg / max / jitter / loss from successful attempts only', () {
      final s = LatencyStats.fromSamples([10, 20, null, 40], dnsMs: 3);
      expect(s.sent, 4);
      expect(s.received, 3);
      expect(s.minMs, 10);
      expect(s.maxMs, 40);
      expect(s.avgMs, closeTo(70 / 3, 1e-9));
      expect(s.jitterMs, closeTo(((20 - 10) + (40 - 20)) / 2, 1e-9));
      expect(s.lossPercent, 25);
      expect(s.dnsMs, 3);
      expect(s.reachable, isTrue);
    });

    test('a lost attempt is never counted as 0 ms', () {
      final s = LatencyStats.fromSamples([null, 50, null, null]);
      expect(s.minMs, 50);
      expect(s.avgMs, 50);
      expect(s.jitterMs, isNull); // needs two successes
      expect(s.lossPercent, 75);
    });

    test('all lost -> unreachable with no numbers', () {
      final s = LatencyStats.fromSamples([null, null, null, null]);
      expect(s.reachable, isFalse);
      expect(s.avgMs, isNull);
      expect(s.minMs, isNull);
      expect(s.lossPercent, 100);
    });
  });

  group('SocketLatencyProbe (loopback)', () {
    test('times real TCP handshakes against a local server; closed port is lost, never 0', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((s) => s.destroy());
      const probe = SocketLatencyProbe();

      final ok = await probe.measure(
        LatencyTarget(
          id: 'x',
          name: 'local',
          host: '127.0.0.1',
          port: server.port,
          group: LatencyGroup.custom,
        ),
        samples: 3,
        timeout: const Duration(seconds: 2),
        isCancelled: () => false,
      );
      expect(ok.dnsFailed, isFalse);
      expect(ok.dnsMs, isNull); // IP literal: no DNS step
      expect(ok.tcpMs.length, 3);
      expect(ok.tcpMs.every((v) => v != null && v >= 0 && v < 2000), isTrue);

      final closedPort = server.port;
      await server.close();
      final lost = await probe.measure(
        LatencyTarget(
          id: 'y',
          name: 'closed',
          host: '127.0.0.1',
          port: closedPort,
          group: LatencyGroup.custom,
        ),
        samples: 2,
        timeout: const Duration(seconds: 1),
        isCancelled: () => false,
      );
      expect(lost.tcpMs, [null, null]);
      expect(LatencyStats.fromSamples(lost.tcpMs).reachable, isFalse);
    });

    test('an unresolvable name is reported as a DNS failure', () async {
      const probe = SocketLatencyProbe();
      final m = await probe.measure(
        const LatencyTarget(
          id: 'z',
          name: 'bad',
          host: 'nonexistent.invalid',
          group: LatencyGroup.custom,
        ),
        samples: 2,
        timeout: const Duration(seconds: 3),
        isCancelled: () => false,
      );
      expect(m.dnsFailed, isTrue);
      expect(m.tcpMs, isEmpty);
    });

    test('cancellation stops further attempts', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((s) => s.destroy());
      var calls = 0;
      final m = await const SocketLatencyProbe().measure(
        LatencyTarget(
          id: 'x',
          name: 'local',
          host: '127.0.0.1',
          port: server.port,
          group: LatencyGroup.custom,
        ),
        samples: 5,
        timeout: const Duration(seconds: 2),
        isCancelled: () => ++calls > 2,
      );
      expect(m.tcpMs.length, 2);
    });
  });

  group('LatencyGrade', () {
    test('thresholds are 50 / 100 / 200 ms', () {
      expect(LatencyGrade.of(10), LatencyGrade.excellent);
      expect(LatencyGrade.of(49.9), LatencyGrade.excellent);
      expect(LatencyGrade.of(50), LatencyGrade.good);
      expect(LatencyGrade.of(99), LatencyGrade.good);
      expect(LatencyGrade.of(100), LatencyGrade.fair);
      expect(LatencyGrade.of(200), LatencyGrade.poor);
    });
  });

  group('custom address parsing', () {
    test('accepts hosts, ports, URLs and IPs', () {
      final a = LatencyTarget.parseCustom('Example.COM')!;
      expect((a.host, a.port), ('example.com', 443));
      expect(a.group, LatencyGroup.custom);
      expect(a.id, 'custom:example.com:443');

      final b = LatencyTarget.parseCustom('example.com:8443')!;
      expect(b.port, 8443);
      expect(b.displayAddress, 'example.com:8443');

      expect(
        LatencyTarget.parseCustom('https://www.example.com/some/path?q=1')!
            .host,
        'www.example.com',
      );
      expect(LatencyTarget.parseCustom('http://example.com')!.port, 80);
      expect(
        LatencyTarget.parseCustom('http://example.com:8080/x')!.port,
        8080,
      );
      expect(LatencyTarget.parseCustom('1.1.1.1')!.host, '1.1.1.1');
      expect(LatencyTarget.parseCustom('1.1.1.1:53')!.port, 53);

      final v6 = LatencyTarget.parseCustom('[2606:4700:4700::1111]:443')!;
      expect(v6.host, '2606:4700:4700::1111');
      expect(v6.storageKey, '[2606:4700:4700::1111]:443');
      // The stored form parses back to the same target.
      expect(LatencyTarget.parseCustom(v6.storageKey)!.id, v6.id);
    });

    test('rejects nonsense', () {
      for (final bad in [
        '',
        '   ',
        'not a host',
        'localhost-only',
        'ftp://example.com',
        'example.com:0',
        'example.com:99999',
        'exa mple.com',
        '://x',
        'a..b',
      ]) {
        expect(LatencyTarget.parseCustom(bad), isNull, reason: bad);
      }
    });

    test('built-in lists are split into mainland and international', () {
      expect(
        LatencyTarget.mainland.every((t) => t.group == LatencyGroup.mainland),
        isTrue,
      );
      expect(
        LatencyTarget.international.every(
          (t) => t.group == LatencyGroup.international,
        ),
        isTrue,
      );
      expect(
        LatencyTarget.mainland.map((t) => t.host),
        contains('www.baidu.com'),
      );
      expect(
        LatencyTarget.international.map((t) => t.host),
        contains('www.google.com'),
      );
      final ids = LatencyTarget.builtIn.map((t) => t.id).toSet();
      expect(ids.length, LatencyTarget.builtIn.length);
    });
  });

  group('AppSettings custom targets', () {
    test('round trip and tolerant loading', () {
      const s = AppSettings(customLatencyTargets: ['a.com:443', 'b.org:8080']);
      expect(AppSettings.fromJson(s.toJson()).customLatencyTargets, [
        'a.com:443',
        'b.org:8080',
      ]);
      expect(
        AppSettings.fromJson('{"themeMode":"dark"}').customLatencyTargets,
        isEmpty,
      );
      expect(
        AppSettings.fromJson('{"customLatencyTargets":[1,"x.com:443",""]}')
            .customLatencyTargets,
        ['x.com:443'],
      );
    });
  });

  group('LatencyController', () {
    ProviderContainer make(
      FakeProbe probe, {
      AppSettings settings = const AppSettings(),
    }) {
      final c = ProviderContainer(
        overrides: [
          latencyProbeProvider.overrideWithValue(probe),
          initialSettingsProvider.overrideWithValue(settings),
          realPlatformProvider.overrideWithValue(UnsupportedPlatform('test')),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test(
      'tests every target with limited concurrency and reports results',
      () async {
        final probe = FakeProbe({
          'www.baidu.com': const LatencyMeasurement(
            dnsMs: 4,
            tcpMs: [30, 32, 34, 36],
          ),
          'www.google.com': const LatencyMeasurement(
            dnsMs: 4,
            tcpMs: [null, null, null, null],
          ),
          'github.com': const LatencyMeasurement(dnsFailed: true),
        });
        final c = make(probe);
        c.listen(latencyControllerProvider, (_, _) {});
        final ctl = c.read(latencyControllerProvider.notifier);
        await ctl.testAll();

        final s = c.read(latencyControllerProvider);
        expect(s.running, isFalse);
        expect(s.finished, LatencyTarget.builtIn.length);
        expect(probe.measured.toSet().length, LatencyTarget.builtIn.length);
        expect(
          probe.maxActive,
          lessThanOrEqualTo(LatencyController.concurrency),
        );

        final baidu = s.resultOf('cn-baidu');
        expect(baidu.status, TargetStatus.done);
        expect(baidu.stats!.avgMs, 33);
        expect(s.resultOf('us-google').status, TargetStatus.failed);
        expect(s.resultOf('us-google').failure, FailureKind.unreachable);
        expect(s.resultOf('us-github').failure, FailureKind.dns);
        expect(s.groupAverage(LatencyTarget.mainland), isNotNull);
      },
    );

    test('stop cancels the run and clears in-flight entries', () async {
      final probe = FakeProbe({});
      final c = make(probe);
      c.listen(latencyControllerProvider, (_, _) {});
      final ctl = c.read(latencyControllerProvider.notifier);
      final run = ctl.testAll();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(c.read(latencyControllerProvider).running, isTrue);
      ctl.stop();
      await run;
      final s = c.read(latencyControllerProvider);
      expect(s.running, isFalse);
      expect(
        s.results.values.where((r) => r.status == TargetStatus.testing),
        isEmpty,
      );
      expect(s.finished, lessThan(LatencyTarget.builtIn.length));
    });

    test(
      'custom targets are validated, stored in settings, tested and removable',
      () async {
        final probe = FakeProbe({});
        final c = make(probe);
        c.listen(latencyControllerProvider, (_, _) {});
        final ctl = c.read(latencyControllerProvider.notifier);

        expect(ctl.addCustom('bad address'), AddTargetOutcome.invalid);
        expect(ctl.addCustom('my.server.net:8443'), AddTargetOutcome.added);
        expect(ctl.addCustom('MY.server.net:8443'), AddTargetOutcome.duplicate);
        expect(c.read(settingsProvider).customLatencyTargets, [
          'my.server.net:8443',
        ]);
        expect(ctl.customTargets.single.group, LatencyGroup.custom);

        await ctl.testAll();
        expect(probe.measured, contains('my.server.net'));
        final id = ctl.customTargets.single.id;
        expect(
          c.read(latencyControllerProvider).resultOf(id).status,
          TargetStatus.done,
        );

        ctl.removeCustom(ctl.customTargets.single);
        expect(c.read(settingsProvider).customLatencyTargets, isEmpty);
        expect(
          c.read(latencyControllerProvider).results.containsKey(id),
          isFalse,
        );
      },
    );

    test('number of custom targets is limited', () {
      final c = make(FakeProbe({}));
      c.listen(latencyControllerProvider, (_, _) {});
      final ctl = c.read(latencyControllerProvider.notifier);
      for (var i = 0; i < LatencyTarget.maxCustom; i++) {
        expect(ctl.addCustom('h$i.example.com'), AddTargetOutcome.added);
      }
      expect(
        ctl.addCustom('one.more.example.com'),
        AddTargetOutcome.limitReached,
      );
    });
  });

  group('latency page', () {
    testWidgets(
      'speed icon on the overview opens the page; test shows results; custom address can be added',
      (tester) async {
        tester.view.physicalSize = const Size(800, 4000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final probe = FakeProbe({
          'www.baidu.com': const LatencyMeasurement(
            dnsMs: 4,
            tcpMs: [30, 32, 34, 36],
          ),
          'www.google.com': const LatencyMeasurement(
            dnsMs: 4,
            tcpMs: [null, null, null, null],
          ),
        });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              realPlatformProvider.overrideWithValue(
                UnsupportedPlatform('windows'),
              ),
              latencyProbeProvider.overrideWithValue(probe),
              initialSettingsProvider.overrideWithValue(
                const AppSettings(languageCode: 'en'),
              ),
            ],
            child: const SignalScopeApp(),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        await tester.tap(find.byIcon(Icons.speed_rounded));
        await tester.pumpAndSettle();
        expect(find.text('Latency test'), findsOneWidget);
        expect(find.text('Mainland China'), findsOneWidget);
        expect(find.text('USA / International'), findsOneWidget);
        expect(find.text('Custom addresses'), findsOneWidget);
        expect(find.text('Baidu 百度'), findsOneWidget);
        expect(find.text('Google'), findsOneWidget);

        await tester.tap(find.text('Start test'));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Timeout / unreachable'), findsOneWidget); // google
        expect(find.text('33'), findsOneWidget); // baidu average
        expect(find.text('Start test'), findsOneWidget); // run finished

        await tester.enterText(find.byType(TextField), 'no good');
        await tester.tap(find.text('Add'));
        await tester.pump();
        expect(find.text('Invalid address'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'my.host.dev');
        await tester.tap(find.text('Add'));
        await tester.pump();
        expect(find.text('my.host.dev'), findsWidgets);
        expect(find.text('Invalid address'), findsNothing);

        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      },
    );
  });
}
