INSERT INTO "FromOption" ("group", "label", "sort") VALUES
('lossOptions', 'ไม่มีความเสียหาย', 1),
('lossOptions', 'ต้นไม้', 2),
('lossOptions', 'สระน้ำ', 3),
('lossOptions', 'จอมปลวก', 4),
('lossOptions', 'อาคาร', 5),
('lossOptions', 'อ้อยแล้งตาย', 6),
('lossOptions', 'อื่นๆ', 7)
ON CONFLICT ("group", "label") DO UPDATE SET "sort" = EXCLUDED."sort";

INSERT INTO "FromOption" ("group", "label", "sort") VALUES
('terrains', 'ลุ่มมาก', 1),
('terrains', 'ลุ่ม', 2),
('terrains', 'ปกติ', 3),
('terrains', 'สูง', 4),
('terrains', 'สูงมาก', 5)
ON CONFLICT ("group", "label") DO UPDATE SET "sort" = EXCLUDED."sort";

INSERT INTO "FromOption" ("group", "label", "sort") VALUES
('caneTypes', 'ปลายฝนขยาย', 1),
('caneTypes', 'ต้นฝน', 2),
('caneTypes', 'ตอ1', 3),
('caneTypes', 'ตอ2', 4),
('caneTypes', 'ตอ3', 5),
('caneTypes', '>ตอ3', 6),
('caneTypes', 'อ้อยตอ 6,000', 7),
('caneTypes', 'ปลายฝนรื้อตอ', 8)
ON CONFLICT ("group", "label") DO UPDATE SET "sort" = EXCLUDED."sort";

INSERT INTO "FromOption" ("group", "label", "sort") VALUES
('zones', 'สาวเอ้', 1),
('zones', 'หนองเครือ', 2),
('zones', 'โนนเขวา', 3),
('zones', 'ละกอ', 4),
('zones', 'ลำทะเมนชัย', 5),
('zones', 'นาศรีนวล', 6),
('zones', 'ตลาดโพธิ์', 7),
('zones', 'หนองไผ่', 8),
('zones', 'สวายตางวน', 9),
('zones', 'โนนจำปา', 10),
('zones', 'ทุ่งวัง', 11),
('zones', 'ตลาดชัย', 12),
('zones', 'ปลัดปุ๊ก', 13),
('zones', 'บ้านด่าน', 14)
ON CONFLICT ("group", "label") DO UPDATE SET "sort" = EXCLUDED."sort";
