CREATE TABLE "RiskPoint" (
    "plotId" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "name" TEXT,
    "note" TEXT,
    "severity" INTEGER,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "RiskPoint_pkey" PRIMARY KEY ("plotId")
);

ALTER TABLE "RiskPoint" ADD CONSTRAINT "RiskPoint_plotId_fkey" FOREIGN KEY ("plotId") REFERENCES "Plot"("id") ON DELETE CASCADE ON UPDATE CASCADE;