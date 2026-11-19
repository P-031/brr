/// Result returned when the measurement form is saved — model
/// ของ flow วัดแปลง (แยกออกจาก view เพราะ DraftsViewModel
/// ใช้รับค่าตอนแก้ร่างด้วย)
class MeasurementResult {
  const MeasurementResult({
    required this.name,
    this.productionYear,
    this.officerName,
    this.project,
    this.farmerName,
    this.farmerId,
    this.caneGroup,
    this.zone,
    this.province,
    this.district,
    this.subdistrict,
    this.village,
    this.rootNo,
    this.sequenceNo,
    this.prevPlotNo,
    this.caneType,
    this.caneVariety,
    this.ownership,
    this.terrain,
    this.hasLoss,
    this.lossRai,
    this.targetYield,
    this.note,
    this.photos = const [],
    this.draft = false,
  });

  final String name;
  final String? productionYear;
  final String? officerName;
  final String? project;
  final String? farmerName;
  final String? farmerId;
  final String? caneGroup;
  final String? zone;
  final String? province;
  final String? district;
  final String? subdistrict;
  final String? village;
  final String? rootNo;
  final String? sequenceNo;
  final String? prevPlotNo;
  final String? caneType;
  final String? caneVariety;
  final String? ownership;
  final String? terrain;
  final String? hasLoss;
  final String? lossRai;
  final String? targetYield;
  final String? note;
  final List<String> photos;
  final bool draft;
}
