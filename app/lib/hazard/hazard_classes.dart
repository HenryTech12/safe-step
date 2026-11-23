/// SafeStep hazard classes (ml/classes.yaml). Order = fine-tuned model class ids.
enum Severity { minor, critical }

enum HazardClass {
  openGutter('open_gutter', Severity.critical),
  pothole('pothole', Severity.minor),
  openManhole('open_manhole', Severity.critical),
  kerbDrop('kerb_drop', Severity.minor),
  okada('okada', Severity.critical),
  vehicle('vehicle', Severity.minor),
  person('person', Severity.minor),
  pole('pole', Severity.minor),
  traderTable('trader_table', Severity.minor),
  constructionDebris('construction_debris', Severity.minor);

  const HazardClass(this.wire, this.severity);
  final String wire;
  final Severity severity;

  bool get critical => severity == Severity.critical;

  static HazardClass? fromWire(String s) {
    for (final c in values) {
      if (c.wire == s) return c;
    }
    return null;
  }
}

/// Placeholder mapping from stock COCO ids to SafeStep classes. COCO has no gutters,
/// manholes, potholes or kerbs; those need the fine-tuned model.
const Map<int, HazardClass> cocoToSafeStep = {
  0: HazardClass.person,
  1: HazardClass.vehicle, // bicycle
  2: HazardClass.vehicle, // car
  3: HazardClass.okada, // motorcycle: in Nigerian streets, almost always an okada
  5: HazardClass.vehicle, // bus
  7: HazardClass.vehicle, // truck
  9: HazardClass.pole, // traffic light
  10: HazardClass.pole, // fire hydrant
  11: HazardClass.pole, // stop sign
  12: HazardClass.pole, // parking meter
  13: HazardClass.traderTable, // bench
  60: HazardClass.traderTable, // dining table
  56: HazardClass.constructionDebris, // chair (stand-in for clutter on the walkway)
};

/// Maps a model class id to a SafeStep class, picking the scheme from the class count.
HazardClass? classForModel(int classId, int numClasses) {
  if (numClasses == HazardClass.values.length) {
    return classId >= 0 && classId < numClasses ? HazardClass.values[classId] : null;
  }
  return cocoToSafeStep[classId];
}
