import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/network_type.dart';
import '../../../core/utils/signal_quality.dart';
import '../../../core/utils/wifi_utils.dart';
import '../../../data/models/cellular_info.dart';
import '../../../data/models/platform_info.dart';
import '../../../data/models/sim_info.dart';
import '../../../shared/widgets/address_widgets.dart';
import '../../../shared/widgets/cards.dart';
import '../../../shared/widgets/mini_signal_bar.dart';
import '../../../shared/widgets/page_scaffold.dart';
import '../../../shared/widgets/trend_chart.dart';
import '../../cellular/application/cellular_controller.dart';
import '../../gnss/application/gnss_controller.dart';
import '../../gnss/data/gnss_repository.dart';
import '../../gnss/presentation/gnss_page.dart' show fixStateStyle;
import '../../latency/presentation/latency_page.dart';
import '../../permissions/application/permission_controller.dart';
import '../../permissions/presentation/permission_banner.dart';
import '../../shell/application/navigation.dart';
import '../../wifi/application/wifi_controller.dart';

/// Aggregated live view: SIMs, Wi-Fi, GNSS and the signal trends.
///
/// This page owns no data; it only reads the three controllers, so values are
/// exactly what the detail pages show.
class OverviewPage extends ConsumerWidget {
  const OverviewPage({super.key});

  static const Set<PermGroup> _groups = {PermGroup.phone, PermGroup.location, PermGroup.nearbyWifi};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = ref.watch(signalPlatformProvider);
    // The latency test only needs dart:io, so it works on every platform.
    final actions = [
      IconButton(
        tooltip: context.tr('latency.open'),
        icon: const Icon(Icons.speed_rounded),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const LatencyPage()),
        ),
      ),
    ];
    if (!platform.isAndroid) {
      return PageScaffold(
        title: context.tr('nav.overview'),
        actions: actions,
        children: [UnsupportedNotice(platformName: platform.name)],
      );
    }
    final perms = ref.watch(permissionProvider);
    final cell = ref.watch(cellularControllerProvider);
    final wifi = ref.watch(wifiControllerProvider);
    final gnss = ref.watch(gnssControllerProvider);

    return PageScaffold(
      title: context.tr('nav.overview'),
      actions: actions,
      onRefresh: () => ref.read(cellularControllerProvider.notifier).refreshSims(),
      children: [
        if (PermissionBanner.isNeeded(perms, _groups))
          const PermissionBanner(groups: _groups, messageKey: 'overview.permWhy'),
        if (cell.simsLoaded && cell.sims.isEmpty)
          _SummaryCard(
            icon: Icons.sim_card_alert_outlined,
            title: context.tr('overview.cellular'),
            onTap: () => ref.read(currentTabProvider.notifier).select(AppTab.cellular),
            child: Text(context.tr('overview.noSim'), style: Theme.of(context).textTheme.bodyMedium),
          ),
        for (final sim in cell.sims)
          _SimSummary(
            sim: sim,
            info: cell.latest[sim.subscriptionId],
            paused: cell.status != MonitorStatus.listening,
            onTap: () {
              ref.read(cellularControllerProvider.notifier).selectSim(sim.subscriptionId);
              ref.read(currentTabProvider.notifier).select(AppTab.cellular);
            },
          ),
        _WifiSummary(state: wifi),
        _GnssSummary(state: gnss),
        if (cell.sims.isNotEmpty) _CellularTrend(sims: cell.sims),
        const _WifiTrend(),
      ],
    );
  }
}

/// Tappable card with an icon title row. Navigation target is chosen by the caller.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.title,
    required this.child,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  ?trailing,
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded, size: 20, color: theme.colorScheme.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Large value with unit and a coloured level bar below it.
class _ValueBlock extends StatelessWidget {
  const _ValueBlock({
    required this.valueText,
    required this.unit,
    required this.color,
    required this.fraction,
    this.caption,
  });

