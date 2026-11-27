INSERT INTO "FromOption" ("group", "label", "sort") VALUES
('productionYears', '2569/70', 1),
('productionYears', '2570/71', 2)
ON CONFLICT ("group", "label") DO UPDATE SET "sort" = EXCLUDED."sort";
