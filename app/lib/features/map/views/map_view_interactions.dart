part of 'map_view.dart';

/// ตรรก์ปฏิสัมพันธ์กับแผนที่ของ _MapBodyState — แยกออกจาก
/// map_view.dart เพราะไฟล์เดิมยาวกว่าพันบรรทัด; extension
/// เข้าถึง field/method private ได้เหมือนเดิมทุกอย่าง
extension _MapInteractions on _MapBodyState {
  /// Push หน้าเลือกปี/ดาวน์โหลดทับแผนที่ — unmount GoogleMap ระหว่าง
  /// ถูกคลุม (platform view กิน GPU หนัก) แล้วเอาผลลัพธ์มาแสดงต่อ
  /// `autoPrompt` = เปิดเองตอนเข้าแผนที่ — ถ้าผู้ใช้ back ออกโดย
  /// ไม่เลือก ให้ปิดแผนที่ทิ้งด้วยกลับ home (ไม่ทิ้งแผนที่เปล่าค้าง)
  Future<void> _openDownload(MapViewModel vm, {bool autoPrompt = false}) async {
    _set(() => _formOpen = true);
    final dvm = vm.createDownloadVm();
    final result = await Navigator.of(context).push<PlotDownloadResult>(
      MaterialPageRoute(builder: (_) => PlotDownloadView(viewModel: dvm)),
    );
    dvm.dispose();
    if (!mounted) return;
    _set(() => _formOpen = false);
    if (result == null) {
      if (autoPrompt) Navigator.of(context).pop();
      return;
    }
    vm.applyDownload(result.page, result.selected);
    _fitParcels(vm);
  }

