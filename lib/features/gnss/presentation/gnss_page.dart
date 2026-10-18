import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/signal_quality.dart';
import '../../../data/models/gnss_info.dart';
import '../../../data/models/platform_info.dart';
import '../../../shared/widgets/cards.dart';
import '../../../shared/widgets/monitor_bar.dart';
import '../../../shared/widgets/page_scaffold.dart';
import '../../../shared/widgets/trend_chart.dart';
import '../../permissions/application/permission_controller.dart';
import '../../permissions/presentation/permission_banner.dart';
import '../application/gnss_controller.dart';
import '../data/gnss_repository.dart';
import 'cn0_bars.dart';
import 'constellation_flag.dart';
import 'sky_plot.dart';

/// Colour and i18n key for a [FixState].
(Color, String) fixStateStyle(FixState s) => switch (s) {
  FixState.unknown => (SignalColors.none, 'gnss.state.unknown'),
  FixState.unsupported => (SignalColors.bad, 'gnss.state.unsupported'),
  FixState.blocked => (SignalColors.poor, 'gnss.state.blocked'),
  FixState.searching => (SignalColors.fair, 'gnss.state.searching'),
  FixState.fixed => (SignalColors.excellent, 'gnss.state.fixed'),
  FixState.stale => (SignalColors.poor, 'gnss.state.stale'),
};

class GnssPage extends ConsumerWidget {
  const GnssPage({super.key});

  static const Set<PermGroup> _groups = {PermGroup.location};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = ref.watch(signalPlatformProvider);
    if (!platform.isAndroid) {
      return PageScaffold(
        title: context.tr('nav.gnss'),
        children: [UnsupportedNotice(platformName: platform.name)],
      );
    }
    final state = ref.watch(gnssControllerProvider);
    final perms = ref.watch(permissionProvider);
    final controller = ref.read(gnssControllerProvider.notifier);
    final snap = state.snapshot;
    final unsupported = state.fixState == FixState.unsupported;

    return PageScaffold(
      title: context.tr('nav.gnss'),
      children: [
        if (!unsupported &&
            PermissionBanner.isNeeded(
              perms,
              _groups,
              needsLocationServices: true,
            ))
          const PermissionBanner(
            groups: _groups,
            messageKey: 'gnss.permWhy',
            needsLocationServices: true,
          ),
        MonitorBar(
          status: state.status,
          streaming: state.streaming,
          updatedAtMs: snap?.timestampMs,
          onStart: controller.start,
          onPause: controller.pause,
          onStop: controller.stop,
        ),
        _FixCard(state: state),
        if (!unsupported) ...[
          if (snap?.location != null) _PositionCard(state: state),
          _SatelliteSummary(snap: snap),
          if (snap != null && snap.satellites.isNotEmpty) ...[
            _SkyCard(sats: snap.satellites),
            _Cn0Card(sats: snap.satellites),
          ],
          const _GnssTrends(),
          if (snap != null && snap.satellites.isNotEmpty)
            _SatelliteList(sats: snap.satellites),
        ],
        if (snap != null && snap.issues.isNotEmpty)
          _IssueList(issues: snap.issues),
      ],
    );
  }
}

class _FixCard extends ConsumerWidget {
  const _FixCard({required this.state});

  final GnssState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final fix = state.fixState;
    final (color, key) = fixStateStyle(fix);
    final snap = state.snapshot;
    final mock = snap?.location?.isMock == true;

    final hint = switch (fix) {
      FixState.searching => context.tr('gnss.hint.searching'),
      FixState.stale => context.tr('gnss.hint.stale'),
      _ => null,
    };
    final showLocationSettings =
        snap?.issues.contains('location_off') == true ||
        snap?.issues.contains('gps_provider_disabled') == true;

    return SectionCard(
      title: context.tr('gnss.fix'),
      trailing: StatusPill(
        text: context.tr(key),
        color: color,
        icon: Icons.satellite_alt_rounded,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoRow(
            label: context.tr('gnss.ttff'),
            value: snap?.ttffMs == null ? null : fmtDuration(snap!.ttffMs),
            note: snap?.ttffMs == null ? null : context.tr('gnss.ttffNote'),
          ),
          InfoRow(
            label: context.tr('gnss.engine'),
            value: fmtBool(
              snap?.engineStarted,
              yes: context.tr('gnss.engine.running'),
              no: context.tr('gnss.engine.stopped'),
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 8),
            Text(
              hint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (mock) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: SignalColors.fair,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    context.tr('gnss.hint.mock'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: SignalColors.fair,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (showLocationSettings) ...[
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () =>
                  ref.read(signalPlatformProvider).openLocationSettings(),
              child: Text(context.tr('perm.openLocationSettings')),
            ),
          ],
        ],
      ),
    );
  }
}

