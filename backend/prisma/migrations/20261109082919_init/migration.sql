-- CreateExtension
CREATE EXTENSION IF NOT EXISTS "postgis";

-- CreateEnum
CREATE TYPE "Role" AS ENUM ('FARMER', 'OFFICER');

-- CreateEnum
CREATE TYPE "TaskKind" AS ENUM ('PLANT', 'FERTILIZE', 'SPRAY', 'HARVEST');

-- CreateTable
CREATE TABLE "User" (
    "id" TEXT NOT NULL,
    "keycloakId" TEXT NOT NULL,
    "username" TEXT NOT NULL,
    "role" "Role" NOT NULL,
    "displayName" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "FarmerCare" (
    "officerId" TEXT NOT NULL,
    "farmerId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "FarmerCare_pkey" PRIMARY KEY ("officerId","farmerId")
);

-- CreateTable
CREATE TABLE "Plot" (
    "id" TEXT NOT NULL,
    "farmerId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "variety" TEXT NOT NULL DEFAULT '',
    "areaSqm" DOUBLE PRECISION NOT NULL,
    "centerLat" DOUBLE PRECISION NOT NULL,
    "centerLng" DOUBLE PRECISION NOT NULL,
    "boundary" geometry(Polygon, 4326),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Plot_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "YieldRecord" (
    "id" TEXT NOT NULL,
    "plotId" TEXT NOT NULL,
    "season" TEXT NOT NULL,
    "weightTons" DOUBLE PRECISION NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "YieldRecord_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "FieldTask" (
    "id" TEXT NOT NULL,
    "plotId" TEXT NOT NULL,
    "kind" "TaskKind" NOT NULL,
    "date" DATE NOT NULL,
    "done" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "FieldTask_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "User_keycloakId_key" ON "User"("keycloakId");

-- CreateIndex
CREATE UNIQUE INDEX "User_username_key" ON "User"("username");

-- CreateIndex
CREATE INDEX "User_role_idx" ON "User"("role");

-- CreateIndex
CREATE INDEX "FarmerCare_farmerId_idx" ON "FarmerCare"("farmerId");

-- CreateIndex
CREATE INDEX "Plot_farmerId_createdAt_id_idx" ON "Plot"("farmerId", "createdAt", "id");

-- CreateIndex
CREATE INDEX "Plot_boundary_idx" ON "Plot" USING GIST ("boundary");

-- CreateIndex
CREATE INDEX "YieldRecord_plotId_createdAt_idx" ON "YieldRecord"("plotId", "createdAt");

-- CreateIndex
CREATE INDEX "FieldTask_plotId_date_idx" ON "FieldTask"("plotId", "date");

-- AddForeignKey
ALTER TABLE "FarmerCare" ADD CONSTRAINT "FarmerCare_officerId_fkey" FOREIGN KEY ("officerId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "FarmerCare" ADD CONSTRAINT "FarmerCare_farmerId_fkey" FOREIGN KEY ("farmerId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Plot" ADD CONSTRAINT "Plot_farmerId_fkey" FOREIGN KEY ("farmerId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "YieldRecord" ADD CONSTRAINT "YieldRecord_plotId_fkey" FOREIGN KEY ("plotId") REFERENCES "Plot"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "FieldTask" ADD CONSTRAINT "FieldTask_plotId_fkey" FOREIGN KEY ("plotId") REFERENCES "Plot"("id") ON DELETE CASCADE ON UPDATE CASCADE;
