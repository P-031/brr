// ตรรก์คำนวณของฟอร์มบันทึกกิจกรรม — pure functions อยู่ชั้น
// model (MVVM) แยกจาก view เทสได้โดยไม่ต้อง mount widget

/// แปลงข้อความเป็นตัวเลข — ว่าง/ผิดรูป = 0
double rateOf(String? s) => double.tryParse(s ?? '') ?? 0;

/// ปริมาณตันรวม = ประเมิน(ตัน/ไร่) × พื้นที่ไร่ของแปลง
double totalTons(String? yieldPerRai, double areaRai) =>
    rateOf(yieldPerRai) * areaRai;

/// อ้อยเข้าหีบจริง = ตันรวม − หักตัดพันธุ์ − หักสูญเสียจากการตัด
double actualTons(
  String? yieldPerRai,
  double areaRai, {
  String? cutVarietyTons,
  String? cutLossTons,
}) =>
    totalTons(yieldPerRai, areaRai) -
    rateOf(cutVarietyTons) -
    rateOf(cutLossTons);

/// อัตราปุ๋ยรวม = อัตราฝ่ากอ + รวมอัตราทุกรอบใส่ปุ๋ย
double totalFertilizerRate(String? baseRate, Iterable<String?> roundRates) =>
    rateOf(baseRate) + roundRates.fold(0.0, (s, r) => s + rateOf(r));
