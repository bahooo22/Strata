# Невалидная серия «200k»

Эта серия не используется в acceptance. `E:/tmp/master.txt` содержал 430080 символов после UTF-8 decoding, поэтому запрос с `--chars 616000` фактически повторял 160k prompt: engine summary показывал около 139k tokens и pp около 908.

Сохранены raw console/engine/answer/provenance/resources, исходный summary и ledger как diagnostic. Для настоящего 200k создан `E:/tmp/master-upstream-200k.txt` на 616000 символов с тем же префиксом; валидный ledger содержит только 32k/160k строки.
