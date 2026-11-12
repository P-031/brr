import "dotenv/config";
import { destination, polygonAreaSqm, ringCenter, type LatLng } from "./area";
import { writeBoundary } from "./boundary";
import { prisma } from "./prisma";

const samples: Array<{ id: string; name: string; variety: string; widthM: number; heightM: number }> = [
  { id: "sample-cane-1", name: "ไร่อ้อยตัวอย่าง 1", variety: "ขอนแก่น 3", widthM: 40, heightM: 80 },
  { id: "sample-cane-2", name: "ไร่อ้อยตัวอย่าง 2", variety: "อู่ทอง 12", widthM: 50, heightM: 60 },
  { id: "sample-cane-3", name: "ไร่อ้อยตัวอย่าง 3", variety: "ลำปาง 1", widthM: 36, heightM: 70 },
];

function rectangle(origin: LatLng, widthM: number, heightM: number): LatLng[] {
  return [
    origin,
    destination(origin, 0, widthM),
    destination(origin, heightM, widthM),
    destination(origin, heightM, 0),
  ];
}

async function main() {
const farmers = await prisma.user.findMany({
  where: { role: "FARMER" },
  select: { id: true, username: true },
  orderBy: { username: "asc" },
});

if (farmers.length === 0) {
  console.log("no farmers");
  await prisma.$disconnect();
  process.exit(0);
}

await prisma.plot.deleteMany({ where: { id: { startsWith: "sample-paddy-" } } });

let created = 0;
for (const [index, farmer] of farmers.entries()) {
  let cursor = destination({ latitude: 14.9935, longitude: 103.111 }, index * 220, 0);
  for (const sample of samples) {
    const id = `${sample.id}-${farmer.username}`;
    const ring = rectangle(cursor, sample.widthM, sample.heightM);
    const areaSqm = polygonAreaSqm(ring);
    const center = ringCenter(ring);
    const surveyedAt = new Date("2026-11-01T02:00:00.000Z");
    await prisma.plot.upsert({
      where: { id },
      create: {
        id,
        farmerId: farmer.id,
        name: sample.name,
        variety: sample.variety,
        areaSqm,
        centerLat: center.latitude,
        centerLng: center.longitude,
        surveyedAt,
      },
      update: {
        farmerId: farmer.id,
        name: sample.name,
        variety: sample.variety,
        areaSqm,
        centerLat: center.latitude,
        centerLng: center.longitude,
        surveyedAt,
      },
    });
    await writeBoundary(prisma, id, ring);
    await prisma.plotSurvey.deleteMany({ where: { plotId: id } });
    await prisma.plotSurvey.create({
      data: {
        plotId: id,
        startedAt: new Date(surveyedAt.getTime() - 10 * 60_000),
        finishedAt: surveyedAt,
        areaSqm,
        corners: ring.map((point, corner) => ({
          latitude: point.latitude,
          longitude: point.longitude,
          accuracyM: 5,
          capturedAt: new Date(surveyedAt.getTime() - (ring.length - corner) * 60_000).toISOString(),
        })),
      },
    });
    created += 1;
    cursor = destination(cursor, 0, sample.widthM + 30);
  }
}

console.log(`farmers ${farmers.map((farmer) => farmer.username).join(", ")}`);
console.log(`plots ${created}`);
await prisma.$disconnect();
}

main().catch(async (error) => {
  console.error(error);
  await prisma.$disconnect();
  process.exit(1);
});
