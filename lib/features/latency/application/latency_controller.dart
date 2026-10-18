import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/latency_probe.dart';
import '../data/latency_targets.dart';

enum TargetStatus { idle, testing, done, failed }

/// Why a target failed.
enum FailureKind { none, dns, unreachable }

class TargetResult {
  const TargetResult({this.status = TargetStatus.idle, this.stats, this.failure = FailureKind.none});

  final TargetStatus status;
  final LatencyStats? stats;
  final FailureKind failure;
}

enum AddTargetOutcome { added, invalid, duplicate, limitReached }

/// Colour class of an average latency: <50 ms, <100 ms, <200 ms, otherwise.
enum LatencyGrade {
  excellent,
  good,
  fair,
  poor;

  static LatencyGrade of(double ms) {
    if (ms < 50) return excellent;
    if (ms < 100) return good;
    if (ms < 200) return fair;
    return poor;
  }
}

class LatencyState {
  const LatencyState({this.results = const {}, this.running = false, this.total = 0, this.finished = 0});

  final Map<String, TargetResult> results;
  final bool running;

  /// Targets queued in the current run and how many are done.
  final int total;
  final int finished;

  TargetResult resultOf(String id) => results[id] ?? const TargetResult();

  LatencyState copyWith({Map<String, TargetResult>? results, bool? running, int? total, int? finished}) =>
      LatencyState(
        results: results ?? this.results,
        running: running ?? this.running,
        total: total ?? this.total,
        finished: finished ?? this.finished,
      );

  /// Mean of the average latency of reachable targets in [targets]; `null` if none.
  double? groupAverage(Iterable<LatencyTarget> targets) {
    var sum = 0.0;
    var n = 0;
    for (final t in targets) {
      final avg = results[t.id]?.stats?.avgMs;
      if (avg != null) {
        sum += avg;
        n++;
      }
    }
    return n == 0 ? null : sum / n;
  }
}

/// Runs latency tests. Auto-disposed with the page: leaving the page cancels
/// whatever is still running.
class LatencyController extends Notifier<LatencyState> {
  static const int samples = 4;
  static const Duration timeout = Duration(seconds: 5);
  static const int concurrency = 4;

  int _epoch = 0;
  bool _alive = true;

  LatencyProbe get _probe => ref.read(latencyProbeProvider);

  @override
  LatencyState build() {
    _alive = true;
    ref.onDispose(() {
      _alive = false;
      _epoch++;
    });
    return const LatencyState();
  }

  /// Built-in targets plus the user's custom ones, in display order.
  List<LatencyTarget> get targets => [...LatencyTarget.builtIn, ...customTargets];

  List<LatencyTarget> get customTargets {
    final list = <LatencyTarget>[];
    final seen = <String>{};
    for (final s in ref.read(settingsProvider).customLatencyTargets) {
      final t = LatencyTarget.parseCustom(s);
      if (t != null && seen.add(t.id)) list.add(t);
    }
    return list;
  }

  Future<void> testAll() => _run(targets);

  Future<void> testOne(LatencyTarget target) => _run([target]);

  void stop() {
    _epoch++;
    final reset = {
      for (final e in state.results.entries)
        e.key: e.value.status == TargetStatus.testing ? const TargetResult() : e.value,
    };
    state = state.copyWith(results: reset, running: false);
  }

  Future<void> _run(List<LatencyTarget> list) async {
    if (list.isEmpty) return;
    final epoch = ++_epoch;
    bool cancelled() => !_alive || epoch != _epoch;

    state = state.copyWith(
      running: true,
      total: list.length,
      finished: 0,
      results: {
        ...state.results,
        for (final t in list) t.id: const TargetResult(status: TargetStatus.testing),
      },
    );

    final queue = [...list];
    Future<void> worker() async {
      while (queue.isNotEmpty && !cancelled()) {
        final t = queue.removeAt(0);
        final m = await _probe.measure(t, samples: samples, timeout: timeout, isCancelled: cancelled);
        if (cancelled()) return;
        final TargetResult result;
        if (m.dnsFailed) {
          result = const TargetResult(status: TargetStatus.failed, failure: FailureKind.dns);
        } else {
          final stats = LatencyStats.fromSamples(m.tcpMs, dnsMs: m.dnsMs);
          result = stats.reachable
              ? TargetResult(status: TargetStatus.done, stats: stats)
              : TargetResult(status: TargetStatus.failed, stats: stats, failure: FailureKind.unreachable);
        }
        state = state.copyWith(
          results: {...state.results, t.id: result},
          finished: state.finished + 1,
        );
      }
    }

    await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
    if (!cancelled()) state = state.copyWith(running: false);
  }

  // ---- custom targets ----

  AddTargetOutcome addCustom(String input) {
    final t = LatencyTarget.parseCustom(input);
    if (t == null) return AddTargetOutcome.invalid;
    final current = ref.read(settingsProvider).customLatencyTargets;
    if (customTargets.any((e) => e.id == t.id)) return AddTargetOutcome.duplicate;
    if (current.length >= LatencyTarget.maxCustom) return AddTargetOutcome.limitReached;
    ref.read(settingsProvider.notifier).update(
          (s) => s.copyWith(customLatencyTargets: [...s.customLatencyTargets, t.storageKey]),
        );
    return AddTargetOutcome.added;
  }

  void removeCustom(LatencyTarget target) {
    ref.read(settingsProvider.notifier).update(
          (s) => s.copyWith(
            customLatencyTargets: [
              for (final e in s.customLatencyTargets)
                if (LatencyTarget.parseCustom(e)?.id != target.id) e,
            ],
          ),
        );
    state = state.copyWith(results: {...state.results}..remove(target.id));
  }
}

final latencyControllerProvider =
    NotifierProvider.autoDispose<LatencyController, LatencyState>(LatencyController.new);
