import { Router } from "express";
import { route } from "../http";
import { prisma } from "../prisma";

export const metaRouter = Router();

// Master data for the measurement save form. Real admin divisions for
// the BRR mill area (อ.คูเมือง จ.บุรีรัมย์); promote to DB tables when a
// master-data admin UI exists.
const ZONES = [
  "เขตคูเมือง",
  "เขตเมืองบุรีรัมย์",
  "เขตแคนดง",
  "เขตบ้านด่าน",
  "เขตพุทไธสง",
  "เขตลำปลายมาศ",
];

const PROVINCES = ["บุรีรัมย์", "นครราชสีมา", "สุรินทร์", "มหาสารคาม"];

// ตำบลจริงต่ออำเภอ จ.บุรีรัมย์ — อ้างอิงรายชื่อเทศบาล/อบต.จาก
// หน้า Wikipedia จังหวัดบุรีรัมย์ + หน้ารายอำเภอ (ไม่ครบทุกตำบล —
// เพิ่มตำบลที่เหลือเมื่อมี master data).
const DISTRICT_TAMBONS: Record<string, string[]> = {
  เมืองบุรีรัมย์: ["ในเมือง", "อิสาณ", "เสม็ด", "ชุมเห็ด", "บ้านบัว", "สวายจีก", "หลักเขต", "หนองตาด"],
  คูเมือง: ["คูเมือง", "ปะเคียบ", "บ้านแพ", "พรสำราญ", "หินเหล็กไฟ", "ตูมใหญ่", "หนองขมาร"],
  กระสัง: ["กระสัง", "สองชั้น", "หนองเต็ง", "อุดมธรรม"],
  นางรอง: ["นางรอง", "ทุ่งแสงทอง", "หนองโบสถ์"],
  หนองกี่: ["หนองกี่", "ศาลเจ้าพ่อขุนศรี", "ดอนอะราง", "เมืองไผ่"],
  ละหานทราย: ["ละหานทราย", "ตาจง", "หนองแวง", "สำโรงใหม่", "หนองตะครอง"],
  ประโคนชัย: ["ประโคนชัย", "แสลงโทน", "โคกม้า", "เขาคอก", "ตะโกตาพิ"],
  บ้านกรวด: ["บ้านกรวด", "ตลาดนิคมปราสาท", "บ้านกรวดปัญญาวัฒน์", "หนองไม้งาม", "จันทบเพชร", "โนนเจริญ", "บึงเจริญ", "ปราสาท"],
  พุทไธสง: ["พุทไธสง"],
  ลำปลายมาศ: ["ลำปลายมาศ", "ทะเมนชัย"],
  สตึก: ["สตึก", "ศรีสตึก", "ดอนมนต์", "สะแก"],
  ปะคำ: ["ปะคำ"],
  นาโพธิ์: ["นาโพธิ์"],
  หนองหงส์: ["หนองหงส์"],
  พลับพลาชัย: ["พลับพลาชัย", "จันดุม", "โคกขมิ้น"],
  ห้วยราช: ["ห้วยราช", "โคกเหล็ก", "สามแวง"],
  โนนสุวรรณ: ["โนนสุวรรณ", "โกรกแก้ว", "ดงอีจาน", "ทุ่งจังหัน"],
  ชำนิ: ["ชำนิ", "หนองปล่อง"],
  บ้านใหม่ไชยพจน์: ["บ้านใหม่ไชยพจน์"],
  โนนดินแดง: ["โนนดินแดง"],
  บ้านด่าน: ["บ้านด่าน", "ปราสาท"],
  แคนดง: ["แคนดง", "หัวฝาย"],
  เฉลิมพระเกียรติ: ["พนมรุ้ง", "ยายแย้มวัฒนา", "ถาวร"],
};

