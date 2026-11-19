-- Plot.status was created as the PlotStatus enum before the app started
-- storing the Thai labels from plotStatuses. Prisma reads it as text.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_name = 'Plot'
      AND column_name = 'status'
      AND udt_name = 'PlotStatus'
  ) THEN
    ALTER TABLE "Plot" ALTER COLUMN "status" DROP DEFAULT;
    ALTER TABLE "Plot"
      ALTER COLUMN "status" TYPE TEXT
      USING (
        CASE "status"::text
          WHEN 'PENDING' THEN 'รออนุมัติ'
          WHEN 'APPROVED' THEN 'อนุมัติ'
          WHEN 'REJECTED' THEN 'ไม่อนุมัติ'
          WHEN 'CANCELLED' THEN 'ยกเลิก'
          WHEN 'CONFIRMING' THEN 'แปลงรอยืนยัน'
          WHEN 'CANCELLED_IN_DEBT' THEN 'ยกเลิก'
          ELSE "status"::text
        END
      );
    ALTER TABLE "Plot" ALTER COLUMN "status" DROP NOT NULL;
  END IF;
END $$;

DROP TYPE IF EXISTS "PlotStatus";

ALTER TYPE "TaskKind" ADD VALUE IF NOT EXISTS 'PREPARE';
ALTER TYPE "TaskKind" ADD VALUE IF NOT EXISTS 'CARE';
