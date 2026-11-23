enum AppMode {
  hazardDetection('hazard_detection'),
  navigation('navigation');

  const AppMode(this.wire);

  /// Value used in data messages and the token request.
  final String wire;

  static AppMode fromWire(String? v) =>
      values.firstWhere((m) => m.wire == v, orElse: () => AppMode.hazardDetection);
}
