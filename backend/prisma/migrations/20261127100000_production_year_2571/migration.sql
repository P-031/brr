INSERT INTO "FromOption" ("group", "label", "sort") VALUES 
('productionYears', '2571/72', 3)
ON CONFLICT ("group", "label") DO NOTHING;