class _PositionCard extends StatelessWidget {
  const _PositionCard({required this.state});

  final GnssState state;

  @override
  Widget build(BuildContext context) {
    final loc = state.snapshot!.location!;
    final age = state.fixAgeMs;
    return SectionCard(
      title: context.tr('gnss.position'),
      child: Column(
        children: [
          InfoRow(
            label: context.tr('gnss.latitude'),
            value: fmtCoord(loc.latitude, isLat: true),
            emphasize: true,
          ),
          InfoRow(
            label: context.tr('gnss.longitude'),
            value: fmtCoord(loc.longitude, isLat: false),
            emphasize: true,
          ),
          InfoRow(
            label: context.tr('gnss.altitude'),
            value: loc.altitudeM == null
                ? null
                : fmtNum(loc.altitudeM, unit: 'm', decimals: 1),
            note: loc.altitudeM == null
                ? null
                : context.tr('gnss.altitudeNote'),
          ),
          InfoRow(
            label: context.tr('gnss.hAcc'),
            value: loc.horizontalAccuracyM == null
                ? null
                : fmtNum(loc.horizontalAccuracyM, unit: 'm', decimals: 1),
            note: loc.horizontalAccuracyM == null
                ? null
                : context.tr('gnss.hAccNote'),
          ),
          InfoRow(
            label: context.tr('gnss.vAcc'),
            value: loc.verticalAccuracyM == null
                ? null
                : fmtNum(loc.verticalAccuracyM, unit: 'm', decimals: 1),
          ),
          InfoRow(
            label: context.tr('gnss.speed'),
            value: loc.speedMps == null
                ? null
                : '${fmtNum(loc.speedMps, decimals: 1)} m/s · ${fmtNum(loc.speedMps! * 3.6, decimals: 1)} km/h',
          ),
          InfoRow(
            label: context.tr('gnss.bearing'),
            value: loc.bearingDeg == null
                ? null
                : fmtNum(loc.bearingDeg, unit: '°', decimals: 0),
          ),
          InfoRow(
            label: context.tr('gnss.fixTime'),
            value: loc.timeMs == null ? null : fmtClock(loc.timeMs),
          ),
          InfoRow(
            label: context.tr('gnss.fixAge'),
            value: age == null ? null : fmtDuration(age),
          ),
          InfoRow(label: context.tr('gnss.provider'), value: loc.provider),
        ],
      ),
    );
  }
}

class _SatelliteSummary extends StatelessWidget {
  const _SatelliteSummary({required this.snap});

