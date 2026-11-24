/// ข้อมูลตัวแอปที่ใช้แสดงบน UI — แหล่งเดียวกันทั้ง footer เมนู
/// และหน้าตั้งค่า (อย่า hardcode "1.0.0" ซ้ำหลายที่ — เปลี่ยน
/// version ใน pubspec.yaml แล้วมา sync ตรงนี้)
class AppInfo {
  AppInfo._();

  /// ตรงกับ `version:` ใน pubspec.yaml (ส่วนก่อน +build)
  static const version = '1.0.0';

  /// applicationId — ใช้เปิดหน้าแอปบน Play Store
  static const packageId = 'com.brr.brr';

  static const playStoreUrl =
      'https://play.google.com/store/apps/details?id=$packageId';
  static const playStoreMarketUri = 'market://details?id=$packageId';
}
