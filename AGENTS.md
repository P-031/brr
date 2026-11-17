# BRR — สรุปโปรเจกต์และงานทั้งหมด (สำหรับ session ต่อไป)

> **Backend handoff**: `docs/API_CONTRACT.md` = เอกสารต่อเชื่อมหลัก —
> ทุก endpoint + shape ที่แอป parse + field ที่เพิ่มแล้วแอปหยิบเอง +
> endpoint ที่แอป wire พร้อมแล้วรอ backend เขียน (เช่น `POST
> /plots/:id/requests` — แอปเรียกอยู่แล้ว ตอนนี้ 404) — แก้ contract
> แล้ว sync ไฟล์นี้เสมอ. Path ทั้งหมดอยู่ใน
> `app/lib/core/config/api_endpoints.dart`

> เอกสารนี้รวมทุกอย่างที่ทำ/ตกลงกันมา — อ่านก่อนเริ่มงานเสมอ
> **สำคัญ: ผู้ใช้ขอไว้ว่าแก้โค้ดเสร็จให้บอกเฉยๆ ไม่ต้อง build/install APK ให้ — เขาทำเอง**

## 1. ภาพรวมโปรเจกต์

แอปพลิเคชันจัดการไร่อ้อย BRR สำหรับพนักงาน/เจ้าหน้าที่ลงพื้นที่วัดแปลงอ้อย — ความแม่นยำพิกัดสำคัญที่สุด ต้องรองรับเครื่องสเปกต่ำ สัญญาณเน็ต/GPS ไม่ดี และข้อมูลหลักหมื่นแปลง

```
D:\BRR\brr\
├── app/      Flutter — MVVM + Provider (ChangeNotifier)
│             features/<feature>/{data,models,viewmodels,views,widgets}
└── backend/  Express/TypeScript + Prisma + PostgreSQL/PostGIS + Redis + Keycloak
```

- **Auth**: Keycloak — app ส่ง bearer access token กับทุก request (`ApiClient`), แยกสิทธิ์ farmer / officer (officer เลือก farmer แล้วบันทึกแปลงให้ได้)
- **Boundary**: PostGIS polygon — เก็บ geometry จริง ห้ามแทนด้วยค่าประมาณ; `backend/src/boundary.ts` มี helper raw-query `ST_AsGeoJSON`
- **ผู้ใช้ตอบภาษาไทย** — UI label ไทยทั้งหมด, ตอบสั้นกระชับ, iterate UI ทีละนิดตาม feedback

## 2. คำสั่งที่ใช้บ่อย

```bash
cd D:\BRR\brr\app
dart analyze lib/features/<feature>          # verify ฝั่งแอป
flutter build apk --release                  # → app/build/app/outputs/flutter-apk/app-release.apk
flutter run -d emulator-5554

cd D:\BRR\brr\backend && npx tsc --noEmit    # verify ฝั่ง backend

# emulator/adb (adb ไม่อยู่ใน PATH ต้องเรียก path เต็ม)
"C:\Users\theao\AppData\Local\Android\sdk\emulator\emulator.exe" -avd Pixel_7_API35
"C:\Users\theao\AppData\Local\Android\sdk\platform-tools\adb.exe" -s emulator-5554 install -r <apk>
"C:\Users\theao\AppData\Local\Android\sdk\platform-tools\adb.exe" -s emulator-5554 shell am start -n com.brr.brr/.MainActivity
# AVD=Pixel_7_API35, device=emulator-5554, package=com.brr.brr
# เปิด AVD ซ้ำตอนรันอยู่ → error "multiple emulators with same AVD" (ให้ใช้ตัวที่เปิดอยู่)

# docker containers: brr-redis, brr-keycloak, backend-db-1 (psql อยู่ใน backend-db-1)
```

## 3. Backend API ที่ทำไว้

