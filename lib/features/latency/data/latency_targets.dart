import 'dart:io';

/// Which card a target belongs to.
enum LatencyGroup { mainland, international, custom }

/// A host to measure. [port] is the TCP port used for the handshake.
class LatencyTarget {
  const LatencyTarget({
    required this.id,
    required this.name,
    required this.host,
    this.port = 443,
    required this.group,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final LatencyGroup group;

  bool get isCustom => group == LatencyGroup.custom;

  /// `host` or `host:port` (IPv6 literals in brackets).
  String get displayAddress {
    final h = host.contains(':') ? '[$host]' : host;
    return port == 443 ? h : '$h:$port';
  }

  /// Text stored in the settings for a custom target.
  String get storageKey => '${host.contains(':') ? '[$host]' : host}:$port';

  /// Built-in popular sites. Brand names are shown as they are.
  static const List<LatencyTarget> mainland = [
    LatencyTarget(
      id: 'cn-baidu',
      name: 'Baidu 百度',
      host: 'www.baidu.com',
      group: LatencyGroup.mainland,
    ),
    LatencyTarget(
      id: 'cn-qq',
      name: 'Tencent QQ 腾讯',
      host: 'www.qq.com',
      group: LatencyGroup.mainland,
    ),
    LatencyTarget(
      id: 'cn-taobao',
      name: 'Taobao 淘宝',
      host: 'www.taobao.com',
      group: LatencyGroup.mainland,
    ),
    LatencyTarget(
      id: 'cn-bilibili',
      name: 'Bilibili 哔哩哔哩',
      host: 'www.bilibili.com',
      group: LatencyGroup.mainland,
    ),
    LatencyTarget(
      id: 'cn-163',
      name: 'NetEase 网易',
      host: 'www.163.com',
      group: LatencyGroup.mainland,
    ),
    LatencyTarget(
      id: 'cn-jd',
      name: 'JD 京东',
      host: 'www.jd.com',
      group: LatencyGroup.mainland,
    ),
  ];

  static const List<LatencyTarget> international = [
    LatencyTarget(
      id: 'us-google',
      name: 'Google',
      host: 'www.google.com',
      group: LatencyGroup.international,
    ),
    LatencyTarget(
      id: 'us-cloudflare',
      name: 'Cloudflare',
      host: 'www.cloudflare.com',
      group: LatencyGroup.international,
    ),
    LatencyTarget(
      id: 'us-github',
      name: 'GitHub',
      host: 'github.com',
      group: LatencyGroup.international,
    ),
    LatencyTarget(
      id: 'us-microsoft',
      name: 'Microsoft',
      host: 'www.microsoft.com',
      group: LatencyGroup.international,
    ),
    LatencyTarget(
      id: 'us-amazon',
      name: 'Amazon',
      host: 'www.amazon.com',
      group: LatencyGroup.international,
    ),
    LatencyTarget(
      id: 'us-apple',
      name: 'Apple',
      host: 'www.apple.com',
      group: LatencyGroup.international,
    ),
  ];

  static const List<LatencyTarget> builtIn = [...mainland, ...international];

  static const int maxCustom = 20;

  static final RegExp _hostName = RegExp(
    r'^(?=.{1,253}$)([a-z0-9_]([a-z0-9_-]{0,61}[a-z0-9_])?)(\.[a-z0-9_]([a-z0-9_-]{0,61}[a-z0-9_])?)*$',
    caseSensitive: false,
  );

  /// Parses user input: `host`, `host:port`, `[v6]:port`, or an `http(s)://` URL.
  /// Returns `null` when the text is not a usable address. A bare host or an
  /// `https://` URL uses port 443, `http://` uses 80.
  static LatencyTarget? parseCustom(String input) {
    final text = input.trim();
    if (text.isEmpty || text.contains(RegExp(r'\s'))) return null;
    final hasScheme = text.contains('://');
    final uri = Uri.tryParse(hasScheme ? text : 'https://$text');
    if (uri == null) return null;
    if (hasScheme && uri.scheme != 'http' && uri.scheme != 'https') return null;

    var host = uri.host;
    if (host.isEmpty) return null;
    if (host.startsWith('[') && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }
    final isIp = InternetAddress.tryParse(host) != null;
    if (!isIp &&
        (!_hostName.hasMatch(host) ||
            !host.contains('.') && host != 'localhost')) {
      return null;
    }

    final defaultPort = hasScheme && uri.scheme == 'http' ? 80 : 443;
    final port = uri.hasPort ? uri.port : defaultPort;
    if (port < 1 || port > 65535) return null;

    host = host.toLowerCase();
    final target = LatencyTarget(
      id: 'custom:$host:$port',
      name: host,
      host: host,
      port: port,
      group: LatencyGroup.custom,
    );
    return target;
  }
}