  final String valueText;
  final String unit;
  final Color color;
  final double? fraction;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final missing = fraction == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
              child: Text(
                valueText,
                key: ValueKey(valueText),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: missing ? theme.colorScheme.onSurfaceVariant : color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(unit, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
        if (caption != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              caption!,
              style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        const SizedBox(height: 8),
        MiniSignalBar(fraction: fraction, color: color),
      ],
    );
  }
}

class _SimSummary extends StatelessWidget {
  const _SimSummary({required this.sim, required this.info, required this.paused, required this.onTap});

  final SimInfo sim;
  final CellularInfo? info;
  final bool paused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reading = info?.gaugeReading;
    final lteNr = reading != null && (reading.rat == 'LTE' || reading.rat == 'NR');
    final grade = reading == null
        ? SignalGrade.none
        : (lteNr ? SignalQuality.rsrp(reading.dbm) : SignalQuality.legacyDbm(reading.dbm));
    final fraction = reading == null
        ? null
        : (lteNr
            ? SignalQuality.fraction(reading.dbm, min: -140, max: -44)
            : SignalQuality.fraction(reading.dbm, min: -113, max: -51));
    final typeCode = info?.dataNetworkType ?? sim.dataNetworkType;
    final typeName = NetworkTypes.name(typeCode);
    final mode = info?.nrMode;
    final operator = info?.operatorName ?? sim.networkOperatorName ?? sim.carrierName;

