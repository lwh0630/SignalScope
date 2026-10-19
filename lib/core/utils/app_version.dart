/// Semantic version (`1.2.3`, `v1.2.3`, `1.2.3-beta.1`, `1.2.3+4`) with SemVer
/// precedence: a pre-release is older than the same version without one.
/// Build metadata (`+...`) is ignored.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(
    this.major,
    this.minor,
    this.patch, [
    this.preRelease = const [],
  ]);

  final int major;
  final int minor;
  final int patch;

  /// Dot separated pre-release identifiers; empty for a normal release.
  final List<String> preRelease;

  bool get isPreRelease => preRelease.isNotEmpty;

  static final RegExp _pattern = RegExp(
    r'^[vV]?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
  );

  /// `null` when [text] is not a version.
  static AppVersion? tryParse(String? text) {
    final m = _pattern.firstMatch((text ?? '').trim());
    if (m == null) return null;
    final major = int.tryParse(m.group(1)!);
    final minor = int.tryParse(m.group(2)!);
    final patch = int.tryParse(m.group(3)!);
    if (major == null || minor == null || patch == null) return null;
    final pre = m.group(4);
    return AppVersion(
      major,
      minor,
      patch,
      pre == null || pre.isEmpty ? const [] : pre.split('.'),
    );
  }

  @override
  int compareTo(AppVersion other) {
    var c = major.compareTo(other.major);
    if (c != 0) return c;
    c = minor.compareTo(other.minor);
    if (c != 0) return c;
    c = patch.compareTo(other.patch);
    if (c != 0) return c;
    if (preRelease.isEmpty && other.preRelease.isEmpty) return 0;
    if (preRelease.isEmpty) return 1;
    if (other.preRelease.isEmpty) return -1;
    final n = preRelease.length < other.preRelease.length
        ? preRelease.length
        : other.preRelease.length;
    for (var i = 0; i < n; i++) {
      final a = preRelease[i];
      final b = other.preRelease[i];
      final ai = int.tryParse(a);
      final bi = int.tryParse(b);
      c = switch ((ai, bi)) {
        (final x?, final y?) => x.compareTo(y),
        (_?, null) => -1, // numeric identifiers sort before alphanumeric
        (null, _?) => 1,
        _ => a.compareTo(b),
      };
      if (c != 0) return c;
    }
    return preRelease.length.compareTo(other.preRelease.length);
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease.join('.'));

  @override
  String toString() =>
      '$major.$minor.$patch${preRelease.isEmpty ? '' : '-${preRelease.join('.')}'}';
}
