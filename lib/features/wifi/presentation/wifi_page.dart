import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/signal_quality.dart';
import '../../../core/utils/wifi_utils.dart';
import '../../../data/models/platform_info.dart';
import '../../../data/models/wifi_info.dart';
import '../../../shared/widgets/address_widgets.dart';
import '../../../shared/widgets/cards.dart';
import '../../../shared/widgets/monitor_bar.dart';
import '../../../shared/widgets/page_scaffold.dart';
import '../../../shared/widgets/signal_bars.dart';
import '../../../shared/widgets/signal_gauge.dart';
import '../../../shared/widgets/trend_chart.dart';
import '../../permissions/application/permission_controller.dart';
import '../../permissions/presentation/permission_banner.dart';
import '../application/wifi_controller.dart';
import '../data/wifi_repository.dart';
import 'channel_graph.dart';

class WifiPage extends ConsumerWidget {
  const WifiPage({super.key});

  static const Set<PermGroup> _groups = {
    PermGroup.location,
    PermGroup.nearbyWifi,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = ref.watch(signalPlatformProvider);
    if (!platform.isAndroid) {
      return PageScaffold(
        title: context.tr('nav.wifi'),
        children: [UnsupportedNotice(platformName: platform.name)],
      );
    }
    final state = ref.watch(wifiControllerProvider);
    final perms = ref.watch(permissionProvider);
    final controller = ref.read(wifiControllerProvider.notifier);
    final conn = state.connection;
    final wifiOff = conn?.wifiEnabled == false;
    // Hide the "disabled" note: the dedicated card already says so.
    final issues = <String>{
      ...?conn?.issues,
      ...?state.scan?.issues,
    }.where((i) => i != 'wifi_disabled').toList();

    return PageScaffold(
      title: context.tr('nav.wifi'),
      children: [
        if (PermissionBanner.isNeeded(
          perms,
          _groups,
          needsLocationServices: true,
        ))
          const PermissionBanner(
            groups: _groups,
            messageKey: 'wifi.permWhy',
            needsLocationServices: true,
          ),
        MonitorBar(
          status: state.status,
          streaming: state.streaming,
          updatedAtMs: conn?.timestampMs,
          onStart: controller.start,
          onPause: controller.pause,
          onStop: controller.stop,
        ),
        if (wifiOff) const _WifiOffCard(),
        if (!wifiOff) _ConnectionGauge(conn: conn),
        if (!wifiOff) const _RssiTrend(),
        if (conn != null && conn.connected) _ConnectionDetails(conn: conn),
        if (!wifiOff) _NearbyCard(state: state),
        if (!wifiOff) _ChannelCard(state: state),
        if (issues.isNotEmpty) _IssueList(issues: issues),
      ],
    );
  }
}

