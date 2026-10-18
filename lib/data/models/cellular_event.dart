import 'cellular_info.dart';

/// Event pushed on the cellular EventChannel.
sealed class CellularEvent {
  const CellularEvent();
}

/// A new signal snapshot for one subscription.
class CellularSnapshotEvent extends CellularEvent {
  const CellularSnapshotEvent(this.info);
  final CellularInfo info;
}

/// The active subscription list changed (SIM inserted, removed or swapped).
class SimsChangedEvent extends CellularEvent {
  const SimsChangedEvent();
}