| Endpoint | รายละเอียด |
|---|---|
| `GET /plots` | list แปลง — `limit/cursor` (30/เพจ), `years` (comma + `nullYear`), `zone`, `caneType`, `planted` (0/1), `groupKind` (harvest/maintain), `search` (ชื่อ/เลขแปลง/รูท/รหัส/ชื่อชาวไร่ ilike) — หลายค่า = comma = OR; response มี `total` (count ตาม filter) + `outline` GeoJSON ต่อแปลงสำหรับ thumbnail |
| `GET /plots/map` | lightweight สำหรับวาดบนแผนที่ + boundary เต็ม |
| `GET /plots/:id` | รายละเอียดแปลงเดียว (info sheet ใช้) |
| `GET /plots/years` | รายการปีการผลิตสำหรับตัวเลือก |
| `GET /meta/options` | zones/caneTypes/caneGroups/จังหวัด-อำเภอ-ตำบล-หมู่บ้าน cascading + `plotStatuses`/`plotRequestTypes` (คำขอ1/2) + `parcelStatuses` (tab หน้าสถานะแปลง) + `riskLevels` (จุดเสี่ยง) |
| `PATCH /plots/:id` | แก้ meta แปลง (ใช้ตอนนี้: rootNo/sequenceNo — หน้าแก้ไขรูท) |
| `POST /plots` | บันทึกแปลง (farmer เลือกได้เฉพาะ officer) |

สมมติฐาน filter ที่ตกลงกัน: **ปลูกแล้ว** = มี `caneType`; **กลุ่มตัด/บำรุง** = `caneGroup` มีคำ "ตัด"/"บำรุง"

## 4. ฟีเจอร์แผนที่ (`features/map`)

- `map_view.dart` — จอเดียวใช้ 2 โหมด: **วัดพื้นที่** (`parcelBrowser:false`, วาดจุดตาม walk/manual + form บันทึก + พื้นที่สูญเสียหลายชิ้น + cascading จังหวัด→อำเภอ→ตำบล→หมู่บ้าน + เลือกปีการผลิต) vs **แผนที่แปลง** (`parcelBrowser:true` แตะ polygon เด้ง info sheet)
- `autoPromptDownload:false` = ไม่เด้งหน้าเลือกปี/ดาวน์โหลดเอง (ใช้ตอนเข้าจากกิจกรรมแปลง)
- `focusParcel` (ใหม่ล่าสุด) — เปิดแผนที่มุ่งแปลงเดียว: initialCamera กลางแปลง + fit bounds + auto `_showParcelInfo` (`_focusInitialParcel`/`_focusCenter`)
- info sheet แปลง → `widgets/parcel_info_sheet.dart` (`showParcelInfoSheet`) — ดีไซน์ตาม ref แอปจริง: header Land No + อายุ badge + chip เกรด + ตารางสลับสี + เมนู grid 7 ปุ่ม + กิจกรรม (บันทึก/ประวัติ/นำส่ง/อัปเดตแปลงตัด/โครงการ/ยืนยันแปลง/จุดเสี่ยง) — **ปุ่มทั้งหมดยังเป็น stub `_todo` รอนิยามหน้าที่**; วันปลูก fallback `createdAt` (meta.plantedAt ยังไม่มีใน schema); sheet ลากขึ้นเต็มจอได้ (max 1.0, snap) — extent>=0.99 ยิง `onCovered` → map unmount GoogleMap พักไว้เหมือน `_formOpen`
- `เพิ่มเติม` ใน sheet → push `views/parcel_detail_view.dart` (หน้าเต็ม section cards: ข้อมูลแปลง/การปลูก/ชาวไร่/นักส่งเสริม/สถานที่/รูท&ลำดับ/ข้อมูลกลุ่ม 2 ใบ บำรุง+ตัด) — ระหว่างเปิดก็พักแผนที่ผ่าน `onCovered`; ช่องรูปแรกรอ `photoUrl`/`imageUrl` จาก backend (ยังไม่มีใน schema → placeholder)
- `views/parcel_edit_views.dart` — 3 หน้าเมนู: `EditRouteSeqView` (แก้ รูท&ลำดับ → **PATCH /plots/:id จริง** ผ่าน `ParcelService.updateParcelMeta`) + `StatusRequestView`/`EditRequestView` (คำขอแปลง1/2 — dropdown จาก `/meta/options` `plotStatuses`/`plotRequestTypes`; **submit ยัง stub** รอ endpoint คำขอ) — เปิดได้ทั้งจาก ⋮ ในหน้ารายละเอียดและ tile ใน sheet
- **MVVM ตรง flow ข้อมูลแปลง (สำคัญ ห้าม revert)**: view ห้ามเห็น `ParcelService` — `viewmodels/parcel_detail_viewmodel.dart` (`ParcelDetailViewModel`) ครอบ service: `detail` (cache future `/plots/:id` แชร์ทั้ง flow) / `loadOptions()` / `updateRouteSeq()` (PATCH แล้ว refetch+notify ให้ sheet/detail เห็นค่าใหม่) — `MapViewModel.detailVmFor(p)` สร้างต่อแปลง; `map_view.dart` ผ่าน vm เข้า `showParcelInfoSheet` เท่านั้น; `PlotDownloadView` รับ `PlotDownloadViewModel` จาก `vm.createDownloadVm()`; `MapViewModel` **ไม่มี** getter `parcelService` แล้ว — ถ้าจะเพิ่มหน้าใหม่ใต้ flow นี้ให้สร้าง method บน VM ห้ามส่ง service ลง view
- `features/parcel_status/` — มี `ParcelStatusViewModel` แล้ว: tab สถานะจาก `/meta/options → parcelStatuses` (ไม่ hardcode); รายการแปลงต่อ tab ยังไม่มี endpoint (`parcels` ว่าง); `MainView` ส่ง `api` จาก `AuthViewModel` เข้า `ParcelStatusView(api:)`
- `UserProfile.zone` — custom claim `zone` ของ token; badge Zone ใน menu_view แสดงเฉพาะตอนมีจริง
- `widgets/parcel_outline.dart` (`ParcelOutline`) — painter polygon thumbnail แชร์ใช้ทั้งหน้ารายละเอียด + การ์ดกิจกรรมแปลง (ย้ายมาจาก `_RingPainter` เดิม)
- viewport fetch — โหลดแปลงตามกรอบที่เลื่อนดู + gzip + parse ใน isolate + local cache + ข้ามแปลงซ้ำ + cull polygon นอกจอ (optimize หลักหมื่นแปลง)
- walk measure — เพิ่มพิกัดกดมือได้ ปุ่ม "เพิ่มพิกัด" (accuracy gate เข้มงวด), panel ล่างลากได้โชว์พิกัด GPS จริง + copy + accuracy
- ปุ่มลอยขวา: เข็มทิศ (ขึ้นตอน bearing≠0)/ประเภทแผนที่/GPS/ดาวน์โหลด — widget ใน `features/map/widgets/map_widgets.dart` (`MapButton`, `CompassButton`, `MapTypeThumb`)
- `MapViewModel`: `initialParcels` (seed), `yearAllowlist` (กรองปี), `applyDownload`, `canDrawManually`

