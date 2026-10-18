/// What the user asked for. The native listeners may still be released
/// temporarily (page hidden, app in background) while the intent stays
/// [listening].
enum MonitorStatus { listening, paused, stopped }
