/// parse/cast ค่าจาก backend/local store แบบปลอดภัย — cast ดิบ
/// (`as num?`, `as Map`) เคย throw ตอน field ผิดชนิดแล้วลากทั้ง
/// หน้า/รายการพัง ใช้ helper พวกนี้กับข้อมูลที่ไม่ได้ควบคุมเสมอ
double? toDoubleOrNull(Object? v) =>
    v is num ? v.toDouble() : double.tryParse('$v');

int? toIntOrNull(Object? v) => v is num ? v.toInt() : int.tryParse('$v');

/// Map cast แบบปลอดภัย — ผิดชนิดคืน null แทน TypeError
Map<String, dynamic>? asStringMap(Object? v) =>
    v is Map<String, dynamic> ? v : null;
