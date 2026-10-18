import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/band_lookup.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/network_type.dart';
import '../../../core/utils/signal_quality.dart';
import '../../../data/models/cell_signal_info.dart';
import '../../../data/models/cellular_info.dart';
import '../../../data/models/platform_info.dart';
import '../../../data/models/sim_info.dart';
import '../../../shared/widgets/address_widgets.dart';
import '../../../shared/widgets/cards.dart';
import '../../../shared/widgets/monitor_bar.dart';
import '../../../shared/widgets/page_scaffold.dart';
import '../../../shared/widgets/signal_gauge.dart';
import '../../../shared/widgets/trend_chart.dart';
import '../../permissions/application/permission_controller.dart';
import '../../permissions/presentation/permission_banner.dart';
import '../application/cellular_controller.dart';

class CellularPage extends ConsumerWidget {
  const CellularPage({super.key});

  static const Set<PermGroup> _groups = {PermGroup.phone, PermGroup.location};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = ref.watch(signalPlatformProvider);
    if (!platform.isAndroid) {
      return PageScaffold(
        title: context.tr('nav.cellular'),
        children: [UnsupportedNotice(platformName: platform.name)],
      );
    }

    final state = ref.watch(cellularControllerProvider);
    final perms = ref.watch(permissionProvider);
    final sim = state.selectedSim;
    final info = state.selectedInfo;

    final children = <Widget>[
      if (PermissionBanner.isNeeded(perms, _groups))
        const PermissionBanner(groups: _groups, messageKey: 'perm.cellularWhy'),
    ];

    if (state.simsLoaded && state.sims.isEmpty) {
      children.add(_NoSimCard(phoneGranted: perms.phone.isGranted));
    } else if (sim != null) {
      children.addAll([
        _MonitorBar(state: state),
        _GaugeCard(sim: sim, info: info),
        _TrendCard(subscriptionId: sim.subscriptionId, info: info),
        _SimCard(sim: sim, info: info),
        if (info?.servingLte != null) _LteCard(cell: info!.servingLte!),
        if (info?.servingNr != null) _NrCard(cell: info!.servingNr!),
        if (info != null && info.nrMode == 'NSA' && info.servingNr == null)
          const _InfoNote(textKey: 'cellular.nsaNoNr'),
        if (info?.servingLegacy != null) _LegacyCard(cell: info!.servingLegacy!),
        if (info != null) _NeighborCard(info: info),
        if (info != null && info.issues.isNotEmpty) _IssuesCard(issues: info.issues),
      ]);
    }

    return PageScaffold(
      title: context.tr('nav.cellular'),
      header: state.sims.isEmpty ? null : _SimSelector(state: state),
      onRefresh: () => ref.read(cellularControllerProvider.notifier).refreshSims(),
      children: children,
    );
  }
}

// ---------------------------------------------------------------------------

class _SimSelector extends ConsumerWidget {
  const _SimSelector({required this.state});

  final CellularState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          for (final s in state.sims)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                selected: s.subscriptionId == state.selectedSubId,
                avatar: Icon(
                  s.isEmbedded == true ? Icons.sim_card_download_outlined : Icons.sim_card_outlined,
                  size: 18,
                ),
                label: Text(
                  '${s.slotLabel}${s.carrierName != null ? ' · ${s.carrierName}' : ''}',
                ),
                onSelected: (_) => ref
                    .read(cellularControllerProvider.notifier)
                    .selectSim(s.subscriptionId),
              ),
            ),
        ],
      ),
    );
  }
}

class _NoSimCard extends ConsumerWidget {
  const _NoSimCard({required this.phoneGranted});

