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
('zones', 'เขต 1', 1),
('zones', 'เขต 2', 2),
('caneTypes', 'อ้อยปลูกใหม่', 1),
('caneTypes', 'อ้อยตอ', 2),
('caneVarieties', 'ขอนแก่น 3', 1),
('caneVarieties', 'อู่ทอง 12', 2),
('ownerships', 'ของตนเอง', 1),
('ownerships', 'เช่า', 2),
('terrains', 'พื้นที่ราบ', 1),
('terrains', 'พื้นที่ดอน', 2),
('lossOptions', 'ไม่มี', 1),
('lossOptions', 'น้ำท่วม', 2),
('lossOptions', 'แล้ง', 3),
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