## 5. ฟีเจอร์ "กิจกรรมแปลง" (`features/plot_activities`) — งานล่าสุด

เมนู Home → หน้า list แปลง ไฟล์:
- `views/plot_activities_view.dart` — UI ทั้งหมด (ยาว ~1000 บรรทัด)
- `viewmodels/plot_activities_viewmodel.dart` — items/filters/search/selectedId/pagination
- `models/plot_list_item.dart` — parse `GET /plots` (**ตัด ` #เลข` ท้ายชื่อออกแล้ว**)
- `features/map/data/parcel_service.dart` → `fetchPlots()` ส่ง filter เป็น comma list

### Layout ล่าสุด (อนุมัติแล้วตาม feedback ล่าสุด)

```
[แผนที่ย่อ ~1/3 จอ ชิดขอบบนทับ status bar — ไม่มี AppBar]
   • back ลอยซ้ายบน • ขวาบน: เข็มทิศ/layer ประเภทแผนที่/ซูม+- 
   • เลื่อน/ซูม/หมุนได้ (ปิด tilt) • default MapType.satellite (เปลี่ยนได้ใน sheet)
[ช่องค้นหา "ค้นหาจาก ชื่อ, รหัสพื้นที่, รหัสชาวไร่" + ปุ่มฟิลเตอร์ Iconsax.setting_4 + badge]
[แถบเขียว "แสดงผลบนแผนที่ จำนวน [N] รายการ" icon Iconsax.global ฟอนต์หนา]
[การ์ดแปลง ×30 + "โหลดเพิ่ม" เต็มกว้างตัวหนา]
```