  final bool phoneGranted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return SectionCard(
      child: Column(
        children: [
          Icon(Icons.sim_card_alert_outlined, size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            context.tr(phoneGranted ? 'cellular.noSim' : 'cellular.needPhonePerm'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            context.tr(phoneGranted ? 'cellular.noSimHint' : 'cellular.needPhonePermHint'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _MonitorBar extends ConsumerWidget {
  const _MonitorBar({required this.state});

  final CellularState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(cellularControllerProvider.notifier);
    return MonitorBar(
      status: state.status,
      streaming: state.streaming,
      updatedAtMs: state.selectedInfo?.timestampMs,
      onStart: c.start,
      onPause: c.pause,
      onStop: c.stop,
    );
  }
}

class _GaugeCard extends StatelessWidget {
  const _GaugeCard({required this.sim, required this.info});

  final SimInfo sim;
  final CellularInfo? info;

  @override
  Widget build(BuildContext context) {
    final reading = info?.gaugeReading;
    final isLteNr = reading != null && (reading.rat == 'LTE' || reading.rat == 'NR');
    final grade = reading == null
        ? SignalGrade.none
        : (isLteNr ? SignalQuality.rsrp(reading.dbm) : SignalQuality.legacyDbm(reading.dbm));
    final fraction = reading == null
        ? null
        : (isLteNr
            ? SignalQuality.fraction(reading.dbm, min: -140, max: -44)
            : SignalQuality.fraction(reading.dbm, min: -113, max: -51));

    final typeCode = info?.dataNetworkType ?? sim.dataNetworkType;
    final typeName = NetworkTypes.name(typeCode);
    final gen = NetworkTypes.generation(typeCode);
    final mode = info?.nrMode;
    final operator = info?.operatorName ?? sim.networkOperatorName ?? sim.carrierName;
    final roaming = info?.isRoaming ?? sim.isRoaming;
    final theme = Theme.of(context);

    return SectionCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fmtText(operator),
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      sim.slotLabel,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (typeName != null) StatusPill(text: typeName, color: theme.colorScheme.primary),
            ],
          ),
          const SizedBox(height: 8),
          SignalGauge(
            fraction: fraction,
            color: grade.color,
            valueText: reading == null ? kUnavailable : '${reading.dbm}',
            unit: reading == null ? '' : 'dBm',
            caption: reading == null
                ? null
                : '${reading.rat} ${reading.metric} · ${context.tr(grade.labelKey)}',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (gen != NetworkGeneration.none)
                StatusPill(
                  text: NetworkTypes.generationLabel(gen),
                  color: SignalColors.chartA,
                  icon: Icons.network_cell_rounded,
                ),
              if (mode != null)
                StatusPill(text: '5G $mode', color: SignalColors.chartB, icon: Icons.bolt_rounded),
              if (roaming == true)
                StatusPill(
                  text: context.tr('cellular.roaming'),
                  color: SignalColors.fair,
                  icon: Icons.travel_explore_rounded,
                ),
              if (sim.isDefaultData)
                StatusPill(
                  text: context.tr('cellular.defaultData'),
                  color: SignalColors.excellent,
                  icon: Icons.data_usage_rounded,
                ),
            ],
          ),
          if (info != null && reading == null) ...[
            const SizedBox(height: 12),
            Text(
              context.tr('cellular.noReading'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.subscriptionId, required this.info});

  final int subscriptionId;
  final CellularInfo? info;

  @override
  Widget build(BuildContext context) {
    final p = 'cell.$subscriptionId';
    final rat = info?.gaugeReading?.rat;
    final metric = info?.gaugeReading?.metric ?? 'dBm';
    return TrendCard(
      title: context.tr('common.trend'),
      series: [
        TrendSeries(
          key: '$p.primary',
          label: rat == null ? metric : '$rat $metric',
          unit: 'dBm',
          color: SignalColors.chartA,
        ),
      ],
      minY: -140,
      maxY: -40,
    );
  }
}

class _SimCard extends StatelessWidget {
  const _SimCard({required this.sim, required this.info});

  final SimInfo sim;
  final CellularInfo? info;

  @override
  Widget build(BuildContext context) {
    String yn(bool? v) => fmtBool(v, yes: context.tr('common.yes'), no: context.tr('common.no'));
    final simState = sim.simState == null ? null : context.tr('simstate.${sim.simState}');
    final dataState = sim.dataState == null ? null : context.tr('datastate.${sim.dataState}');
    final service = info?.serviceState == null ? null : context.tr('servicestate.${info!.serviceState}');
    final mcc = sim.mcc;
    final mnc = sim.mnc;
    final regNet = info?.networkOperator ?? sim.networkOperator;
    final voiceType = NetworkTypes.name(info?.voiceNetworkType ?? sim.voiceNetworkType);
    final dataType = NetworkTypes.name(info?.dataNetworkType ?? sim.dataNetworkType);

    return SectionCard(
      title: context.tr('cellular.simInfo'),
      child: Column(
        children: [
          InfoRow(label: context.tr('cellular.slot'), value: sim.slotLabel),
          InfoRow(label: context.tr('cellular.carrier'), value: sim.carrierName ?? sim.displayName),
          InfoRow(label: context.tr('cellular.simState'), value: simState),
          InfoRow(label: 'MCC', value: mcc, note: context.tr('cellular.mccNote')),
          InfoRow(label: 'MNC', value: mnc, note: context.tr('cellular.mncNote')),
          InfoRow(label: context.tr('cellular.countryIso'), value: sim.countryIso?.toUpperCase()),
          InfoRow(label: context.tr('cellular.simOperator'), value: sim.simOperator),
          InfoRow(
            label: context.tr('cellular.registeredNetwork'),
            value: regNet == null
                ? null
                : '${info?.operatorName ?? sim.networkOperatorName ?? ''} ($regNet)'.trim(),
          ),
          InfoRow(label: context.tr('cellular.serviceState'), value: service),
          InfoRow(label: context.tr('cellular.dataNetworkType'), value: dataType),
          InfoRow(label: context.tr('cellular.voiceNetworkType'), value: voiceType),
          InfoRow(label: context.tr('cellular.roaming'), value: yn(info?.isRoaming ?? sim.isRoaming)),
          InfoRow(label: context.tr('cellular.defaultData'), value: yn(sim.isDefaultData)),
          InfoRow(label: context.tr('cellular.dataEnabled'), value: yn(sim.isDataEnabled)),
          InfoRow(label: context.tr('cellular.dataState'), value: dataState),
          InfoRow(
            label: context.tr('cellular.simType'),
            value: sim.isEmbedded == null
                ? null
                : context.tr(sim.isEmbedded! ? 'cellular.esim' : 'cellular.physicalSim'),
          ),
          if (info?.hasDataNetwork != null) ...[
            const Divider(height: 20),
            if (info!.hasDataNetwork == true) ...[
              CopyableInfoRow(label: context.tr('addr.ipv4'), value: info!.ipv4, note: context.tr('addr.copyHint')),
              CopyableInfoRow(
                label: context.tr('addr.ipv6'),
                value: info!.ipv6.isEmpty ? null : info!.ipv6.join('\n'),
                note: info!.ipv6.isEmpty ? context.tr('addr.noIpv6') : null,
              ),
              if (info!.ipv6LinkLocal.isNotEmpty)
                CopyableInfoRow(
                  label: context.tr('addr.ipv6LinkLocal'),
                  value: info!.ipv6LinkLocal.join('\n'),
                  note: context.tr('addr.ipv6LinkNote'),
                ),
            ] else
              InfoRow(
                label: context.tr('addr.ipv4'),
                value: null,
                note: '${context.tr('addr.noDataNetwork')} - ${context.tr('addr.noDataNetworkNote')}',
              ),
          ],
        ],
      ),
    );
  }
}

String? _bandText(BuildContext context, List<int> bands, BandSource? source, String prefix) {
  if (bands.isEmpty) return null;
  return bands.map((b) => '$prefix$b').join(' / ');
}

String? _bandNote(BuildContext context, List<int> bands, BandSource? source) {
  if (bands.isEmpty) return null;
  return source == BandSource.derived
      ? context.tr('cellular.bandDerived')
      : context.tr('cellular.bandReported');
}

class _LteCard extends StatelessWidget {
  const _LteCard({required this.cell});

  final LteSignalInfo cell;

  @override
  Widget build(BuildContext context) {
    final dlMhz = BandLookup.lteDlFrequencyMhz(cell.earfcn);
    final plmn = (cell.mcc != null && cell.mnc != null) ? '${cell.mcc}-${cell.mnc}' : null;
    return SectionCard(
      title: context.tr('cellular.lteTitle'),
      trailing: cell.source == CellDataSource.signalStrength
          ? StatusPill(text: context.tr('cellular.measurementOnly'), color: SignalColors.fair)
          : null,
      child: Column(
        children: [
          InfoRow(
            label: 'RSRP',
            value: fmtNum(cell.rsrp, unit: 'dBm'),
            valueColor: SignalQuality.rsrp(cell.rsrp).color,
            emphasize: true,
          ),
          InfoRow(label: 'RSRQ', value: fmtNum(cell.rsrq, unit: 'dB')),
          InfoRow(label: 'RSSI', value: fmtNum(cell.rssi, unit: 'dBm')),
          InfoRow(label: 'SINR (RSSNR)', value: fmtNum(cell.rssnr, unit: 'dB')),
          InfoRow(label: 'CQI', value: fmtNum(cell.cqi)),
          InfoRow(label: 'Timing Advance', value: fmtNum(cell.timingAdvance)),
          InfoRow(label: 'PCI', value: fmtNum(cell.pci)),
          InfoRow(label: 'TAC', value: fmtNum(cell.tac)),
          InfoRow(label: 'ECI / CI', value: fmtNum(cell.ci)),
          InfoRow(
            label: 'eNodeB ID',
            value: fmtNum(cell.enbId),
            note: cell.enbId == null ? null : context.tr('cellular.enbNote'),
          ),
          InfoRow(
            label: context.tr('cellular.localCellId'),
            value: fmtNum(cell.localCellId),
            note: cell.localCellId == null ? null : context.tr('cellular.localCellNote'),
          ),
          InfoRow(label: 'EARFCN', value: fmtNum(cell.earfcn)),
          InfoRow(
            label: context.tr('cellular.dlFrequency'),
            value: dlMhz == null ? null : fmtNum(dlMhz, unit: 'MHz', decimals: 1),
            note: dlMhz == null ? null : context.tr('cellular.freqDerived'),
          ),
          InfoRow(
            label: context.tr('cellular.band'),
            value: _bandText(context, cell.bands, cell.bandSource, 'B'),
            note: _bandNote(context, cell.bands, cell.bandSource),
          ),
          InfoRow(
            label: context.tr('cellular.bandwidth'),
            value: cell.bandwidthKhz == null ? null : fmtNum(cell.bandwidthKhz! / 1000, unit: 'MHz', decimals: 1),
          ),
          InfoRow(label: 'PLMN', value: plmn),
        ],
      ),
    );
  }
}

class _NrCard extends StatelessWidget {
  const _NrCard({required this.cell});

  final NrSignalInfo cell;

  @override
  Widget build(BuildContext context) {
    final freq = BandLookup.nrFrequencyMhz(cell.nrarfcn);
    final plmn = (cell.mcc != null && cell.mnc != null) ? '${cell.mcc}-${cell.mnc}' : null;
    return SectionCard(
      title: context.tr('cellular.nrTitle'),
      trailing: cell.source == CellDataSource.signalStrength
          ? StatusPill(text: context.tr('cellular.measurementOnly'), color: SignalColors.fair)
          : null,
      child: Column(
        children: [
          InfoRow(
            label: 'SS-RSRP',
            value: fmtNum(cell.ssRsrp, unit: 'dBm'),
            valueColor: SignalQuality.rsrp(cell.ssRsrp).color,
            emphasize: true,
          ),
          InfoRow(label: 'SS-RSRQ', value: fmtNum(cell.ssRsrq, unit: 'dB')),
          InfoRow(label: 'SS-SINR', value: fmtNum(cell.ssSinr, unit: 'dB')),
          InfoRow(label: 'CSI-RSRP', value: fmtNum(cell.csiRsrp, unit: 'dBm')),
          InfoRow(label: 'CSI-RSRQ', value: fmtNum(cell.csiRsrq, unit: 'dB')),
          InfoRow(label: 'CSI-SINR', value: fmtNum(cell.csiSinr, unit: 'dB')),
          InfoRow(label: 'NRARFCN', value: fmtNum(cell.nrarfcn)),
          InfoRow(
            label: context.tr('cellular.nrFrequency'),
            value: freq == null ? null : fmtNum(freq, unit: 'MHz', decimals: 2),
            note: freq == null ? null : context.tr('cellular.freqDerived'),
          ),
          InfoRow(
            label: context.tr('cellular.band'),
            value: _bandText(context, cell.bands, cell.bandSource, 'n'),
            note: _bandNote(context, cell.bands, cell.bandSource),
          ),
          InfoRow(label: 'PCI', value: fmtNum(cell.pci)),
          InfoRow(label: 'TAC', value: fmtNum(cell.tac)),
          InfoRow(label: 'NCI', value: fmtNum(cell.nci)),
          InfoRow(label: 'PLMN', value: plmn),
        ],
      ),
    );
  }
}

class _LegacyCard extends StatelessWidget {
  const _LegacyCard({required this.cell});

  final LegacyCellInfo cell;

  @override
  Widget build(BuildContext context) {
    final isGsm = cell.rat == 'GSM';
    return SectionCard(
      title: '${cell.rat} · ${cell.rat == 'GSM' ? '2G' : '3G'}',
      child: Column(
        children: [
          InfoRow(
            label: 'RSSI',
            value: fmtNum(cell.dbm, unit: 'dBm'),
            valueColor: SignalQuality.legacyDbm(cell.dbm).color,
            emphasize: true,
          ),
          InfoRow(label: context.tr('cellular.level'), value: fmtNum(cell.level)),
          InfoRow(label: 'CID', value: fmtNum(cell.cid)),
          InfoRow(label: 'LAC', value: fmtNum(cell.lac)),
          InfoRow(label: isGsm ? 'ARFCN' : 'UARFCN', value: fmtNum(cell.channel)),
          if (isGsm) InfoRow(label: 'BSIC', value: fmtNum(cell.bsic)) else InfoRow(label: 'PSC', value: fmtNum(cell.psc)),
        ],
      ),
    );
  }
}

class _NeighborCard extends StatelessWidget {
  const _NeighborCard({required this.info});

  final CellularInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lte = info.neighborLte;
    final nr = info.neighborNr;
    final legacy = info.neighborLegacy;
    final empty = lte.isEmpty && nr.isEmpty && legacy.isEmpty;

    Widget line(String title, String detail, Color color) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: theme.textTheme.bodyMedium)),
              Text(detail,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
            ],
          ),
        );

    return SectionCard(
      title: context.tr('cellular.neighbors'),
      child: empty
          ? Text(
              context.tr('cellular.noNeighbors'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          : Column(
              children: [
                for (final c in lte)
                  line(
                    'LTE  PCI ${fmtNum(c.pci)} · EARFCN ${fmtNum(c.earfcn)}',
                    fmtNum(c.rsrp, unit: 'dBm'),
                    SignalQuality.rsrp(c.rsrp).color,
                  ),
                for (final c in nr)
                  line(
                    'NR  PCI ${fmtNum(c.pci)} · NRARFCN ${fmtNum(c.nrarfcn)}',
                    fmtNum(c.ssRsrp ?? c.csiRsrp, unit: 'dBm'),
                    SignalQuality.rsrp(c.ssRsrp ?? c.csiRsrp).color,
                  ),
                for (final c in legacy)
                  line(
                    '${c.rat}  CID ${fmtNum(c.cid)} · LAC ${fmtNum(c.lac)}',
                    fmtNum(c.dbm, unit: 'dBm'),
                    SignalQuality.legacyDbm(c.dbm).color,
                  ),
              ],
            ),
    );
  }
}

class _InfoNote extends StatelessWidget {
  const _InfoNote({required this.textKey});

  final String textKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(context.tr(textKey), style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _IssuesCard extends StatelessWidget {
  const _IssuesCard({required this.issues});

  final List<String> issues;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      title: context.tr('cellular.notes'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final i in issues)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(child: Text(context.tr('issue.$i'), style: theme.textTheme.bodySmall)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