  final GnssSnapshot? snap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sats = snap?.satellites ?? const <SatelliteInfo>[];
    final hasData =
        snap != null && snap!.engineStarted != null || sats.isNotEmpty;
    final avg = GnssRepository.averageCn0(sats);
    final byConstellation = <Constellation, int>{};
    for (final s in sats) {
      byConstellation[s.constellation] =
          (byConstellation[s.constellation] ?? 0) + 1;
    }
    return SectionCard(
      title: context.tr('gnss.satellites'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Stat(
                label: context.tr('gnss.visible'),
                value: hasData ? '${sats.length}' : kUnavailable,
              ),
              _Stat(
                label: context.tr('gnss.used'),
                value: hasData ? '${snap!.usedCount}' : kUnavailable,
              ),
              _Stat(
                label: context.tr('gnss.tracked'),
                value: hasData
                    ? '${GnssRepository.trackedCount(sats)}'
                    : kUnavailable,
              ),
            ],
          ),
          const SizedBox(height: 8),
          InfoRow(
            label: context.tr('gnss.avgCn0'),
            value: avg == null ? null : fmtNum(avg, unit: 'dB-Hz', decimals: 1),
            note: avg == null ? null : context.tr('gnss.avgCn0Note'),
            valueColor: SignalQuality.cn0(avg).color,
          ),
          if (byConstellation.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e
                    in (byConstellation.entries.toList()
                      ..sort((a, b) => a.key.code.compareTo(b.key.code))))
                  StatusPill(
                    text:
                        '${ConstellationFlag.of(e.key).emoji} ${e.key.label} ${e.value}',
                    color: constellationColor(e.key),
                  ),
              ],
            ),
          ] else if (hasData)
            Text(
              context.tr('gnss.noSats'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SkyCard extends StatelessWidget {
  const _SkyCard({required this.sats});

  final List<SatelliteInfo> sats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      title: context.tr('gnss.skyPlot'),
      child: Column(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: SkyPlot(satellites: sats),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final c
                  in (sats.map((s) => s.constellation).toSet().toList()
                    ..sort((a, b) => a.code.compareTo(b.code))))
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: constellationColor(c),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${ConstellationFlag.of(c).emoji} ${c.label} · ${context.tr(ConstellationFlag.of(c).countryKey)}',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('gnss.skyNote'),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Cn0Card extends StatelessWidget {
  const _Cn0Card({required this.sats});

  final List<SatelliteInfo> sats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      title: context.tr('gnss.cn0Chart'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Cn0Bars(satellites: sats),
          const SizedBox(height: 8),
          Text(
            context.tr('gnss.cn0Note'),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _GnssTrends extends StatelessWidget {
  const _GnssTrends();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TrendCard(
          title:
              '${context.tr('common.trend')} · ${context.tr('gnss.trendCn0')}',
          series: [
            TrendSeries(
              key: 'gnss.cn0avg',
              label: 'C/N0',
              unit: 'dB-Hz',
              color: SignalColors.chartA,
            ),
          ],
          minY: 0,
          maxY: 50,
        ),
        TrendCard(
          title:
              '${context.tr('common.trend')} · ${context.tr('gnss.trendUsed')}',
          series: [
            TrendSeries(
              key: 'gnss.used',
              label: context.tr('gnss.used'),
              unit: '',
              color: SignalColors.chartD,
            ),
          ],
          minY: 0,
          maxY: 20,
        ),
      ],
    );
  }
}

class _SatelliteList extends StatelessWidget {
  const _SatelliteList({required this.sats});

  final List<SatelliteInfo> sats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = [...sats]
      ..sort((a, b) => (b.cn0DbHz ?? -1).compareTo(a.cn0DbHz ?? -1));
    final head = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return SectionCard(
      title: '${context.tr('gnss.list')} (${sats.length})',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 4,
                child: Text(context.tr('gnss.col.sat'), style: head),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  context.tr('gnss.col.az'),
                  style: head,
                  textAlign: TextAlign.end,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  context.tr('gnss.col.el'),
                  style: head,
                  textAlign: TextAlign.end,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  context.tr('gnss.col.cn0'),
                  style: head,
                  textAlign: TextAlign.end,
                ),
              ),
              Expanded(
                flex: 1,
                child: Text(
                  context.tr('gnss.col.used'),
                  style: head,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          const Divider(),
          for (final s in sorted) _SatRow(sat: s),
        ],
      ),
    );
  }
}

class _SatRow extends StatelessWidget {
  const _SatRow({required this.sat});

  final SatelliteInfo sat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tracked = (sat.cn0DbHz ?? 0) > 0;
    final style = theme.textTheme.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final carrier = sat.carrierFrequencyHz;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      ConstellationFlag.of(sat.constellation).emoji,
                      style: const TextStyle(fontSize: 15),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${sat.constellation.label} ${sat.svid}',
                        overflow: TextOverflow.ellipsis,
                        style: style?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                if (carrier != null)
                  Text(
                    '${context.tr('gnss.carrier')} ${(carrier / 1e6).toStringAsFixed(2)} MHz',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              fmtNum(sat.azimuthDeg, unit: '°'),
              style: style,
              textAlign: TextAlign.end,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              fmtNum(sat.elevationDeg, unit: '°'),
              style: style,
              textAlign: TextAlign.end,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              tracked ? fmtNum(sat.cn0DbHz, decimals: 1) : kUnavailable,
              style: style?.copyWith(
                color: tracked ? SignalQuality.cn0(sat.cn0DbHz).color : null,
              ),
              textAlign: TextAlign.end,
            ),
          ),
          Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.centerRight,
              child: sat.usedInFix == true
                  ? const Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: SignalColors.excellent,
                    )
                  : Text(kUnavailable, style: style),
            ),
          ),
        ],
      ),
    );
  }
}

class _IssueList extends StatelessWidget {
  const _IssueList({required this.issues});

  final List<String> issues;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      title: context.tr('cellular.notes'),
      child: Column(
        children: [
          for (final i in issues)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.tr('gnssissue.$i'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
