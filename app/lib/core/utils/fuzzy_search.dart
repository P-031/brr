/// ค้นหารายการแบบใช้ร่วมทั้งแอป — ตรงก่อน (`contains`) ถ้าไม่เจอ
/// เลยค่อยหา "คำใกล้เคียง" ด้วย LCS similarity ≥ [threshold]
/// (เช่น "อ้อยตน" เจอ "อ้อยต้นฝน", พิมพ์เกิน/ตก 1-2 ตัวก็ยังเจอ)
///
/// คืน: รายการที่ตรง หรือใกล้เคียงเรียงมาก→น้อย (สูงสุด [limit] รายการ)
List<T> fuzzySearch<T>(
  Iterable<T> items,
  String query,
  String Function(T) labelOf, {
  double threshold = 0.6,
  int limit = 10,
}) {
  if (query.isEmpty) return items.toList();
  final direct = [
    for (final i in items)
      if (labelOf(i).contains(query)) i,
  ];
  if (direct.isNotEmpty) return direct;
  final scored = [
    for (final i in items) (item: i, score: _lcsRatio(query, labelOf(i))),
  ]..sort((a, b) => b.score.compareTo(a.score));
  return [
    for (final s in scored)
      if (s.score >= threshold) s.item,
  ].take(limit).toList();
}

/// สัดส่วนตัวอักษรของ [query] ที่เรียงลำดับตรงกันใน [target]
/// (longest common subsequence / ความยาว query)
double _lcsRatio(String query, String target) {
  final n = target.length;
  var prev = List<int>.filled(n + 1, 0);
  for (var i = 1; i <= query.length; i++) {
    final cur = List<int>.filled(n + 1, 0);
    for (var j = 1; j <= n; j++) {
      cur[j] = query[i - 1] == target[j - 1]
          ? prev[j - 1] + 1
          : (prev[j] > cur[j - 1] ? prev[j] : cur[j - 1]);
    }
    prev = cur;
  }
  return prev[n] / query.length;
}
