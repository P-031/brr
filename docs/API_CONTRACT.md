# API Contract — สิ่งที่แอปเรียก/คาดหวังจาก backend

> เอกสารฉบับเดียวสำหรับคนทำ backend ต่อ — รวมทุก endpoint ที่แอปใช้,
> shape ที่แอป parse, field ที่แอปจะหยิบแสดงอัตโนมัติเมื่อเพิ่ม,
> และ endpoint ที่แอปพร้อมแล้วแต่รอ backend เขียน
>
> ฝั่งแอป: path ทั้งหมดรวมอยู่ใน `app/lib/core/config/api_endpoints.dart`
> (+ `api_config.dart` สำหรับ auth paths), ทุก call ผ่าน `ApiClient`
> (Bearer `<keycloak access_token>` ทุก request) → data layer เท่านั้น
> (`ParcelService` / `AuthService`) — view ไม่แตะ service ตาม MVVM

## ข้อตกลงทั่วไป

- **Auth**: `Authorization: Bearer <access_token>` — ตัวตน/สิทธิ์
  decode จาก token (Keycloak); farmer เห็นเฉพาะแปลงตัวเอง, officer
  เห็นแปลงที่ดูแล (`farmerCare`)
- **รูปแบบ list**: `{ "items": [...] }` เสมอ — cursor pagination ผ่าน
  `nextCursor` + `total` ตาม endpoint
- **`meta` object**: ข้อมูลแปลงเสริม — แอปอ่าน key เผื่อล่วงหน้า
  (ดูหัวข้อ "meta keys ที่รองรับแล้ว") เพิ่ม key ได้เลยแอปหยิบเอง
- **ค่าว่าง**: แอปถือ `null`/`""` = ไม่ระบุ → แสดง `—`
- **วันที่**: ISO 8601 — แอปแปลงเป็นพ.ศ./เดือนไทยเองฝั่ง UI
- **ชื่อแปลง**: backend อาจต่อท้าย ` #เลข` — แอปตัดออกตอนแสดงแล้ว
- **`/plots/map`**: รองรับ `Accept-Encoding: gzip` (payload ใหญ่,
  หลักหมื่นแปลง) — ต้องไม่ส่ง geometry ประมาณ ใช้ PostGIS polygon จริง

## Endpoint ที่แอปเรียกอยู่

| Method | Path | Query | Request | Response ที่แอป parse |
|---|---|---|---|---|
| GET | `/plots/map` | `box=minLng,minLat,maxLng,maxLat` (หรือ `full`), `years=a,b`, `nullYear=1` | — | `{items:[{id,name,variety?,status?,farmer?,center:{latitude,longitude},meta?,outline:[{latitude,longitude}]}], truncated:bool}` |
| GET | `/plots` | `limit`, `cursor`, `years=a,b`, `nullYear=1`, `zone`, `caneType`, `planted=0/1`, `groupKind=harvest/maintain`, `search` | — | `{items:[plotSummary], nextCursor:string?, total:int}` — `plotSummary` = map item + `outline` GeoJSON สำหรับ thumbnail |
| GET | `/plots/{id}` | — | — | `{id,name,status?,variety?,points:[{latitude,longitude}],farmer:{id,username?,displayName?,email?},area:{rai,ngan,wa,raiDecimal},meta:{...},createdAt}` |
| GET | `/plots/years` | — | — | `{items:[{year:string?,count:int}]}` — `year:null` = แปลงไม่มีปี |
| GET | `/meta/options` | — | — | `{zones,provinces,locations,projects,caneGroups,caneTypes,caneVarieties,ownerships,terrains,lossOptions,plotStatuses,plotRequestTypes,parcelStatuses,riskLevels,prevPlots:[{code,name}]}` — `locations` = `{จังหวัด:{อำเภอ:{ตำบล:[หมู่บ้าน]}}}` |
| GET | `/officers` | — | — | `{items:[{displayName}]}` |
| GET | `/farmers` | — | — | `{items:[{id,displayName?,username}]}` |
| POST | `/plots` | — | `{name,variety?,farmerId?(officer),productionYear?,officerName?,project?,caneGroup?,zone?,province?,district?,subdistrict?,village?,rootNo?,sequenceNo?,prevPlotNo?,caneType?,caneVariety?,ownership?,terrain?,hasLoss?,lossRai?,targetYield?,note?,boundary:{...}}` | plot object |
| PATCH | `/plots/{id}` | — | subset ของ meta fields ข้างบน (แอปใช้ `rootNo`/`sequenceNo`) | plot detail เหมือน GET |
| PUT | `/me/password` | — | `{oldPassword,newPassword}` (อ้าง `ApiConfig.accountPasswordPath`) | 200 |
| POST | `/api/v1/auth/register` | — | ตาม `ApiConfig.registerPath` | — |

