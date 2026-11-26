/// รายการแจ้งเตือนหนึ่งแถว — parse จาก `GET /notifications`
/// item `{id,title,body,createdAt ISO,read}`; `time` คือ
/// createdAt ที่ฟอร์แมตเป็นไทยแล้วสำหรับแสดง
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