**การ์ด**: รูป 92×92 กรอบมนซ้าย (พื้นเขียวเข้ม `0xFF173F2A` + polygon เขียวมะกอกจาก outline จริง — `_OutlineThumb`/`_RingPainter` normalize รักษาสัดส่วน) / ชื่อแปลง 16 หนา / `เลขแปลง` / `รหัสชาวไร่` / `ชาวไร่` (15 เทา คนละบรรทัด) / `พื้นที่` เขียวหนา 15 ชิดขวา (FittedBox scaleDown ไม่ตัด) / ปุ่ม `เลือก` เขียวเล็ก (15 หนา, padding 18×10) กึ่งกลางขวา — **ไม่มี animation**

**ปุ่มเลือก** → `vm.select` + push `MapView(parcelBrowser, autoPromptDownload:false, focusParcel)` — แปลง seed เป็น `initialParcels` ให้เห็น polygon ทันที

### ฟิลเตอร์ — multi-select ทุกตัว (Set ใน VM)

ปีการผลิต/เขต/ประเภทอ้อย/สถานะปลูก/กลุ่มงาน → กดเปิด bottom sheet เลือกได้หลายค่า (กรอบเขียว+✓, "ทั้งหมด"=ล้าง, "เสร็จ" ปิด) → "ใช้ตัวกรอง" apply ทีเดียว; ช่องที่เลือกโชว์ "เลือกแล้ว N" + กรอบเขียว; badge นับจำนวนค่าที่เลือกรวม; ตัวเลือกดึง backend (`/plots/years` + `/meta/options`) **ไม่ hardcode**

## 6. Home

`home_view.dart` — เมนู: วัดพื้นที่ / แผนที่แปลง / กิจกรรมแปลง (ใหม่) + header `assets/images/home_header.jpg`

## 7. ข้อมูล seed

`backend/scripts/seed-plots.ts` — กลุ่มจริง 6 กลุ่ม (กลุ่มตัด/บำรุง × หินเหล็กไฟ/คูเมือง/ตูมใหญ่); DB ~30k แปลง (ตัด ~15k / บำรุง ~15k / ปลูกแล้ว ~25.6k / ยังไม่ปลูก ~4.4k); ชื่อแปลงมี ` #เลข` ต่อท้าย (แอปตัดออกตอนแสดงแล้ว)

## 8. สิ่งที่เคยแก้/รู้จักมาแล้ว (อย่าซ้ำผิดพลาดเดิม)

- Emulator เดิม Gboard ไม่เสถียร → เปลี่ยนเป็น **Pixel_7_API35 + OpenBoard** แล้ว
- ช่องตัวเลข: ต้องรองรับคีย์บอร์ดไทย/อังกฤษ (เคยกดเลขไทยไม่ได้)
- Google Maps API key อยู่ `app/android/local.properties` — **ห้ามเปิดเผย/reproduce**
- `401` ตอนโหลดแปลง = token หมดอายุ → logout/login ใหม่
- analyzer มี info `material.dart deprecated → material_ui` — ของ toolchain ใหม่ ไม่ใช่ bug ไม่ต้องแก้
- Emulator เปิด `flutter emulators --launch` อาจ exit 1 ถ้ามี AVD เดิมรันอยู่ — เช็ก `adb devices` ก่อน ใช้ตัวเดิมได้เลย
- Google Maps บน emulator มี log Play services เยอะ — เป็น environmental ไม่ใช่บั๊กแอป
- หมุดบนแผนที่ย่อทับกันหนาแน่นตอนซูมออก — รู้แล้ว ยังไม่ได้ทำ clustering (ทำได้ถ้าขอ)

## 9. ข้อตกลงกับผู้ใช้

- ตอบไทย สั้นกระชับ — สรุปเป็น bullet/ตารางได้
- เปลี่ยนแปลงทีละนิดตาม feedback รูปภาพ (เขา annotate รูปส่งมาบ่อย)
- **หลังแก้โค้ด: แจ้งเฉยๆ ไม่ build/install ให้** — เขาทำเอง (`flutter build apk --release` + adb install)
- ข้อมูลตัวเลือก/ฟิลเตอร์ต้องมาจาก backend เสมอ ห้าม hardcode
- preserve geometry fidelity, cursor pagination (ห้ามโหลดหลักหมื่นเข้า RAM), สิทธิ์ farmer/officer