    return _SummaryCard(
      icon: Icons.signal_cellular_alt_rounded,
      title: '${sim.slotLabel} · ${fmtText(operator)}',
      onTap: onTap,
      trailing: Wrap(
        spacing: 6,
        children: [
          if (typeName != null) StatusPill(text: typeName, color: theme.colorScheme.primary),
          if (mode != null) StatusPill(text: '5G $mode', color: SignalColors.chartB),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ValueBlock(
            valueText: reading == null ? kUnavailable : '${reading.dbm}',
            unit: reading == null ? '' : 'dBm',
            color: grade.color,
            fraction: fraction,
            caption: reading != null
                ? '${reading.rat} ${reading.metric} · ${context.tr(grade.labelKey)}'
                : context.tr(paused ? 'overview.paused' : 'overview.waiting'),
          ),
          if (info != null && info!.hasDataNetwork != null) ...[
            const SizedBox(height: 10),
            if (info!.hasDataNetwork == true)
              AddressLines(entries: [
                AddressEntry(context.tr('addr.ipv4'), info!.ipv4),
                AddressEntry(context.tr('addr.ipv6'), fmtFirstOfMany(info!.ipv6), hint: context.tr('addr.noIpv6')),
              ])
            else
              Row(
                children: [
                  Icon(Icons.link_off_rounded, size: 14, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      context.tr('addr.noDataNetwork'),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

class _WifiSummary extends ConsumerWidget {
  const _WifiSummary({required this.state});

  final WifiState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final conn = state.connection;
    final off = conn?.wifiEnabled == false;
    final connected = conn?.connected == true;
    final rssi = connected ? conn?.rssi : null;
    final grade = SignalQuality.wifiRssi(rssi);

    final String caption;
    if (off) {
      caption = context.tr('wifi.disabled');
    } else if (conn == null) {
      caption = context.tr(state.status == MonitorStatus.listening ? 'overview.waiting' : 'overview.paused');
    } else if (!connected) {
      caption = context.tr('wifi.notConnected');
    } else {
      caption = '${conn.ssid ?? context.tr('wifi.hiddenSsid')}'
          '${conn.linkSpeedMbps != null ? ' · ${conn.linkSpeedMbps} Mbps' : ''}';
    }

    return _SummaryCard(
      icon: off ? Icons.wifi_off_rounded : Icons.wifi_rounded,
      title: context.tr('overview.wifi'),
      onTap: () => ref.read(currentTabProvider.notifier).select(AppTab.wifi),
      trailing: connected && conn!.band != WifiBand.unknown
          ? StatusPill(text: conn.band.label, color: theme.colorScheme.primary)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ValueBlock(
            valueText: rssi == null ? kUnavailable : '$rssi',
            unit: rssi == null ? '' : 'dBm',
            color: grade.color,
            fraction: rssi == null ? null : SignalQuality.fraction(rssi, min: -100, max: -30),
            caption: caption,
          ),
          if (connected) ...[
            const SizedBox(height: 10),
            AddressLines(entries: [
              AddressEntry(context.tr('addr.ipv4'), conn!.ipAddress),
              AddressEntry(context.tr('addr.ipv6'), fmtFirstOfMany(conn.ipv6), hint: context.tr('addr.noIpv6')),
              AddressEntry(context.tr('addr.mac'), conn.macAddress, hint: context.tr('addr.macHiddenShort')),
              AddressEntry(context.tr('addr.routerMac'), conn.bssid),
            ]),
          ],
        ],
      ),
    );
  }
}

class _GnssSummary extends ConsumerWidget {
  const _GnssSummary({required this.state});

  final GnssState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final fix = state.fixState;
    final (color, key) = fixStateStyle(fix);
    final snap = state.snapshot;
    final loc = snap?.location;
    final showCounts = fix != FixState.unsupported && fix != FixState.unknown && snap != null;
    final avg = snap == null ? null : GnssRepository.averageCn0(snap.satellites);

    return _SummaryCard(
      icon: Icons.satellite_alt_rounded,
      title: context.tr('overview.gnss'),
      onTap: () => ref.read(currentTabProvider.notifier).select(AppTab.gnss),
      trailing: StatusPill(text: context.tr(key), color: color),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showCounts)
            Text(
              context.tr('overview.satellites', [snap.usedCount, snap.visibleCount]),
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            )
          else
            Text(
              context.tr(fix == FixState.unsupported ? 'gnss.state.unsupported' : 'overview.waiting'),
              style: theme.textTheme.bodyMedium,
            ),
          if (loc != null && loc.hasFix) ...[
            const SizedBox(height: 4),
            Text(
              '${fmtCoord(loc.latitude, isLat: true)}   ${fmtCoord(loc.longitude, isLat: false)}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          if (loc?.horizontalAccuracyM != null || avg != null) ...[
            const SizedBox(height: 4),
            Text(
              [
                if (loc?.horizontalAccuracyM != null)
                  '${context.tr('gnss.hAcc')} ${fmtNum(loc!.horizontalAccuracyM, unit: 'm', decimals: 1)}',
                if (avg != null) 'C/N0 ${fmtNum(avg, unit: 'dB-Hz', decimals: 1)}',
              ].join(' · '),
              style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _CellularTrend extends StatelessWidget {
  const _CellularTrend({required this.sims});

  final List<SimInfo> sims;

  static const _colors = [SignalColors.chartA, SignalColors.chartB, SignalColors.chartC];

  @override
  Widget build(BuildContext context) {
    return TrendCard(
      title: context.tr('overview.cellularTrend'),
      series: [
        for (var i = 0; i < sims.length; i++)
          TrendSeries(
            key: 'cell.${sims[i].subscriptionId}.primary',
            label: sims[i].slotLabel,
            unit: 'dBm',
            color: _colors[i % _colors.length],
          ),
      ],
      minY: -140,
      maxY: -40,
    );
  }
}

class _WifiTrend extends StatelessWidget {
  const _WifiTrend();

  @override
  Widget build(BuildContext context) {
    return TrendCard(
      title: context.tr('overview.wifiTrend'),
      series: const [
        TrendSeries(key: 'wifi.rssi', label: 'RSSI', unit: 'dBm', color: SignalColors.chartD),
      ],
      minY: -100,
      maxY: -30,
    );
  }
}
