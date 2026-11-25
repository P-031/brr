ALTER TABLE "Plot" ADD COLUMN IF NOT EXISTS "officerName" TEXT;
ALTER TABLE "Plot" ADD COLUMN IF NOT EXISTS "project" TEXT;
ALTER TABLE "Plot" ADD COLUMN IF NOT EXISTS "caneGroup" TEXT;
ALTER TABLE "Plot" ADD COLUMN IF NOT EXISTS "zone" TEXT;
ALTER TABLE "Plot" ADD COLUMN IF NOT EXISTS "province" TEXT;
ALTER TABLE "Plot" ADD COLUMN IF NOT EXISTS "district" TEXT;
ALTER TABLE "Plot" ADD COLUMN IF NOT EXISTS "subdistrict" TEXT;
ALTER TABLE "Plot" ADD COLUMN IF NOT EXISTS "village" TEXT;
ALTER TABLE "Plot" ADD COLUMN IF NOT EXISTS "rootNo" TEXT;
ALTER TABLE "Plot" ADD COLUMN IF NOT EXISTS "sequenceNo" TEXT;
ALTER TABLE "Plot" ADD COLUMN IF NOT EXISTS "prevPlotNo" TEXT;
ALTER TABLE "Plot" ADD COLUMN IF NOT EXISTS "caneType" TEXT;
ALTER TABLE "Plot" ADD COLUMN IF NOT EXISTS "caneVariety" TEXT;
ALTER TABLE "Plot" ADD COLUMN IF NOT EXISTS "ownership" TEXT;
ALTER TABLE "Plot" ADD COLUMN IF NOT EXISTS "terrain" TEXT;
ALTER TABLE "Plot" ADD COLUMN IF NOT EXISTS "hasLoss" TEXT;
ALTER TABLE "Plot" ADD COLUMN IF NOT EXISTS "lossRai" DOUBLE PRECISION;
ALTER TABLE "Plot" ADD COLUMN IF NOT EXISTS "targetYield" DOUBLE PRECISION;
ALTER TABLE "Plot" ADD COLUMN IF NOT EXISTS "note" TEXT;
ALTER TABLE "Plot" ADD COLUMN IF NOT EXISTS "groupKind" TEXT;
ALTER TABLE "Plot" ADD COLUMN IF NOT EXISTS "status" TEXT;

CREATE TABLE IF NOT EXISTS "PlotRequest" (
    "id" TEXT NOT NULL,
    "plotId" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "value" TEXT NOT NULL,
    "createdAt" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "PlotRequest_pkey" PRIMARY KEY ("id")
);
CREATE INDEX IF NOT EXISTS "PlotRequest_plotId_createdAt_idx" ON "PlotRequest" ("plotId", "createdAt");
DO $$ BEGIN
    ALTER TABLE "PlotRequest" ADD CONSTRAINT "PlotRequest_plotId_fkey" 
    FOREIGN KEY ("plotId") REFERENCES "Plot"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS "FromOption" (
    "group" TEXT NOT NULL,
    "label" TEXT NOT NULL,
    "sort" INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT "FromOption_pkey" PRIMARY KEY ("group", "label")
);

CREATE TABLE IF NOT EXISTS "Place" (
    "province" TEXT NOT NULL,
    "district" TEXT NOT NULL,
    "subdistrict" TEXT NOT NULL,
    "village" TEXT NOT NULL,
    CONSTRAINT "Place_pkey" PRIMARY KEY ("province", "district", "subdistrict", "village")
);

INSERT INTO "FromOption" ("group", "label", "sort") VALUES
('projects', 'โครงการเพิ่มผลผลิตอ้อย', 1),
('caneGroups', 'กลุ่ม 1', 1),
('ownerships', 'ของตนเอง', 1),
('ownerships', 'เช่า', 2),
('plotStatuses', 'รออนุมัติ', 1),
('plotStatuses', 'อนุมัติ', 2),
('plotStatuses', 'ไม่อนุมัติ', 3),
('plotRequestTypes', 'แก้ปีการผลิต', 1),
('plotRequestTypes', 'แก้เขต', 2),
('plotRequestTypes', 'แก้ประเภทอ้อย', 3),
('parcelStatuses', 'รออนุมัติ', 1),
('parcelStatuses', 'อนุมัติ', 2),
('parcelStatuses', 'ไม่อนุมัติ', 3),
('parcelStatuses', 'ยกเลิก', 4),
('parcelStatuses', 'แปลงที่ลบแล้ว', 5),
('parcelStatuses', 'แปลงรอยืนยัน', 6),
('parcelStatuses', 'ยกเลิกแบบมีหนี้ค้าง', 7),
('riskLevels', 'ต่ำ', 1),
('riskLevels', 'ปานกลาง', 2),
('riskLevels', 'สูง', 3)
ON CONFLICT ("group", "label") DO NOTHING;

