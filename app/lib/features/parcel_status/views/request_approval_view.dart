import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/widgets/brr_app_bar.dart';
import 'package:brr/features/map/models/parcel.dart';
import 'package:brr/features/parcel_status/models/plot_request.dart';
import 'package:brr/features/parcel_status/viewmodels/parcel_status_viewmodel.dart';
import 'package:brr/core/widgets/error_retry_view.dart';

/// หน้าตัดสินคำขอ — เข้าได้เฉพาะ OFFICER (เมนูกันไว้ + backend
/// บังคับ 403 อีกชั้น) แสดงเฉพาะคำขอ "รออนุมัติ"; กดอนุมัติ/
/// ไม่อนุมัติ = PATCH /plot-requests/:id ย้อนกลับไม่ได้เลยมี
/// confirm ทุกครั้ง
class RequestApprovalView extends StatelessWidget {
  const RequestApprovalView({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) => ParcelStatusViewModel.forContext(ctx),
      child: const _Body(),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  /// id คำขอที่กำลัง PATCH — ปุ่มใบนั้น disable กันกดซ้ำ
  final Set<String> _busy = {};

  /// เรียงคำขอตามเวลาส่ง — ใหม่สุดก่อนเป็นค่าเริ่มต้น
  bool _newestFirst = true;

  String _thaiDate(DateTime? d) {
    if (d == null) return '';
    final l = d.toLocal();
    return '${l.day}/${l.month}/${l.year + 543} '
        '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _decide(
    PlotRequestEntry r,
    String status,
    ParcelStatusViewModel vm,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'ยืนยันการตัดสิน',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
        ),
        content: Text(
          '$status คำขอ "${r.kindLabel}" ของแปลง ${r.plotName}\n\n'
          'ตัดสินแล้วเปลี่ยนไม่ได้',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก', style: TextStyle(fontSize: 16)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: status == 'อนุมัติ'
                  ? AppColors.green
                  : Colors.red.shade700,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(status, style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy.add(r.id));
    try {
      await vm.decideRequest(r.id, status);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$status แล้ว — ${r.plotName}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ParcelStatusViewModel>();
    final pending = vm.pending
      ..sort((a, b) {
        final ta = a.createdAt ?? DateTime(0);
        final tb = b.createdAt ?? DateTime(0);
        return _newestFirst ? tb.compareTo(ta) : ta.compareTo(tb);
      });
    return Scaffold(
      appBar: brrAppBar('อนุมัติคำขอ'),
      body: Column(
        children: [
          // แถบเครื่องมือ — เรียงใหม่/เก่า + รีเฟรช
          // ชุดเดียวกับหน้าสถานะแปลง
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 6, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => _newestFirst = !_newestFirst),
                  icon: const Icon(Iconsax.sort, size: 24),
                  label: Text(
                    _newestFirst ? 'ใหม่สุด' : 'เก่าสุด',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: TextButton.styleFrom(foregroundColor: Colors.black87),
                ),
                IconButton(
                  iconSize: 32,
                  padding: const EdgeInsets.all(12),
                  icon: const Icon(Icons.autorenew),
                  tooltip: 'รีเฟรช',
                  onPressed: vm.load,
                ),
              ],
            ),
          ),
          Expanded(
            child: vm.loading
                ? const Center(child: CircularProgressIndicator())
                : vm.requestsError != null
                ? ErrorRetryView('โหลดรายการไม่สำเร็จ', onRetry: vm.load)
                : pending.isEmpty
                ? const Center(
                    child: Text(
                      'ไม่มีคำขอรอตัดสิน',
                      style: TextStyle(fontSize: 19),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: pending.length,
                    itemBuilder: (context, i) => _ApproveCard(
                      r: pending[i],
                      busy: _busy.contains(pending[i].id),
                      dateText: _thaiDate(pending[i].createdAt),
                      onDecide: (status) => _decide(pending[i], status, vm),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// การ์ดคำขอรอตัดสิน — แสดงรายละเอียดครบ (officer ต้องอ่านก่อน
/// ตัดสิน) + ปุ่ม อนุมัติ/ไม่อนุมัติ ใหญ่กดง่ายกลางแจ้ง
class _ApproveCard extends StatelessWidget {
  const _ApproveCard({
    required this.r,
    required this.busy,
    required this.dateText,
    required this.onDecide,
  });

  final PlotRequestEntry r;
  final bool busy;
  final String dateText;
  final void Function(String status) onDecide;

  String get _landNo => r.plotName.replaceAll(RegExp(r'\s*#\d+\s*$'), '');
  String get _plotCode =>
      RegExp(r'#\s*(\d+)\s*$').firstMatch(r.plotName)?.group(1) ?? '';

  @override
  Widget build(BuildContext context) {
    return Card(
      // เทาอ่อน + ขอบ — การ์ดต้องดูต่างจากพื้นหลังชัดเจน
      color: Colors.grey.shade200,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.grey.shade400, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                text: _landNo,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                children: [
                  if (_plotCode.isNotEmpty)
                    TextSpan(
                      text: '  #$_plotCode',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.green,
                      ),
                    ),
                ],
              ),
            ),
            if (r.productionYear != null)
              Text(
                'ปีการผลิต ${r.productionYear}',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.black87,
                  height: 1.4,
                ),
              ),
            if (r.farmerName != null)
              Text(
                'ชาวไร่ ${r.farmerName}',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.black87,
                  height: 1.4,
                ),
              ),
            if (r.areaSqm != null)
              Text(
                'พื้นที่ ${Parcel.formatThaiArea(r.areaSqm!)}',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.black87,
                  height: 1.4,
                ),
              ),
            const SizedBox(height: 4),
            if (r.requester != null)
              Text(
                'โดย ${r.requester}',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.black87,
                  height: 1.4,
                ),
              ),
            Text(
              'วัน⁠ที่ $dateText',
              style: TextStyle(
                fontSize: 18,
                color: Colors.black87,
                height: 1.4,
              ),
            ),
            const Divider(height: 20),
            _infoRow('ประเภท', r.kindLabel),
            // รายละเอียดทุกฟิลด์ของคำขอ — officer ต้องเห็นครบ
            // ก่อนกดตัดสิน (ย้อนกลับไม่ได้)
            for (final (label, value) in r.detailRows) _infoRow(label, value),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: busy ? null : () => onDecide('ไม่อนุมัติ'),
                    // Material filled — หนากว่าเส้น iconsax
                    icon: const Icon(Icons.cancel, size: 28),
                    label: const Text(
                      'ไม่อนุมัติ',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.green,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: busy ? null : () => onDecide('อนุมัติ'),
                    icon: const Icon(Icons.check_circle, size: 28),
                    label: Text(
                      busy ? 'กำลังบันทึก…' : 'อนุมัติ',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(fontSize: 18, color: Colors.black87),
          ),
        ),
        const Text(':', style: TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    ),
  );
}
