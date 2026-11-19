-- CreateEnum
CREATE TYPE "RecordKind" AS ENUM ('PLOT', 'YIELD', 'TASK');

-- AlterTable
ALTER TABLE "Plot" ADD COLUMN     "surveyedAt" TIMESTAMP(3),
ADD COLUMN     "version" INTEGER NOT NULL DEFAULT 1;

-- AlterTable
-- Existing rows need a value. The default is dropped so the column matches Prisma's @updatedAt.
ALTER TABLE "YieldRecord" ADD COLUMN     "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
ADD COLUMN     "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "YieldRecord" ALTER COLUMN "updatedAt" DROP DEFAULT;

-- AlterTable
ALTER TABLE "FieldTask" ADD COLUMN     "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
ADD COLUMN     "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "FieldTask" ALTER COLUMN "updatedAt" DROP DEFAULT;

-- CreateTable
CREATE TABLE "PlotSurvey" (
    "id" TEXT NOT NULL,
    "plotId" TEXT NOT NULL,
    "startedAt" TIMESTAMP(3) NOT NULL,
    "finishedAt" TIMESTAMP(3) NOT NULL,
    "corners" JSONB NOT NULL,
    "areaSqm" DOUBLE PRECISION NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PlotSurvey_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "DeletedRecord" (
    "kind" "RecordKind" NOT NULL,
    "recordId" TEXT NOT NULL,
    "farmerId" TEXT NOT NULL,
    "plotId" TEXT,
    "deletedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "DeletedRecord_pkey" PRIMARY KEY ("kind","recordId")
);

-- CreateIndex
CREATE INDEX "PlotSurvey_plotId_createdAt_idx" ON "PlotSurvey"("plotId", "createdAt");

-- CreateIndex
CREATE INDEX "DeletedRecord_farmerId_deletedAt_idx" ON "DeletedRecord"("farmerId", "deletedAt");

-- CreateIndex
CREATE INDEX "Plot_farmerId_updatedAt_idx" ON "Plot"("farmerId", "updatedAt");

-- CreateIndex
CREATE INDEX "YieldRecord_updatedAt_idx" ON "YieldRecord"("updatedAt");

-- CreateIndex
CREATE INDEX "FieldTask_updatedAt_idx" ON "FieldTask"("updatedAt");

-- AddForeignKey
ALTER TABLE "PlotSurvey" ADD CONSTRAINT "PlotSurvey_plotId_fkey" FOREIGN KEY ("plotId") REFERENCES "Plot"("id") ON DELETE CASCADE ON UPDATE CASCADE;
