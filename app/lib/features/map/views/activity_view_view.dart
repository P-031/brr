import 'dart:io';

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:brr/core/theme/app_theme.dart';
import 'package:brr/core/widgets/brr_app_bar.dart';
import 'package:brr/features/map/viewmodels/parcel_detail_viewmodel.dart';

/// หน้า "ข้อมูลกิจกรรม" — ดูข้อมูลที่บันทึกไว้อย่างเดียว
/// (อ่านอย่างเดียว ไม่มีช่องกรอก/ปุ่มบันทึก)
/// เปิดจากการ์ดในหน้าประวัติบันทึกกิจกรรม
class ActivityViewView extends StatelessWidget {
  const ActivityViewView({super.key, required this.vm, required this.activity});

  final ParcelDetailViewModel vm;
  final Map<String, dynamic> activity;

  static String _fmtThaiDate(String? iso) {
    final d = DateTime.tryParse('$iso');
    if (d == null) return '—';
    return '${d.day}/${d.month}/${d.year + 543}';
  }

  static String _fmtThaiTime(String? iso) {
    final d = DateTime.tryParse('$iso');
    if (d == null) return '—';
    return '${d.day}/${d.month}/${d.year + 543} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  String _s(String k) => '${activity[k] ?? ''}'.trim();

  bool? _b(String k) => activity[k] is bool ? activity[k] as bool : null;

  String _yesNo(bool? v, [String yes = 'ทำ', String no = 'ไม่ทำ']) => v == null
      ? '—'
      : v
      ? yes
      : no;

  /// แถว "label : value" ชิดซ้าย — ซ่อนถ้า value ว่าง
  /// หน่วยซ้ำไม่แสดง (ค่าบันทึกอาจต่อท้ายหน่วยมาแล้ว เช่น '60%')
  Widget _row(String label, String value, {String? unit}) {
    if (value.isEmpty) return const SizedBox.shrink();
    final suffix = unit != null && !value.endsWith(unit) ? ' $unit' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Text.rich(
        TextSpan(
          text: '$label : ',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
          children: [
            TextSpan(
              text: '$value$suffix',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// หัวย่อยในการ์ด — ตรงกับชื่อ section ในหน้าบันทึก
  Widget _subHead(String text) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 4),
    child: Text(
      text,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
    ),
  );

  Widget _card(String title, List<Widget> rows) {
    final visible = rows.where((w) => w is! SizedBox).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.green,
            ),
          ),
          const Divider(height: 20),
          ...rows,
        ],
      ),
    );
  }

  Widget _photos() {
    final rawPhotos = activity['photos'];
    final photos = rawPhotos is List ? rawPhotos : const [];
    if (photos.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ภาพถ่าย ${photos.length} ใบ',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.green,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final p in photos)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    File('$p'),
                    width: 100,
                    height: 100,
                    cacheWidth: 200,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 100,
                      height: 100,
                      color: Colors.black12,
                      child: const Icon(
                        Iconsax.gallery_slash,
                        color: Colors.black38,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rawRounds = activity['fertilizerRounds'];
    final rounds = rawRounds is List ? rawRounds : const [];
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      appBar: brrAppBar('ข้อมูลกิจกรรม'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        children: [
          // สรุปหัวการ์ด — ผู้บันทึก + เวลา
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row('บันทึกเมื่อ', _fmtThaiTime('${activity['createdAt']}')),
                _row(
                  'สถานะ',
                  activity['detailPending'] == true
                      ? 'รอกรอกรายละเอียด'
                      : switch ('${activity['submitStatus'] ?? 'pending'}') {
                          'sent' => 'นำส่งแล้ว',
                          'failed' => 'นำส่งไม่สำเร็จ',
                          'queued' => 'รอส่งอัตโนมัติเมื่อออนไลน์',
                          _ => 'บันทึกเรียบร้อย',
                        },
                ),
                _row(
                  'บันทึกโดย',
                  [
                    _s('recordedBy'),
                    if (_s('recordedByRole') == 'officer')
                      '(นักส่งเสริม)'
                    else if (_s('recordedByRole') == 'farmer')
                      '(ชาวไร่)',
                  ].where((x) => x.isNotEmpty).join(' '),
                ),
              ],
            ),
          ),
          _card('วันที่ปลูก', [
            _row('วันที่ปลูก', _fmtThaiDate(_s('plantedAt'))),
          ]),
          _card('กลุ่มสร้างอ้อย (กลุ่มบำรุง)', [
            _row('กลุ่ม', _s('caneGroup')),
          ]),
          _card('การใช้ยาคุม', [_row('ยาคุม', _s('herbicideUsed'))]),
          _card('เลือกกลุ่มตัดอ้อย', [
            _row('ชาวไร่', _s('harvestGroupFarmer')),
          ]),
          _card('ฝ่ากอ', [
            _row('อัตราการใส่ปุ๋ย', _s('fertilizerRate'), unit: 'กก./ไร่'),
            _row(
              'สูตร NPK',
              [
                if (_s('npkN').isNotEmpty) 'N:${_s('npkN')}',
                if (_s('npkP').isNotEmpty) 'P:${_s('npkP')}',
                if (_s('npkK').isNotEmpty) 'K:${_s('npkK')}',
              ].join(' '),
            ),
          ]),
          _card('ใช้ปุ๋ยตามปริมาณผลผลิตที่ต้องการ', [
            _row('ค่าปุ๋ย MPI', _yesNo(_b('mpiApplied'))),
            for (var i = 0; i < rounds.length; i++)
              ...() {
                final m = rounds[i] is Map
                    ? Map<String, dynamic>.from(rounds[i] as Map)
                    : <String, dynamic>{};
                String v(String k) => '${m[k] ?? ''}'.trim();
                final npk = v('npk').isNotEmpty
                    ? v('npk')
                    : [
                        if (v('npkN').isNotEmpty) 'N:${v('npkN')}',
                        if (v('npkP').isNotEmpty) 'P:${v('npkP')}',
                        if (v('npkK').isNotEmpty) 'K:${v('npkK')}',
                      ].join(' ');
                return [
                  _subHead('รอบที่ ${i + 1}'),
                  _row('วันที่ใส่', _fmtThaiDate(v('date'))),
                  _row('อัตรา', v('rate'), unit: 'กก./ไร่'),
                  _row('สูตรปุ๋ย', npk),
                ];
              }(),
          ]),
          _card('ใส่ปุ๋ยอินทรีย์ (>500 กก/ไร่)', [
            _row('ชนิดปุ๋ยอินทรีย์', _s('organicFertilizerType')),
            _row('อัตรา', _s('organicRate'), unit: 'กก./ไร่'),
            _row('วันที่ใส่', _fmtThaiDate(_s('organicDate'))),
          ]),
          _card('ใส่โดโลไมท์ (50 - 100 กก/ไร่)', [
            _row('อัตรา', _s('dolomiteRate'), unit: 'กก./ไร่'),
            _row('วันที่ใส่', _fmtThaiDate(_s('dolomiteDate'))),
          ]),
          _card('คุมวัชพืช ต้องไม่มีวัชพืช', [
            _row(
              'วัชพืช',
              _yesNo(_b('weedPresent'), 'มีวัชพืช', 'ไม่มีวัชพืช'),
            ),
          ]),
          _card('ไถระเบิดดินดาน (ลึก > 40 ซม.)', [
            _row(
              'ไถระเบิดดินดาน',
              _yesNo(_b('subsoiled'), 'ทำแล้ว', 'ยังไม่ทำ'),
            ),
            _row('ความลึก', _s('subsoilDepth'), unit: 'ซม.'),
          ]),
          _card('พูนโคน', [_row('พูนโคน', _yesNo(_b('hilled')))]),
          _card('การงอก', [
            _row('เปอร์เซ็นต์งอก', _s('germinationPercent'), unit: '%'),
          ]),
          _card('โรค', [
            _row('โรค', _yesNo(_b('diseasePresent'), 'มีโรค', 'ไม่มีโรค')),
            _row('ชนิดโรค', _s('diseaseType')),
            _row('ระบาด', _s('diseaseSpread'), unit: '%'),
            _row(
              'การจัดการ',
              _yesNo(_b('diseaseManaged'), 'จัดการแล้ว', 'ยังไม่จัดการ'),
            ),
          ]),
          _card('แมลง', [
            _row('แมลง', _yesNo(_b('pestPresent'), 'มีแมลง', 'ไม่มีแมลง')),
            _row('ชนิดแมลง', _s('pestType')),
            _row('ระบาด', _s('pestSpread'), unit: '%'),
            _row('ความเสียหาย', _s('pestDamage'), unit: '%'),
            _row(
              'การจัดการ',
              _yesNo(_b('pestManaged'), 'จัดการแล้ว', 'ยังไม่จัดการ'),
            ),
          ]),
          _card('สูญเสียในแปลง', [
            _row('สาเหตุ', _s('lossReason')),
            _row('สูญเสียรวม', _s('lossAreaRai'), unit: 'ไร่'),
            _row('ประเมิน', _s('yieldEstimate'), unit: 'ตัน/ไร่'),
            _row('ปริมาณตันรวม', _s('totalTons'), unit: 'ตัน'),
          ]),
          _card('สูญเสียจากการตัด และหักพันธุ์', [
            _row('หักตัดพันธุ์รวม', _s('cutVarietyDeduction'), unit: 'ตัน'),
            _row('หักสูญเสียจากการตัด', _s('cutLossKgPerRai'), unit: 'กก./ไร่'),
            _row('หักสูญเสียจากการตัด', _s('cutLossTons'), unit: 'ตัน'),
            _row('สาเหตุหักสูญเสีย', _s('cutLossReason')),
            _row('อ้อยเข้าหีบจริง', _s('actualHarvestTons'), unit: 'ตัน'),
          ]),
          _card('อ้อยพันธุ์', [
            _row('เป็นอ้อยพันธุ์', _yesNo(_b('seedCane'), 'ใช่', 'ไม่ใช่')),
            _row('รายละเอียด', _s('seedCaneNote')),
          ]),
          _card('ข้อเสนอแนะ / ตรวจสอบ', [_row('ข้อเสนอแนะ', _s('suggestion'))]),
          _photos(),
        ],
      ),
    );
  }
}