  /// Push หน้า "ข้อมูลฉบับร่าง" — unmount GoogleMap ระหว่างถูกคลุม;
  /// ถ้ามีร่างถูกลบ (pop คืน true) → refetch กรอบปัจจุบันให้
  /// แปลงร่างที่ถูกลบหายจากแผนที่ทันที
  Future<void> _openDrafts(MapViewModel vm) async {
    _set(() => _formOpen = true);
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DraftsView(
          vm: vm.createDraftsVm(),
          // officer แก้ร่างต้องเห็นช่องเลือกชาวไร่เหมือนทาง home —
          // ไม่ส่ง flag จะซ่อนช่องแล้วแปลงตกเป็นของ officer เอง
          isOfficer: vm.canDrawManually,
        ),
      ),
    );
    if (!mounted) return;
    _set(() => _formOpen = false);
    if (changed != true) return;
    final r = await _controller?.getVisibleRegion();
    if (r == null || !mounted) return;
    vm.loadViewport(
      r.southwest.longitude,
      r.southwest.latitude,
      r.northeast.longitude,
      r.northeast.latitude,
    );
  }

  /// สีพื้น/เส้นของแปลง — กำหนดจุดเสี่ยงแล้ว=สีตามชนิดภัย
  /// (ชุดเดียวกับ chip ใน info sheet) / ที่เหลือ (บันทึกแล้ว
  /// รวมร่างในเครื่อง)=ม่วง; ที่กำลังวัดอยู่วาดชมพูแยกใน _polygons
  (Color, Color) _parcelColors(Parcel p, Map<String, String> risks) {
    // จุดเสี่ยงทาตามสีชนิดภัยเสมอ; ที่เหลือ (บันทึกแล้ว/ratingร่าง) = ม่วง
    final type = risks[p.id] ?? '';
    if (type.isEmpty) {
      return (AppColors.purple.withValues(alpha: 0.3), AppColors.purple);
    }
    final (_, bg, fg) = riskChipStyle(type);
    return (bg.withValues(alpha: 0.6), fg);
  }

  /// Lazily creates pin bitmaps for new draft indexes (async — markers
  /// fall back to a plain blue pin until their numbered icon is ready).
  void _ensurePinIcons(int count) {
    for (var i = _pinIcons.length + 1; i <= count; i++) {
      final n = i;
      _MapBodyState._numberedPin(n).then((icon) {
        if (mounted) _set(() => _pinIcons[n] = icon);
      });
    }
  }

  /// Tap a draft pin to arm/disarm it for moving; the next map tap
  /// relocates it. A gold ring marks the armed pin.
  void _toggleMovePin(int i) {
    _set(() {
      _movingIndex = _movingIndex == i ? null : i;
    });
    if (_movingIndex != null && _pinSelIcons[i + 1] == null) {
      final n = i + 1;
      _MapBodyState._numberedPin(n, ring: AppColors.gold).then((icon) {
        if (mounted) _set(() => _pinSelIcons[n] = icon);
      });
    }
  }

  /// Map tap: relocate an armed pin, otherwise drop a new point.
  /// Ignored while walk-measuring — pins come from the GPS stream.
  void _onMapTap(LatLng p, MapViewModel vm) {
    if (vm.walking) return;
    final point = ll.LatLng(p.latitude, p.longitude);
    final i = _movingIndex;
    if (i != null && i < vm.draft.length) {
      _set(() => _movingIndex = null);
      vm.moveDraftPoint(i, point);
    } else {
      _movingIndex = null;
      vm.addDraftPoint(point);
    }
  }

  /// Moves the camera to the user's GPS position. [auto] is used when
  /// the page opens — it suppresses error toasts and returns false so
  /// the caller can fall back to fitting the parcels.
  Future<bool> _locate(MapViewModel vm, {bool auto = false}) async {
    if (mounted) _set(() => _locating = true);
    try {
      final pos = await vm.locate();
      if (pos == null) throw 'เปิด GPS แล้วอนุญาตตำแหน่ง';
      if (!mounted) return true;
      _set(() => _locationGranted = true);
      await _controller?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 17),
      );
      return true;
    } catch (e) {
      if (mounted && !auto) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))),
        );
      }
      return false;
    } finally {
      if (mounted) _set(() => _locating = false);
    }
  }

  /// On page open: jump to the user's current position; if GPS /
  /// permission is unavailable, fit the camera around the parcels.
  Future<void> _initialLocate(MapViewModel vm) async {
    if (!await _locate(vm, auto: true)) _fitParcels(vm);
  }

  /// เปิดแผนที่พร้อมแปลงเป้าหมาย (จากกิจกรรมแปลง) — บินไปกรอบแปลง
  /// นั้นแทน GPS ของตัวเอง แล้วเด้ง sheet ข้อมูลขึ้นมาทันที
  Future<void> _focusInitialParcel(MapViewModel vm) async {
    final p = widget.focusParcel!;
    if (p.points.length >= 2) {
      var s = p.points.first.latitude, n = s;
      var w = p.points.first.longitude, e = w;
      for (final x in p.points) {
        if (x.latitude < s) s = x.latitude;
        if (x.latitude > n) n = x.latitude;
        if (x.longitude < w) w = x.longitude;
        if (x.longitude > e) e = x.longitude;
      }
      // pad เล็กน้อยกันแปลงเล็กมาก zoom จนแตก
      const pad = 0.0005;
      await _controller?.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(s - pad, w - pad),
            northeast: LatLng(n + pad, e + pad),
          ),
          60,
        ),
      );
    } else {
      final c =
          p.centerOverride ?? (p.points.isNotEmpty ? p.points.first : null);
      if (c != null) {
        await _controller?.animateCamera(
          CameraUpdate.newLatLngZoom(_MapBodyState._ll(c), 17),
        );
      }
    }
    if (mounted) _showParcelInfo(p, vm);
  }

  /// จุดกลางของ focusParcel — ใช้เป็น initialCamera ตั้งแต่เฟรมแรก
  /// จะได้ไม่กระโดดจากตำแหน่ง GPS ไปแปลงทีหลัง
  ll.LatLng? get _focusCenter {
    final p = widget.focusParcel;
    if (p == null) return null;
    if (p.centerOverride != null) return p.centerOverride;
    if (p.points.isEmpty) return null;
    var s = p.points.first.latitude, n = s;
    var w = p.points.first.longitude, e = w;
    for (final x in p.points) {
      if (x.latitude < s) s = x.latitude;
      if (x.latitude > n) n = x.latitude;
      if (x.longitude < w) w = x.longitude;
      if (x.longitude > e) e = x.longitude;
    }
    return ll.LatLng((s + n) / 2, (w + e) / 2);
  }

  /// Reset the camera bearing to north (compass button).
  void _resetNorth() {
    _controller?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: _camera.target, zoom: _camera.zoom),
      ),
    );
  }

  /// Map-type picker styled after the Google Maps layer sheet —
  /// thumbnail tiles with a gold ring on the selected one.
  void _pickMapType() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'ประเภทแผนที่',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final e in _MapBodyState._mapTypes.entries)
                    MapTypeThumb(
                      label: e.key,
                      asset: _MapBodyState._mapTypeAssets[e.key]!,
                      selected: _mapType == e.value,
                      onTap: () {
                        _set(() => _mapType = e.value);
                        Navigator.of(sheetContext).pop();
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Saved-parcel polygon set — identical [renderableParcels] list
  /// instance หมายถึงข้อมูล/กรอบ/filter ไม่เปลี่ยน ใช้ชุดเดิมได้เลย
  /// (กัน allocate Polygon ใหม่หลายพันตัวทุก GPS fix)
  Set<Polygon> _polygons(MapViewModel vm) {
    final src = vm.renderableParcels;
    final risks = vm.riskTypes;
    // rebuild เมื่อ list แปลงหรือสถานะจุดเสี่ยงเปลี่ยน
    if (!identical(src, _polySrc) || !identical(risks, _riskSrc)) {
      _polySrc = src;
      _riskSrc = risks;
      _polyCache = {
        for (final p in src)
          () {
            final (fill, stroke) = _parcelColors(p, risks);
            return Polygon(
              polygonId: PolygonId(p.id),
              points: [for (final x in p.points) _MapBodyState._ll(x)],
              fillColor: fill,
              strokeColor: stroke,
              strokeWidth: 3,
              // โหมดแผนที่แปลง — แตะแปลงเด้งข้อมูลขึ้นมา
              consumeTapEvents: widget.parcelBrowser,
              onTap: widget.parcelBrowser ? () => _showParcelInfo(p, vm) : null,
            );
          }(),
      };
    }
    return {
      ..._polyCache,
      // ขอบที่กำลังวาด — ชมพูทั้งหมดตอนเดินวัด/ปักหมุด (ตัวเดียว ถูกมาก)
      if (vm.draft.length >= 3)
        Polygon(
          polygonId: const PolygonId('draft'),
          points: [for (final x in vm.draft) _MapBodyState._ll(x)],
          fillColor: AppColors.pink.withValues(alpha: 0.2),
          strokeColor: AppColors.pink,
          strokeWidth: 3,
        ),
    };
  }

  /// แตะแปลง → sheet ข้อมูลจริงของแปลงนั้น — เปิดทันทีด้วยข้อมูลที่
  /// มีอยู่ แล้ว VM ดึง /plots/:id มาเติม meta (bulk payload ไม่ฝัง
  /// meta หนักๆ ทำให้ดาวน์โหลดเร็วขึ้นมาก) — UI อยู่ใน
  /// parcel_info_sheet.dart
  void _showParcelInfo(Parcel p, MapViewModel vm) {
    final dvm = vm.detailVmFor(context, p);
    showParcelInfoSheet(
      context,
      vm: dvm,
      onCovered: (covered) {
        if (mounted && covered != _infoSheetCovered) {
          _set(() => _infoSheetCovered = covered);
        }
      },
    ).whenComplete(() {
      // sheet ปิดแล้ว — โหลดสถานะจุดเสี่ยงใหม่ (อาจเพิ่งบันทึก)
      // เพื่อทาสี polygon ตามสถานะล่าสุด
      vm.refreshRiskTypes();
      // sheet ถูกปิดทิ้งตอนทับอยู่ — mount แผนที่กลับ
      if (mounted && _infoSheetCovered) {
        _set(() => _infoSheetCovered = false);
      }
      // vm เฉพาะแปลงสร้างใหม่ทุกครั้งที่แตะ — คืนเมื่อ flow จบ
      dvm.dispose();
    });
  }

  /// popup เลือกปีการผลิต — เปิดจากปุ่มฟิลเตอร์ข้างช่องค้นหา
  /// ปุ่มฟิลเตอร์ — ชีตตัวกรองเดียวกับหน้ากิจกรรมแปลง
  /// (ปี/เขต/ประเภทอ้อย/สถานะปลูก/กลุ่มงาน multi-select)
  Future<void> _openYearFilter(MapViewModel vm) async {
    final r = await showPlotFilterSheet(
      context,
      yearOptions: vm.years,
      zoneOptions: vm.zoneOptions,
      caneTypeOptions: vm.caneTypeOptions,
      cutGroupOptions: vm.cutGroupOptions,
      maintainGroupOptions: vm.maintainGroupOptions,
      years: {...vm.filterYears},
      zones: {...vm.filterZones},
      caneTypes: {...vm.filterCaneTypes},
      planted: {...vm.filterPlanted},
      cutGroups: {...vm.filterCutGroups},
      maintainGroups: {...vm.filterMaintainGroups},
    );
    if (r != null) {
      vm.applyFilters(
        years: r.years,
        zones: r.zones,
        caneTypes: r.caneTypes,
        planted: r.planted,
        cutGroups: r.cutGroups,
        maintainGroups: r.maintainGroups,
      );
    }
  }

  /// กดค้นบนช่องค้นหา — zoom ไปครอบผลลัพธ์ที่กรองอยู่
  /// (เช่นเจอแปลงเดียว = ซูมไปแปลงนั้นเลย)
  void _fitRenderable(MapViewModel vm) =>
      _fitPoints([for (final p in vm.renderableParcels) ...p.points]);

  /// บรรทัดรองใน dropdown แนะนำ — ชาวไร่ • พื้นที่ (ไร่-งาน-วา)
  String _suggestionSub(Parcel p) {
    final farmer = (p.owner ?? p.meta?['farmerName']?.toString() ?? '').trim();
    return [if (farmer.isNotEmpty) farmer, p.areaThai].join('  •  ');
  }

  void _fitParcels(MapViewModel vm) =>
      _fitPoints([for (final p in vm.parcels) ...p.points]);

  void _fitPoints(List<ll.LatLng> all) {
    if (all.isEmpty) return;
    var south = all.first.latitude, north = all.first.latitude;
    var west = all.first.longitude, east = all.first.longitude;
    for (final p in all) {
      if (p.latitude < south) south = p.latitude;
      if (p.latitude > north) north = p.latitude;
      if (p.longitude < west) west = p.longitude;
      if (p.longitude > east) east = p.longitude;
    }
    _controller?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south, west),
          northeast: LatLng(north, east),
        ),
        60,
      ),
    );
  }
}
