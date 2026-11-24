/// Central registry of every backend path the app calls — keep this
/// file and docs/API_CONTRACT.md in sync when adding or changing an
/// endpoint. Views/ViewModels never build paths; only the data layer
/// (ParcelService/AuthService) may reference these constants.
class ApiEndpoints {
  ApiEndpoints._();

  /// Parcel collection — list (cursor-paginated) + create.
  static const String plots = '/plots';

  /// Lightweight map payload incl. full boundary — supports gzip and
  /// `box`/`years`/`nullYear` query params.
  static const String plotsMap = '/plots/map';

  /// Distinct production years with counts for the download picker.
  static const String plotsYears = '/plots/years';

  /// Single parcel — GET detail, PATCH metadata.
  static String plot(String id) => '/plots/$id';

  /// คำขอแปลงทั้งหมดที่ผู้ใช้มองเห็น — หน้าสถานะแปลง
  static const String plotRequests = '/plot-requests';

  /// นำส่งกิจกรรมของแปลง — POST ร่างที่บันทึกในเครื่องขึ้นระบบ
  /// (backend เก็บ payload ดิบลง PlotActivity ตาม contract)
  static String plotActivities(String id) => '/plots/$id/activities';

  /// Master option lists for pickers/dropdowns — extend this payload
  /// server-side instead of hardcoding lists in the app.
  static const String metaOptions = '/meta/options';

  /// Extension officers for the caretaker picker.
  static const String officers = '/officers';

  /// Farmers under this officer's care.
  static const String farmers = '/farmers';

  /// จุดเสี่ยงภัยพิบัติล่าสุด — หน้าฉบับร่างดาวน์โหลดมาเก็บในเครื่อง
  static const String riskPoints = '/risk-points';
}
