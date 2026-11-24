ALTER TYPE "RecordKind" ADD VALUE IF NOT EXISTS 'ACTIVITY';

ALTER TABLE "Plot" ADD COLUMN "plantedAt" DATE;

CREATE TABLE "PlotActivity" (
    "id" TEXT NOT NULL,
    "plotId" TEXT NOT NULL,
    "plantedAt" DATE,
    "detailPending" BOOLEAN NOT NULL DEFAULT false,
    "photoCount" INTEGER NOT NULL DEFAULT 0,
    "version" INTEGER NOT NULL DEFAULT 1,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "PlotActivity_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "PlotActivity_plotId_createdAt_idx" ON "PlotActivity"("plotId", "createdAt");
CREATE INDEX "PlotActivity_updatedAt_idx" ON "PlotActivity"("updatedAt");

ALTER TABLE "PlotActivity"
  ADD CONSTRAINT "PlotActivity_plotId_fkey"
  FOREIGN KEY ("plotId") REFERENCES "Plot"("id") ON DELETE CASCADE ON UPDATE CASCADE;