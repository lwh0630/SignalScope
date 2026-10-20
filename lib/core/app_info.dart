/// Fallback version for hosts that cannot report the installed one (Windows).
/// On Android the real `versionName` is read from the system instead (see
/// `installedVersionProvider`), because release builds take it from the git tag.
/// Keep in sync with `version:` in pubspec.yaml.
const String kAppVersion = '1.1.1';

/// GitHub repository whose published (non-draft, non-pre-release) releases are
/// offered as updates. Public information, not a secret.
const String kUpdateRepo = 'lwh0630/SignalScope';