class _WifiOffCard extends ConsumerWidget {
  const _WifiOffCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return SectionCard(
      child: Column(
        children: [
          Icon(
            Icons.wifi_off_rounded,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(context.tr('wifi.disabled'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            context.tr('wifi.disabledHint'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () =>
                ref.read(signalPlatformProvider).openWifiSettings(),
            child: Text(context.tr('wifi.openWifiSettings')),
          ),
        ],
      ),
    );
  }
}

class _ConnectionGauge extends StatelessWidget {
  const _ConnectionGauge({required this.conn});

  final WifiConnectionInfo? conn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = conn?.connected == true;
    final rssi = connected ? conn?.rssi : null;
    final grade = SignalQuality.wifiRssi(rssi);
    return SectionCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      connected
                          ? (conn?.ssid ?? context.tr('wifi.hiddenSsid'))
                          : context.tr('wifi.notConnected'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (connected)
                      Text(
                        fmtText(conn?.bssid),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (connected && conn!.band != WifiBand.unknown)
                StatusPill(
                  text: conn!.band.label,
                  color: theme.colorScheme.primary,
                ),
            ],
          ),
          const SizedBox(height: 8),
          SignalGauge(
            fraction: rssi == null
                ? null
                : SignalQuality.fraction(rssi, min: -100, max: -30),
            color: grade.color,
            valueText: rssi == null ? kUnavailable : '$rssi',
            unit: rssi == null ? '' : 'dBm',
            caption: rssi == null
                ? null
                : '${conn!.percent}% · ${context.tr(grade.labelKey)}',
          ),
          if (connected) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (conn!.standardLabel != null)
                  StatusPill(
                    text: conn!.standardLabel!,
                    color: SignalColors.chartB,
                    icon: Icons.bolt_rounded,
                  ),
                if (conn!.linkSpeedMbps != null)
                  StatusPill(
                    text: '${conn!.linkSpeedMbps} Mbps',
                    color: SignalColors.chartA,
                    icon: Icons.speed_rounded,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RssiTrend extends StatelessWidget {
  const _RssiTrend();

  @override
  Widget build(BuildContext context) {
    return TrendCard(
      title: context.tr('common.trend'),
      series: const [
        TrendSeries(
          key: 'wifi.rssi',
          label: 'RSSI',
          unit: 'dBm',
          color: SignalColors.chartD,
        ),
      ],
      minY: -100,
      maxY: -30,
    );
  }
}

class _ConnectionDetails extends StatelessWidget {
  const _ConnectionDetails({required this.conn});

  final WifiConnectionInfo conn;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: context.tr('wifi.connection'),
      child: Column(
        children: [
          InfoRow(label: 'SSID', value: conn.ssid),
          CopyableInfoRow(
            label: context.tr('addr.routerMac'),
            value: conn.bssid,
          ),
          CopyableInfoRow(
            label: context.tr('addr.mac'),
            value: conn.macAddress,
            note: conn.macAddress == null
                ? context.tr('addr.macHidden')
                : context.tr('addr.macReported'),
          ),
          InfoRow(
            label: 'RSSI',
            value: fmtNum(conn.rssi, unit: 'dBm'),
          ),
          InfoRow(
            label: context.tr('wifi.signalPercent'),
            value: conn.percent == null ? null : '${conn.percent}%',
            note: conn.percent == null ? null : context.tr('wifi.percentNote'),
          ),
          InfoRow(
            label: context.tr('wifi.frequency'),
            value: fmtNum(conn.frequencyMhz, unit: 'MHz'),
          ),
          InfoRow(
            label: context.tr('wifi.channel'),
            value: fmtNum(conn.channel),
            note: conn.channel == null ? null : context.tr('wifi.channelNote'),
          ),
          InfoRow(
            label: context.tr('wifi.bandwidth'),
            value: conn.channelWidthMhz == null
                ? null
                : '${conn.channelWidthMhz} MHz',
            note: conn.channelWidthMhz == null
                ? null
                : context.tr('wifi.widthNote'),
          ),
          InfoRow(
            label: context.tr('wifi.linkSpeed'),
            value: fmtNum(conn.linkSpeedMbps, unit: 'Mbps'),
          ),
          InfoRow(
            label: context.tr('wifi.txRate'),
            value: fmtNum(conn.txLinkSpeedMbps, unit: 'Mbps'),
          ),
          InfoRow(
            label: context.tr('wifi.rxRate'),
            value: fmtNum(conn.rxLinkSpeedMbps, unit: 'Mbps'),
          ),
          CopyableInfoRow(
            label: context.tr('addr.ipv4'),
            value: conn.ipAddress,
            note: context.tr('addr.copyHint'),
          ),
          CopyableInfoRow(
            label: context.tr('addr.ipv6'),
            value: conn.ipv6.isEmpty ? null : conn.ipv6.join('\n'),
            note: conn.ipv6.isEmpty ? context.tr('addr.noIpv6') : null,
          ),
          if (conn.ipv6LinkLocal.isNotEmpty)
            CopyableInfoRow(
              label: context.tr('addr.ipv6LinkLocal'),
              value: conn.ipv6LinkLocal.join('\n'),
              note: context.tr('addr.ipv6LinkNote'),
            ),
          InfoRow(label: context.tr('wifi.gateway'), value: conn.gateway),
          InfoRow(
            label: 'DNS',
            value: conn.dns.isEmpty ? null : conn.dns.join('\n'),
          ),
          InfoRow(
            label: context.tr('wifi.security'),
            value: conn.securityLabel,
          ),
          InfoRow(
            label: context.tr('wifi.standard'),
            value: conn.standardLabel,
          ),
        ],
      ),
    );
  }
}

class _NearbyCard extends ConsumerWidget {
  const _NearbyCard({required this.state});

  final WifiState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(wifiControllerProvider.notifier);
    final theme = Theme.of(context);
    final aps = state.visibleAps;
    final connectedBssid = state.connection?.bssid?.toLowerCase();

    String? noticeText() {
      switch (state.notice) {
        case ScanNotice.none:
          return null;
        case ScanNotice.requested:
          return context.tr('wifi.notice.requested');
        case ScanNotice.refusedByOs:
          return context.tr('wifi.notice.refused');
        case ScanNotice.budgetUsed:
          return context.tr('wifi.notice.budget', [
            state.retryAfterSeconds ?? '--',
          ]);
      }
    }

    final notice = noticeText();

    return SectionCard(
      title: '${context.tr('wifi.nearby')} (${aps.length})',
      trailing: FilledButton.tonalIcon(
        onPressed: state.scanning ? null : c.requestScan,
        icon: state.scanning
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.radar_rounded, size: 18),
        label: Text(context.tr('wifi.scan')),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _bandChip(
                  context,
                  c,
                  state,
                  null,
                  context.tr('wifi.filter.all'),
                ),
                _bandChip(context, c, state, WifiBand.ghz24, '2.4 GHz'),
                _bandChip(context, c, state, WifiBand.ghz5, '5 GHz'),
                _bandChip(context, c, state, WifiBand.ghz6, '6 GHz'),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                context.tr('wifi.sortBy'),
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(width: 8),
              SegmentedButton<WifiSort>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                segments: [
                  ButtonSegment(
                    value: WifiSort.signal,
                    label: Text(context.tr('wifi.sort.signal')),
                  ),
                  ButtonSegment(
                    value: WifiSort.channel,
                    label: Text(context.tr('wifi.sort.channel')),
                  ),
                  ButtonSegment(
                    value: WifiSort.name,
                    label: Text(context.tr('wifi.sort.name')),
                  ),
                ],
                selected: {state.sort},
                onSelectionChanged: (s) => c.setSort(s.first),
              ),
            ],
          ),
          if (notice != null) ...[
            const SizedBox(height: 8),
            Text(
              notice,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (aps.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                context.tr('wifi.noAps'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (var i = 0; i < aps.length; i++) ...[
              if (i > 0) const Divider(),
              _ApTile(
                ap: aps[i],
                connected:
                    connectedBssid != null &&
                    aps[i].bssid.toLowerCase() == connectedBssid,
              ),
            ],
        ],
      ),
    );
  }

