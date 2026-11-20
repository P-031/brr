ALTER TABLE "PlotRequest" ADD COLUMN "status" TEXT NOT NULL DEFAULT 'รออนุมัติ';
ALTER TABLE "PlotRequest" ADD COLUMN "requester" TEXT;
ALTER TABLE "PlotRequest" ADD COLUMN "payload" JSONB;
ALTER TABLE "PlotRequest" ALTER COLUMN "value" SET DEFAULT '';