สิทธิ์: `GET /plots*` ผ่าน `visiblePlot` (เจ้าของ/officer ผู้ดูแล);
`PATCH/POST` ผ่าน `ownedPlot` — คง semantics เดิมนี้

## meta keys ที่แอปอ่านแล้ว (เพิ่มได้เลย แอปหยิบเอง)

| key | แสดงที่ | หมายเหตุ |
|---|---|---|
| `productionYear`,`officerName`,`project`,`caneGroup`,`zone`,`province`,`district`,`subdistrict`,`village`,`rootNo`,`sequenceNo`,`prevPlotNo`,`caneType`,`caneVariety`,`ownership`,`terrain`,`hasLoss`,`lossRai`,`targetYield`,`note` | ตาราง info sheet + หน้ารายละเอียด | schema มีแล้ว |
| `plantedAt` / `plantDate` / `plantedDate` | "ปลูกเมื่อ", "อายุ N วัน" | ตอนนี้ fallback `createdAt` — ส่ง ISO date ได้เลย |
| `grade` / `plotGrade` | chip "แปลงเกรด X" + แถวเกรด | — |
| `cutStatus` | badge การ์ด "อัปเดตสถานะแปลงตัด" | — |
| `maintainGroup`,`harvestGroup` (+`Code`,`OwnerName`/`groupCode`,`groupOwnerName`) | การ์ดข้อมูลกลุ่ม 2 ใบ | ตอนนี้ใช้ `caneGroup` เดียว + เช็คคำ "บำรุง/ตัด" |
| `officerCode`,`officerEmail` | section นักส่งเสริม | — |
| `photoUrl` / `imageUrl` (ระดับ detail หรือ meta ก็ได้) | ช่องรูปแรกหน้ารายละเอียด | ตอนนี้ placeholder "ยังไม่มีรูปถ่าย" |
| `status` (ระดับ plot หรือ detail) | แถว "สถานะแปลง" + tab หน้าสถานะ | ค่าไทยตรง `parcelStatuses` |

## Endpoint ที่แอปพร้อมใช้แล้ว — รอ backend เขียน (เรียงตามง่าย→ยาก)

1. **`POST /plots/{id}/requests`** — ปุ่ม "ส่งคำขอ" 2 หน้า
   - **แอปเรียกอยู่แล้ว** (`ParcelService.submitPlotRequest`) — เขียน
     endpoint ปุ๊บใช้ได้ทันที ไม่ต้องแก้แอป (ตอนนี้กดแล้วเจอ 404)
   - body: `{kind:"status"|"edit", value:string}` — `kind` status =
     คำขอ1 (เปลี่ยนสถานะ), edit = คำขอ2 (ประเภทแก้ไข); `value` =
     ข้อความไทยตรงจาก `plotStatuses`/`plotRequestTypes`
   - แนะนำสร้าง record สถานะ `รออนุมัติ` → ตอบ 200/201 — workflow
     อนุมัติ/GET list ตามหลัง
2. **`GET /notifications`** → `{items:[{title,body,time,read}]}` —
   badge กระดิ่ง + หน้าแจ้งเตือน (`unreadNotifications` พร้อม)
3. **รายการแปลงตามสถานะ** — หน้า "สถานะแปลง" tabs มาจาก
   `parcelStatuses` แล้ว เหลือ query (เช่น `GET /plots?status=...`)
   หรือผูก `status` เข้า plot summary
4. **อัปโหลดรูปแปลง** — ฟอร์มวัดเก็บ `photos[]` (path ในเครื่อง) อยู่แล้ว
   → เพิ่ม multipart upload + ส่ง `photoUrl` ใน detail

## หมายเหตุต่อเชื่อม

- **ห้าม hardcode ค่าตัวเลือกฝั่งแอป** — เพิ่มตัวเลือกใหม่ให้ขยาย array
  ใน `/meta/options` เท่านั้น แอปจะเห็นเอง
- Keycloak custom claim `zone` → badge "Zone" หน้าเมนูแสดงเอง
- ค่า option ทั้งหมดเป็น **ข้อความไทยตรงๆ** (ไม่ใช่ code) — แอปส่งกลับ
  ค่าเดียวกับที่ได้รับ เช่น PATCH `caneType:"อ้อยตอ"`
