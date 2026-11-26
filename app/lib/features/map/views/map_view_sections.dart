part of 'map_view.dart';

/// overlay ลอยบนแผนที่ใน build — แยกเป็น builder ย่อยเพราะ
/// build เดิมยาว ~600 บรรทัดอ่านยาก; เงื่อนไข if ยังอยู่
/// ใน build ให้เห็นลำดับ layer ของ stack ชัดเจนเหมือนเดิม
extension _MapViewSections on _MapBodyState {
  Widget _viewportErrorBar(MapViewModel vm) =>
    Positioned(
      top: MediaQuery.of(context).padding.top + 68,
      left: 16,
      right: 16,
      child: GestureDetector(
        onTap: vm.retryViewport,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3E0),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFE65100),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Iconsax.warning_2,
                size: 18,
                color: Color(0xFFE65100),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'โหลดแปลงบริเวณนี้ไม่สำเร็จ — แตะเพื่อลองใหม่',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFE65100),
                  ),
                ),
              ),
              const Icon(
                Icons.autorenew,
                size: 18,
                color: Color(0xFFE65100),
              ),
            ],
          ),
        ),
      ),
    );

  Widget _backButton() =>
                    Positioned(
    top: MediaQuery.of(context).padding.top + 12,
    left: 16,
    child: GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: const MapButton(
        icon: Iconsax.arrow_left,
        loading: false,
      ),
    ),
                    );

  Widget _searchBar(MapViewModel vm) =>
                    Positioned(
    top: MediaQuery.of(context).padding.top + 12,
    left: 84,
    right: 16,
    child: Row(
      children: [
        Expanded(
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 6,
                ),
              ],
            ),
            child: Row(
              children: [
                // แตะแว่นขยาย = ค้นหา/zoom ผลลัพธ์
                // เหมือนกดค้นบนคีย์บอร์ด
                GestureDetector(
                  onTap: () => _fitRenderable(vm),
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(
                      Iconsax.search_normal,
                      size: 24,
                      color: AppColors.green,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    focusNode: _searchFocus,
                    style: const TextStyle(fontSize: 16),
                    onChanged: (q) {
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(
                        const Duration(milliseconds: 300),
                        () => context
                            .read<MapViewModel>()
                            .setSearchQuery(q),
                      );
                    },
                    // กดค้น = zoom ไปกรอบผลลัพธ์
                    onSubmitted: (_) => _fitRenderable(vm),
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      hintText: 'ค้นหาแปลง / ชาวไร่ / รูท',
                      hintStyle: TextStyle(
                        fontSize: 15,
                        color: Colors.black38,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (vm.searchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchCtrl.clear();
                      vm.setSearchQuery('');
                    },
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Iconsax.close_circle,
                        size: 28,
                        color: Colors.black38,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // ปุ่มฟิลเตอร์ — เลือกปีการผลิต; จุดทอง =
        // กำลังกรองอยู่ (draft แสดงเสมอ)
        if (vm.years.isNotEmpty) ...[
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => _openYearFilter(vm),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const MapButton(
                  icon: Iconsax.setting_4,
                  loading: false,
                ),
                if (vm.activeFilterCount > 0)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    ),
                    );

  Widget _controlButtons(MapViewModel vm) =>
                    Positioned(
    right: 16,
    bottom: widget.parcelBrowser
        ? 16
        : vm.drawing
        ? (vm.walking ? 226 : 166)
        : 116,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // เข็มทิศสไตล์ Google Maps — โผล่เฉพาะตอน
        // แผนที่ถูกหมุน เข็มแดงชี้เหนือจริงตาม bearing
        if (_camera.bearing.abs() > 0.5)
          GestureDetector(
            onTap: _resetNorth,
            child: CompassButton(bearing: _camera.bearing),
          ),
        if (_camera.bearing.abs() > 0.5)
          const SizedBox(height: 10),
        GestureDetector(
          onTap: _locating ? null : () => _locate(vm),
          child: MapButton(
            icon: Iconsax.gps,
            loading: _locating,
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _pickMapType,
          child: const MapButton(
            icon: Iconsax.layer,
            loading: false,
          ),
        ),
        const SizedBox(height: 10),
        // ดาวน์โหลดแปลง — เฉพาะโหมดแผนที่แปลง
        if (widget.parcelBrowser) ...[
          GestureDetector(
            onTap: () => _openDownload(vm),
            child: const MapButton(
              icon: Iconsax.import,
              loading: false,
            ),
          ),
          const SizedBox(height: 10),
        ],
        // ร่างในเครื่อง — โชว์เฉพาะตอนมีร่างจริง
        // (ไม่มีก็ไม่ต้องมีปุ่มให้กดเปล่า)
        if (vm.parcels.any((p) => p.isDraft))
          GestureDetector(
            onTap: () => _openDrafts(vm),
            child: const MapButton(
              icon: Iconsax.document_text,
              loading: false,
            ),
          ),
      ],
    ),
                    );

  Widget _searchSuggestions(MapViewModel vm) =>
    Positioned(
      top: MediaQuery.of(context).padding.top + 74,
      left: 28,
      right: 28,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 8),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          // โชว์ ~5 แถวพอดีจอ ที่เหลือเลื่อนดูใน list
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: 305,
            ),
            child: ListView.separated(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: vm.searchSuggestions.length,
              separatorBuilder: (_, _) => const Divider(
                height: 1,
                color: Colors.black12,
              ),
              itemBuilder: (context, i) => InkWell(
                onTap: () {
                  // เลือกแล้วใส่ชื่อแปลงลงช่องค้นหา
                  // (กรอง polygon เหลือแปลงนี้) +
                  // ปิดคีย์บอร์ด → dropdown ซ่อน +
                  // zoom ไปแปลงที่เลือก
                  final p = vm.searchSuggestions[i];
                  _searchCtrl.text = p.name;
                  _searchCtrl.selection =
                      TextSelection.collapsed(
                        offset: p.name.length,
                      );
                  vm.setSearchQuery(p.name);
                  FocusScope.of(context).unfocus();
                  _fitPoints(p.points);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Iconsax.location,
                        size: 20,
                        color: AppColors.green,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              vm.searchSuggestions[i].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _suggestionSub(
                                vm.searchSuggestions[i],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

  Widget _emptyDownloadPrompt(MapViewModel vm) =>
    Center(
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 14,
          ),
        ),
        onPressed: () => _openDownload(vm),
        icon: const Icon(Iconsax.import, size: 22),
        label: const Text(
          'ดาวน์โหลดข้อมูลแปลง',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );

  Widget _savingOverlay() =>
    Positioned.fill(
      child: Container(
        color: Colors.black38,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 12),
              Text(
                'กำลังบันทึกแปลง...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
}