// ตำบล อ.คูเมือง — real village names, 3 per tambon (อ้างอิงเว็บ
// อบต./เทศบาลของแต่ละตำบล).
const TAMBON_VILLAGES: Record<string, string[]> = {
  คูเมือง: ["บ้านคูเมือง", "บ้านคูบอน", "บ้านโคกกลาง"],
  ปะเคียบ: ["บ้านปะเคียบ", "บ้านหนองบัวแดง", "บ้านกระเบื้อง"],
  บ้านแพ: ["บ้านโนนสูง", "บ้านโนนกลาง", "บ้านแพ"],
  พรสำราญ: ["บ้านสระบัว", "บ้านโนนเมือง", "บ้านหนองขวาง"],
  หินเหล็กไฟ: ["บ้านหินเหล็กไฟ", "บ้านสาวเอ้", "บ้านโนนมาลัย"],
  ตูมใหญ่: ["บ้านตูมใหญ่", "บ้านปะคำสำโรง", "บ้านใหม่เจริญสุข"],
  หนองขมาร: ["บ้านหนองขมาร", "บ้านหนองโฮง", "บ้านดงเค็ง"],
};

// จังหวัด → อำเภอ → ตำบล → [หมู่บ้าน] — nested so the form can
// cascade-filter each level. ตำบลนอก อ.คูเมือง ใช้บ้านชื่อเดียวกับ
// ตำบลเป็น seed ไปก่อน (เกือบทุกตำบลมีหมู่บ้านชื่อเดียวกัน).
const LOCATIONS: Record<string, Record<string, Record<string, string[]>>> = {
  บุรีรัมย์: Object.fromEntries(
    Object.entries(DISTRICT_TAMBONS).map(([district, tambons]) => [
      district,
      Object.fromEntries(
        tambons.map((t) => [t, TAMBON_VILLAGES[t] ?? [`บ้าน${t}`]]),
      ),
    ]),
  ),
  // Provinces outside the mill area — no master data yet, pickers
  // will show "ยังไม่มีข้อมูล" until real district lists are added.
  นครราชสีมา: {},
  สุรินทร์: {},
  มหาสารคาม: {},
};

const PROJECTS = ["โครงการอ้อยแปลงใหญ่", "โครงการเพิ่มผลผลิตต่อไร่", "โครงการน้ำช่วยอ้อย"];

const CANE_TYPES = ["อ้อยตอ", "อ้อยรุ่น", "อ้อยฝนตามฤดู", "อ้อยน้ำผึ้ง/อ้อยอุ่ม"];

const CANE_VARIETIES = [
  "KK3",
  "LK92-11",
  "UT84-12",
  "M-บุรีรัมย์ 60",
  "เพชรบีระ 60",
  "สุพรรณบุรี 50",
  "85-2-669",
];

const CANE_GROUPS = ["กลุ่มบำรุงหินเหล็กไฟ", "กลุ่มบำรุงคูเมือง", "กลุ่มบำรุงตูมใหญ่"];

const OWNERSHIPS = ["ของตนเอง", "เช่า", "เช่าเพาะปลูก"];

const TERRAINS = ["ที่ราบลุ่ม", "ที่ดอน", "ที่ราบสูง"];

// สาเหตุพื้นที่สูญเสีย — แปลงหนึ่งมีได้หลายอย่างพร้อมกัน ("ไม่มี" เป็น
// exclusive ฝั่งแอปจัดการเองใน multi-select).
const LOSS_OPTIONS = ["ต้นไม้", "สระน้ำ", "จอมปลวก", "อาคาร", "ไม่มี", "อื่น ๆ", "อ้อยแล้งตาย"];

metaRouter.get(
  "/meta/options",
  route(async (_req, res) => {
    // Previous plot numbers come from real plots — the picker offers
    // existing plots to continue a sequence.
    const plots = await prisma.plot.findMany({
      select: { id: true, name: true },
      orderBy: { createdAt: "desc" },
      take: 20,
    });

    res.json({
      zones: ZONES,
      provinces: PROVINCES,
      locations: LOCATIONS,
      projects: PROJECTS,
      caneGroups: CANE_GROUPS,
      caneTypes: CANE_TYPES,
      caneVarieties: CANE_VARIETIES,
      ownerships: OWNERSHIPS,
      terrains: TERRAINS,
      lossOptions: LOSS_OPTIONS,
      prevPlots: plots.map((p) => ({ code: p.id, name: p.name })),
    });
  }),
);
