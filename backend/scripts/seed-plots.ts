/**
 * Seed 50 measured cane plots with complete, varied metadata.
 * Reuses the same write path as POST /plots (plot row + PostGIS
 * boundary via writeBoundary) so seeded data is identical to
 * data saved from the app.
 *
 * Run:  npx tsx scripts/seed-plots.ts [count] [minRai] [maxRai] [--year]
 *        --year = ระบุปีการผลิตทุกแปลง (default มีบางแปลงปีว่าง)
 */
import "dotenv/config";
import { Prisma } from "@prisma/client";
import { normalizeRing, polygonAreaSqm, ringCenter, type LatLng } from "../src/area";
import { writeBoundary } from "../src/boundary";
import { prisma } from "../src/prisma";
import { cacheDelPattern } from "../src/redis";

const rand = (min: number, max: number) => min + Math.random() * (max - min);
const pick = <T>(list: readonly T[]): T => list[Math.floor(Math.random() * list.length)];
const pickN = (list: readonly string[]) =>
  list.filter(() => Math.random() < 0.4).slice(0, 3);

// ---- data pools (ตรง master data ใน /meta/options) ----
const YEARS = ["2567", "2568", "2569", null] as const;
const YEARS_REQUIRED = ["2567", "2568", "2569"] as const;
const PROJECTS = [
  "โครงการส่งเสริมการปลูกอ้อย BRR",
  "โครงการอ้อยปลอดเผา",
  "โครงการพัฒนาพื้นที่ชลประทาน",
] as const;
const CANE_GROUPS = [
  "กลุ่มตัดหินเหล็กไฟ",
  "กลุ่มตัดคูเมือง",
  "กลุ่มตัดตูมใหญ่",
  "กลุ่มบำรุงหินเหล็กไฟ",
  "กลุ่มบำรุงคูเมือง",
  "กลุ่มบำรุงตูมใหญ่",
] as const;
const ZONES = ["เขต 1", "เขต 2", "เขต 3", "เขต 4", "เขต 5", "เขต 6"] as const;
const LOCATIONS = [
  { district: "ประโคนชัย", subdistrict: "ประโคนชัย", villages: ["บ้านโคก", "บ้านหนองบัว", "บ้านแดง"] },
  { district: "ประโคนชัย", subdistrict: "สี่เหลี่ยม", villages: ["บ้านสี่เหลี่ยม", "บ้านตาคง"] },
  { district: "ประโคนชัย", subdistrict: "ตะเคียน", villages: ["บ้านตะเคียน", "บ้านโนนเจริญ"] },
  { district: "นางรอง", subdistrict: "ทุ่งแสงทอง", villages: ["บ้านทุ่งแสงทอง", "บ้านหนองตาคง"] },
  { district: "นางรอง", subdistrict: "สะเดา", villages: ["บ้านสะเดา", "บ้านโนนสะอาด"] },
  { district: "ละหานทราย", subdistrict: "ละหานทราย", villages: ["บ้านละหานทราย", "บ้านดงมะไฟ"] },
] as const;
const CANE_TYPES = [
  "อ้อยปลายฝนขยาย",
  "อ้อยปลายฝนรื้อตอ",
  "อ้อยต้นฝน",
  "อ้อยตอ1",
  "อ้อยตอ2",
  "อ้อยตอ3",
  "อ้อยมากกว่าตอ3",
  "อ้อยตอ6000",
] as const;
const CANE_VARIETIES = ["แขกดำ", "เสาวภา 216", "ขอนแก่น 3", "ลำพูน", "อุทิศ 16"] as const;
const OWNERSHIPS = ["กรรมสิทธิ์", "เช่า", "นส.3ก"] as const;
const TERRAINS = ["ที่ราบ", "ที่ราบลุ่ม", "ที่ลูกคลื่น"] as const;
const LOSS_OPTIONS = ["น้ำท่วม", "ความแล้ง", "แมลงศัตรูพืช", "วัชพืช", "เพลี้ยไฟ"] as const;
const NOTES = [
  "ดินดี เหมาะปลูกอ้อย",
  "เคยน้ำท่วมช่วงปลายปี",
  "ต้องปรับระดับหน้าดิน",
  "ใกล้แหล่งน้ำ",
  null,
  null,
] as const;
const NAME_PREFIX = ["แปลงอ้อย", "ไร่อ้อย", "แปลง"] as const;

/** วงขอบไม่สม่ำเสมอ 10–17 จุด — เหมือนปักเดินวัดรอบแปลงจริง
 *  รัศมีแกว่ง 0.65–1.35 เท่าของวงกลมพื้นที่เท่ากัน */
function makeRing(centerLat: number, centerLng: number, areaRai: number): LatLng[] {
  const n = 10 + Math.floor(Math.random() * 8);
  const baseR = Math.sqrt((areaRai * 1600) / Math.PI); // เมตร
  const cosLat = Math.cos((centerLat * Math.PI) / 180);
  const ring: LatLng[] = [];
  for (let i = 0; i < n; i++) {
    const ang = (i / n) * 2 * Math.PI + rand(-0.15, 0.15);
    const r = baseR * rand(0.65, 1.35);
    ring.push({
      latitude: centerLat + (r * Math.cos(ang)) / 111320,
      longitude: centerLng + (r * Math.sin(ang)) / (111320 * cosLat),
    });
  }
  return ring;
}

