INSERT INTO "FromOption" ("group", "label", "sort") VALUES
('riskTypes', 'ตัวอย่างประเภท 1', 1),
('riskTypes', 'ตัวอย่างประเภท 2', 2)
ON CONFLICT ("group", "label") DO NOTHING;