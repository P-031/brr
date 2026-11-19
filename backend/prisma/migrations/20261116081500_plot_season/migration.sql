-- Existing plots have no season yet. They stay under this label until reassigned.
ALTER TABLE "Plot" ADD COLUMN "season" TEXT NOT NULL DEFAULT 'ยังไม่ระบุ';
ALTER TABLE "Plot" ALTER COLUMN "season" DROP DEFAULT;

CREATE INDEX "Plot_farmerId_season_idx" ON "Plot"("farmerId", "season");

ALTER TABLE "DeletedRecord" ADD COLUMN "season" TEXT;
