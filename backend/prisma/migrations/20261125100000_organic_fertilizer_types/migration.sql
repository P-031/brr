INSERT INTO "FromOption" ("group", "label", "sort") VALUES
('organicFertilizerTypes', 'มูลวัว', 1),
('organicFertilizerTypes', 'กากอ้อย', 2)
ON CONFLICT ("group", "label") DO NOTHING;