INSERT INTO "Place" ("province", "district", "subdistrict", "village") VALUES
('บุรีรัมย์', 'เมืองบุรีรัมย์', 'ในเมือง', 'หมู่ 1'),
('บุรีรัมย์', 'เมืองบุรีรัมย์', 'ในเมือง', 'หมู่ 2'),
('บุรีรัมย์', 'เมืองบุรีรัมย์', 'ในเมือง', 'หมู่ 3')
ON CONFLICT ("province", "district", "subdistrict", "village") DO NOTHING;

INSERT INTO "FromOption" ("group", "label", "sort") VALUES
('caneVarieties', 'K95-84', 1),
('caneVarieties', 'K88-92', 2),
('caneVarieties', 'ขอนแก่น 3', 3),
('caneVarieties', 'CSB06-4-162', 4),
('caneVarieties', 'ขอนแก่น 80', 5),
('caneVarieties', 'KPS01-12', 6),
('caneVarieties', 'LK92-11', 7),
('caneVarieties', 'CSB08-108', 8),
('caneVarieties', 'CSB08-99', 9),
('caneVarieties', 'CSB08-111', 10),
('caneVarieties', 'ไข่หวาาน', 11),
('caneVarieties', 'ทองม้วน', 12),
('caneVarieties', 'เม็ดขนุน', 13),
('caneVarieties', 'ขอนแก่น 4', 14),
('caneVarieties', 'K07-250', 15),
('caneVarieties', 'อู่ทอง 17', 16),
('caneVarieties', 'CSB15-221', 17),
('caneVarieties', 'CSB15-144', 18),
('caneVarieties', 'อื่นๆ', 19)
ON CONFLICT ("group", "label") DO NOTHING;

INSERT INTO "FromOption" ("group", "label", "sort") VALUES
('lossOptions', 'ไม่มีความเสียหาย', 1),
('lossOptions', 'ต้นไม้', 2),
('lossOptions', 'สระน้ำ', 3),
('lossOptions', 'จอมปลวก', 4),
('lossOptions', 'อาคาร', 5),
('lossOptions', 'อ้อยแล้งตาย', 6),
('lossOptions', 'อื่นๆ', 7)
ON CONFLICT ("group", "label") DO NOTHING;

INSERT INTO "FromOption" ("group", "label", "sort") VALUES
('terrains', 'ลุ่มมาก', 1),
('terrains', 'ลุ่ม', 2),
('terrains', 'ปกติ', 3),
('terrains', 'สูง', 4),
('terrains', 'สูงมาก', 5)
ON CONFLICT ("group", "label") DO NOTHING;

INSERT INTO "FromOption" ("group", "label", "sort") VALUES
('caneTypes', 'ปลายฝนขยาย', 1),
('caneTypes', 'ต้นฝน', 2),
('caneTypes', 'ตอ1', 3),
('caneTypes', 'ตอ2', 4),
('caneTypes', 'ตอ3', 5),
('caneTypes', '>ตอ3', 6),
('caneTypes', 'อ้อยตอ 6,000', 7),
('caneTypes', 'ปลายฝนรื้อตอ', 8)
ON CONFLICT ("group", "label") DO NOTHING;

INSERT INTO "FromOption" ("group", "label", "sort") VALUES
('zones', 'สาวเอ้', 1),
('zones', 'หนองเครือ', 2),
('zones', 'โนนเขวา', 3),
('zones', 'ละกอ', 4),
('zones', 'ลำทะเมนชัย', 5),
('zones', 'นาศรีนวล', 6),
('zones', 'ตลาดโพธิ์', 7),
('zones', 'หนองไผ่', 8),
('zones', 'สวายตางวน', 9),
('zones', 'โนนจำปา', 10),
('zones', 'ทุ่งวัง', 11),
('zones', 'ตลาดชัย', 12),
('zones', 'ปลัดปุ๊ก', 13),
('zones', 'บ้านด่าน', 14)
ON CONFLICT ("group", "label") DO NOTHING;