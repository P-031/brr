CREATE TABLE "PlotProject" (
    "plotId" TEXT NOT NULL,
    "items" TEXT[],
    "choices" JSONB,
    "passed" BOOLEAN NOT NULL DEFAULT false,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PlotProject_pkey" PRIMARY KEY ("plotId")
);

CREATE TABLE "PlotConfirm" (
    "plotId" TEXT NOT NULL,
    "targetYear" TEXT,
    "status" TEXT,
    "note" TEXT,
    "photoCount" INTEGER NOT NULL DEFAULT 0,
    "recordedBy" TEXT,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PlotConfirm_pkey" PRIMARY KEY ("plotId")
);

CREATE TABLE "PlotCut" (
    "plotId" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "statusCode" TEXT,
    "startDate" DATE,
    "endDate" DATE,
    "estimateTons" DOUBLE PRECISION,
    "cutCaneTons" DOUBLE PRECISION,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PlotCut_pkey" PRIMARY KEY ("plotId")
);

ALTER TABLE "PlotProject" ADD CONSTRAINT "PlotProject_plotId_fkey" FOREIGN KEY ("plotId") REFERENCES "Plot"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "PlotConfirm" ADD CONSTRAINT "PlotConfirm_plotId_fkey" FOREIGN KEY ("plotId") REFERENCES "Plot"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "PlotCut" ADD CONSTRAINT "PlotCut_plotId_fkey" FOREIGN KEY ("plotId") REFERENCES "Plot"("id") ON DELETE CASCADE ON UPDATE CASCADE;