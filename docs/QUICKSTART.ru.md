# Strata: быстрый старт (форк, 0.2.19 + патчи)

Короткая инструкция: как запустить Qwen3.6-35B-A3B (MoE, сжатие IQ4_XS) на одной видеокарте
8 ГБ с окном 160k–200k токенов. Проверено на RTX 3060 Ti 8 ГБ + 32 ГБ RAM, Windows 11.

## Что это

Форк движка Strata 0.2.19 с нашими патчами:
- int8/fused prompt-эксперты (быстрее чтение экспертов на промпте);
- FA v2 — блочное внимание с плиткой 16×32 и ldmatrix (+16 % prefill на окне 200k);
- MAP-кэш экспертов для SSD-режима и префетч на 2 слоя вперёд;
- fused down IQ4_XS (формат 23), IQ4_NL для gate/up.

Числа (KAT IQ4_XS, реальный текст, один сервер):
| окно | prefill, tok/s | decode, tok/s |
|---|---:|---:|
| 160k (139k токенов) | 899,9–901,7 | 15,2 |
| 200k (202 665 токенов) | 744,9–745,3 | 12,1 |
| 160k, MAP-режим (SSD) | 986,0 | 12,0 |

Для сравнения llama.cpp на том же промпте: 159,9 / 4,04.

## Требования

- Видеокарта NVIDIA: 8 ГБ видеопамяти минимум (16 ГБ удобнее), драйвер не старше 2025 года.
- Оперативная память: 32 ГБ для модели 19 ГБ (16 ГБ модели + буферы). Меньше — только SSD-режим MAP.
- Диск: SSD (SATA допустим, NVMe лучше). На HDD prefill падает в разы.
- Для сборки из исходников: Windows 10/11, PowerShell 7, Visual Studio 2022 Build Tools (C++),
  CUDA Toolkit 13.3.

## Путь 1. Portable-комплект (без сборки)

1. Скачайте `Strata-Portable-<дата>.zip` из раздела Releases (ассет последнего релиза).
2. Распакуйте на SSD, например `D:\Strata-Portable`.
3. Положите GGUF-модель в `models\` (KAT IQ4_XS или Huihui IQ4_XS, файл ~19 ГБ).
4. Запустите `START.bat` → выберите модель → дождитесь `http://127.0.0.1:8080`.
5. Подключите клиент: в настройках OpenAI-совместимого клиента адрес `http://127.0.0.1:8080/v1`
   (для Anthropic-клиентов — `http://127.0.0.1:8080`, без `/v1`).

Комплект содержит только Strata (ранее в него входил llama.cpp — удалён).

## Путь 2. Установщик апстрима + наш движок

```pwsh
cd <папка репозитория>
.\START-HERE.bat --check                 # проверка ПК, ничего не ставит
.\START-HERE.bat --setup                 # ставит окружение и движок
```

Установщик собирает движок из `.\engine` и помечает его `source: local` в `BUILD.json` —
такой движок не подменяется скачанным при обновлении.

Если установщик не принимает вашу модель (его каталог — линейка Qwen3.8-Flash), запускайте напрямую:

```pwsh
.\terminal\.venv\Scripts\python.exe terminal\strata.py components add-build engine --backend cuda
.\terminal\.venv\Scripts\python.exe terminal\strata.py launch `
    --model-path D:\Strata\models\katcoder\KAT-...-IQ4_XS.gguf `
    --context 160k --mtp off --vision off --tune skip --yes --no-tui
```

Остановка: `strata.py launch --stop`. Логи: `strata.py logs --follow`.

## Путь 3. Сборка из исходников

```pwsh
pwsh -File glm/scripts/build_strata_nommq_2026-11-19.ps1 -Mode all
# результат: strata-q36.exe и strata.exe (без MMQ, int8/fused включены в сборке)
```

Сборка использует VS2022 Build Tools и CUDA 13.3; занимает 15–25 минут на i7 одного потока.

## Как проверить, что работает наш движок

- В логе движка есть строка `prompt experts on the native grouped kernels`.
- `sha256sum strata.exe` до и после запуска не меняется.
- `/health` отвечает `{"status":"ok","max_context":...}`.

## Частые проблемы

| Симптом | Что делать |
|---|---|
| «a context of N tokens does not fit» | Передайте `--att-mb 256 --kv-type q4_0` (сжатый KV) или уменьшите окно |
| «no host memory for a layer's experts» | Мало RAM под модель: закройте лишнее, включите MAP-режим (`STRATA_Q36_EXPERT_CACHE_MB`) |
| Prefill в разы медленнее таблиц | Модель на HDD или занята видеопамять (браузер, другой сервер) — проверьте `nvidia-smi` |
| Два сервера одновременно | Перед запуском проверьте `tasklist | findstr strata`; держите один экземпляр |
| Порт 8080 занят | `--port 8081` и адрес `http://127.0.0.1:8081` |