  Widget _bandChip(
    BuildContext context,
    WifiController c,
    WifiState s,
    WifiBand? band,
    String label,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: s.bandFilter == band,
        label: Text(label),
        showCheckmark: false,
        onSelected: (_) => c.setBandFilter(band),
      ),
    );
  }
}

class _ApTile extends StatelessWidget {
  const _ApTile({required this.ap, required this.connected});

  final WifiScanInfo ap;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grade = SignalQuality.wifiRssi(ap.rssi);
    final details = <String>[
      ap.band.label,
      if (ap.channel != null) 'CH ${ap.channel}',
      if (ap.frequencyMhz != null) '${ap.frequencyMhz} MHz',
      if (ap.channelWidthMhz != null) '${ap.channelWidthMhz} MHz',
      if (ap.securityLabel != null) ap.securityLabel!,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SignalBars(bars: ap.bars, color: grade.color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        ap.ssid ?? context.tr('wifi.hiddenSsid'),
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontStyle: ap.ssid == null ? FontStyle.italic : null,
                        ),
                      ),
                    ),
                    if (connected) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.check_circle_rounded,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ],
                ),
                Text(
                  ap.bssid,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  details.join(' · '),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            fmtNum(ap.rssi, unit: 'dBm'),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: grade.color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelCard extends ConsumerStatefulWidget {
  const _ChannelCard({required this.state});

  final WifiState state;

  @override
  ConsumerState<_ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends ConsumerState<_ChannelCard> {
  WifiBand _band = WifiBand.ghz24;

  @override
  Widget build(BuildContext context) {
    final aps = widget.state.scan?.results ?? const <WifiScanInfo>[];
    return SectionCard(
      title: context.tr('wifi.channelGraph'),
      trailing: SegmentedButton<WifiBand>(
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        segments: const [
          ButtonSegment(value: WifiBand.ghz24, label: Text('2.4G')),
          ButtonSegment(value: WifiBand.ghz5, label: Text('5G')),
          ButtonSegment(value: WifiBand.ghz6, label: Text('6G')),
        ],
        selected: {_band},
        onSelectionChanged: (s) => setState(() => _band = s.first),
      ),
      child: ChannelGraph(
        aps: aps,
        band: _band,
        connectedBssid: widget.state.connection?.bssid,
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
                      context.tr('wifiissue.$i'),
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
