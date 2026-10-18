import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'latency_targets.dart';

/// Raw outcome of probing one target.
class LatencyMeasurement {
  const LatencyMeasurement({this.dnsMs, this.tcpMs = const [], this.dnsFailed = false});

  /// DNS resolution time; `null` for IP literals or when resolution failed.
  final double? dnsMs;

  /// One entry per attempt: handshake time in ms, or `null` for a lost attempt
  /// (timeout or connection error).
  final List<double?> tcpMs;

  /// The host name could not be resolved at all.
  final bool dnsFailed;
}

/// Summary of the attempts of one target. Pure data + maths, unit-tested.
class LatencyStats {
  const LatencyStats({
    required this.sent,
    required this.received,
    this.minMs,
    this.avgMs,
    this.maxMs,
    this.jitterMs,
    this.dnsMs,
  });

  final int sent;
  final int received;
  final double? minMs;
  final double? avgMs;
  final double? maxMs;

  /// Mean absolute difference between consecutive successful attempts
  /// (the RFC 3550 style interarrival jitter, without smoothing).
  final double? jitterMs;
  final double? dnsMs;

  double get lossPercent => sent == 0 ? 0 : (sent - received) * 100 / sent;
  bool get reachable => received > 0;

  /// Lost attempts are never counted as 0 ms: only successful ones feed the numbers.
  factory LatencyStats.fromSamples(List<double?> samples, {double? dnsMs}) {
    final ok = <double>[for (final s in samples) ?s];
    if (ok.isEmpty) {
      return LatencyStats(sent: samples.length, received: 0, dnsMs: dnsMs);
    }
    var sum = 0.0;
    var lo = ok.first;
    var hi = ok.first;
    for (final v in ok) {
      sum += v;
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    double? jitter;
    if (ok.length >= 2) {
      var d = 0.0;
      for (var i = 1; i < ok.length; i++) {
        d += (ok[i] - ok[i - 1]).abs();
      }
      jitter = d / (ok.length - 1);
    }
    return LatencyStats(
      sent: samples.length,
      received: ok.length,
      minMs: lo,
      avgMs: sum / ok.length,
      maxMs: hi,
      jitterMs: jitter,
      dnsMs: dnsMs,
    );
  }
}

/// Measures TCP handshake time to a target. Replaceable in tests.
abstract class LatencyProbe {
  Future<LatencyMeasurement> measure(
    LatencyTarget target, {
    required int samples,
    required Duration timeout,
    required bool Function() isCancelled,
  });
}

/// `dart:io` implementation: resolve once (timed), then connect [samples]
/// times to the resolved address and time each TCP handshake. ICMP ping needs
/// elevated rights on Android, so the handshake time is the honest substitute.
class SocketLatencyProbe implements LatencyProbe {
  const SocketLatencyProbe();

  @override
  Future<LatencyMeasurement> measure(
    LatencyTarget target, {
    required int samples,
    required Duration timeout,
    required bool Function() isCancelled,
  }) async {
    InternetAddress? address = InternetAddress.tryParse(target.host);
    double? dnsMs;
    if (address == null) {
      final sw = Stopwatch()..start();
      try {
        final list = await InternetAddress.lookup(target.host).timeout(timeout);
        sw.stop();
        if (list.isEmpty) return const LatencyMeasurement(dnsFailed: true);
        // Prefer IPv4 so results are comparable between sites.
        address = list.firstWhere((a) => a.type == InternetAddressType.IPv4, orElse: () => list.first);
        dnsMs = sw.elapsedMicroseconds / 1000;
      } on Object {
        return const LatencyMeasurement(dnsFailed: true);
      }
    }

    final results = <double?>[];
    for (var i = 0; i < samples; i++) {
      if (isCancelled()) break;
      final sw = Stopwatch()..start();
      try {
        final socket = await Socket.connect(address, target.port, timeout: timeout);
        sw.stop();
        socket.destroy();
        results.add(sw.elapsedMicroseconds / 1000);
      } on Object {
        results.add(null);
      }
      if (i < samples - 1) await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    return LatencyMeasurement(dnsMs: dnsMs, tcpMs: results);
  }
}

final latencyProbeProvider = Provider<LatencyProbe>((ref) => const SocketLatencyProbe());