async function main() {
  const farmers = await prisma.user.findMany({ where: { role: "FARMER" } });
  if (farmers.length === 0) throw new Error("ไม่พบ farmer ใน DB");
  const officers = await prisma.user.findMany({ where: { role: "OFFICER" } });
  const officerName = officers[0]?.displayName ?? "";

  const total = Math.max(
    1,
    Number.parseInt(process.argv[2] ?? "50", 10) || 50,
  );
  const minRai = Number(process.argv[3] ?? 2) || 2;
  const maxRai = Number(process.argv[4] ?? 60) || 60;
  const requireYear = process.argv.includes("--year");
  const yearPool = requireYear ? YEARS_REQUIRED : YEARS;
  const startNo = (await prisma.plot.count()) + 1; // ต่อเลขจากแปลงเดิม

  // กระจายแบบธรรมชาติ — คลัสเตอร์ "หมู่บ้าน" หลายจุด แปลงกระจุก
  // รอบคลัสเตอร์ (หนาแน่นต่างกัน) + เศษกระจายอิสระ ไม่เป็นกริด
  const clusterCount = Math.min(45, Math.max(8, Math.floor(total / 500)));
  const clusters = Array.from({ length: clusterCount }, () => ({
    lat: 15.233 + rand(-0.5, 0.5),
    lng: 103.077 + rand(-0.55, 0.55),
    spread: rand(0.02, 0.07), // รัศมีกระจุกต่างกัน ~2–7 กม. คลายกว่ากริดแน่น
    weight: Math.random() ** 0.6, // คลัสเตอร์ใหญ่/เล็กสุ่ม
  }));
  const weightSum = clusters.reduce((s, c) => s + c.weight, 0);
  const centers: { lat: number; lng: number }[] = [];
  for (let i = 0; i < total; i++) {
    if (Math.random() < 0.2) {
      // 20% กระจายอิสระนอกคลัสเตอร์
      centers.push({
        lat: 15.233 + rand(-0.5, 0.5),
        lng: 103.077 + rand(-0.55, 0.55),
      });
      continue;
    }
    let w = Math.random() * weightSum;
    let c = clusters[0];
    for (const cand of clusters) {
      w -= cand.weight;
      if (w <= 0) {
        c = cand;
        break;
      }
    }
    centers.push({
      lat: c.lat + rand(-c.spread, c.spread),
      lng: c.lng + rand(-c.spread, c.spread),
    });
  }

  for (let i = 0; i < total; i++) {
    const farmer = farmers[i % farmers.length];
    const loc = pick(LOCATIONS);
    const losses = pickN(LOSS_OPTIONS);
    const areaRai = rand(minRai, maxRai);
    const ring = normalizeRing(makeRing(centers[i].lat, centers[i].lng, areaRai));
    const measured = {
      ring,
      areaSqm: polygonAreaSqm(ring),
      center: ringCenter(ring),
    };
    const variety = pick(CANE_VARIETIES);
    const year = pick(yearPool);
    const hasLoss = losses.length > 0 && Math.random() < 0.35;

    const plotId = await prisma.$transaction(async (tx) => {
      const created = await tx.plot.create({
        data: {
          farmerId: farmer.id,
          name: `${pick(NAME_PREFIX)} ${loc.villages[0]} #${startNo + i}`,
          variety,
          productionYear: year,
          officerName: officerName || null,
          project: pick(PROJECTS),
          caneGroup: pick(CANE_GROUPS),
          zone: pick(ZONES),
          province: "บุรีรัมย์",
          district: loc.district,
          subdistrict: loc.subdistrict,
          village: pick(loc.villages as unknown as string[]),
          rootNo: `R${String(startNo + i).padStart(4, "0")}`,
          sequenceNo: `${startNo + i}`,
          prevPlotNo: Math.random() < 0.4 ? `P${String(startNo + i).padStart(4, "0")}` : null,
          caneType: pick(CANE_TYPES),
          caneVariety: variety,
          ownership: pick(OWNERSHIPS),
          terrain: pick(TERRAINS),
          hasLoss: hasLoss ? losses.join(",") : null,
          lossRai: hasLoss ? Math.round(rand(0.2, Math.min(3, areaRai / 2)) * 10) / 10 : null,
          targetYield: Math.round(rand(14, 30) * 10) / 10,
          note: pick(NOTES),
          areaSqm: measured.areaSqm,
          centerLat: measured.center.latitude,
          centerLng: measured.center.longitude,
        },
        select: { id: true },
      });
      await writeBoundary(tx as Prisma.TransactionClient, created.id, ring);
      return created.id;
    });
    const step = Math.max(50, Math.floor(total / 20));
    if ((i + 1) % step === 0)
      console.log(`seeded ${i + 1}/${total} (ล่าสุด ${plotId})`);
  }

  await cacheDelPattern("plots:map:*");
  console.log(`เสร็จ — seed ${total} แปลง + clear map cache แล้ว`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
