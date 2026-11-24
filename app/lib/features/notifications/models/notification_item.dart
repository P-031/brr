/// รายการแจ้งเตือนหนึ่งแถว — shape เตรียมไว้ตรงกับ
/// GET /notifications เมื่อ backend พร้อม (ตอนนี้ยังไม่มี
/// endpoint → list ว่าง)
class NotificationItem {
  const NotificationItem({
    required this.title,
    required this.body,
    required this.time,
    this.unread = false,
  });

  final String title;
  final String body;
  final String time;
  final bool unread;
}
