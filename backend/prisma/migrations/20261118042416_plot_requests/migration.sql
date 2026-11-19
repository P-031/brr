-- CreateTable
CREATE TABLE "PlotRequest" (
    "id" TEXT NOT NULL,
    "plotId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "payload" JSONB NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'รออนุมัติ',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PlotRequest_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "PlotRequest_plotId_createdAt_idx" ON "PlotRequest"("plotId", "createdAt");

-- AddForeignKey
ALTER TABLE "PlotRequest" ADD CONSTRAINT "PlotRequest_plotId_fkey" FOREIGN KEY ("plotId") REFERENCES "Plot"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PlotRequest" ADD CONSTRAINT "PlotRequest_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
