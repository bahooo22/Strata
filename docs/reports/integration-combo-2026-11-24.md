# Integration combo qwen35moe: 160k/200k

Дата: 2026-11-24. Статус: **performance snapshot принят; полный no-regression/quality acceptance не принят**.

## Кандидат и стенд

- candidateRef: `exp/integration-combo-final` = `8789c08ac9a14d9fb1dc737f26eb9b9b56ab266b`.
- Код candidateRef совпадает с installer build `631d80302`; delta до `20f7e077c` — только docs.
- Exe: `F:/tmp/installer-accept/terminal/build/strata-q36.exe`.
- SHA-256 exe: `b746e25ff445ccdc63afe5f30951a8c5d0431a690ee76e91463ebb1ba2721c52`.
- GPU: RTX 3060 Ti 8 GiB; RAM: 32 GiB; Windows 11.
- Модель: KAT IQ4_XS, `D:/Strata/models/katcoder/KAT-Coder-V2.5-Dev-35B-A3B-MTP-ABLITERATED.i1-IQ4_XS.gguf`.
- Промпты: реальный текст `E:/tmp/master.txt`; 160k = 139 299 tokens, 200k = 202 665 tokens.
- Общие флаги: graph on, MTP0, q4_0, super-chunk 8, att-mb 256, vram-reserve-mib 512, max-tokens 256.
- Варианты: default; FA (`--fa -2 --fa-tile 4`); FDEC (`STRATA_Q36_FDEC=1`, `STRATA_Q36_FDEC_CHECK=1`, `--fdec 1`); both.

## Результаты

| Окно | Вариант | Prompt tokens | pp | tg | Prefill ms | Gen ms | rc |
|---|---|---:|---:|---:|---:|---:|---:|
| 160k | default | 139 299 | 581,6 | 13,2 | 239 525 | 5 812 | 0 |
| 160k | FA | 139 299 | 579,1 | 13,7 | 240 548 | 5 610 | 0 |
| 160k | FDEC | 139 299 | 581,3 | 12,4 | 239 629 | 6 213 | 0 |
| 160k | both | 139 299 | 580,4 | 12,5 | 240 000 | 6 154 | 0 |
| 200k | default | 202 665 | 382,0 | 10,8 | 530 506 | 8 296 | 0 |
| 200k | FA | 202 665 | 381,9 | 11,0 | 530 643 | 8 211 | 0 |
| 200k | FDEC | 202 665 | 381,8 | 9,8 | 530 843 | 9 225 | 0 |
| 200k | both | 202 665 | 381,8 | 10,1 | 530 872 | 8 927 | 0 |

Все точки завершились rc=0. В FDEC/both `fdec-check` сообщает `cos 1.000000`; маршрут `fdec armed: decode (T <= 4) on KV_Q4` подтверждён логом.

## Вывод main

- Default — baseline без регрессии.
- FA в этой конфигурации нейтрален по pp и даёт небольшой прирост tg: +3,8 % на 160k, +1,9 % на 200k.
- FDEC ухудшает tg: -6,1 % на 160k, -9,3 % на 200k.
- both также ухудшает tg: -5,3 % на 160k, -6,5 % на 200k.
- Поэтому текущая серия не подтверждает FDEC/both как улучшение для MTP0/q4_0/graph на RTX 3060 Ti. Это не отменяет прежних замеров на других окнах/флагах, но новые performance claims должны ссылаться именно на эту конфигурацию.

## Дополнительные проверки

- Installer/source: setup build rc=0, hygiene rc=0, marker 29/29, smoke answer `Да`.
- Eager + batch2 + session copy: ctx 16k, FA+FDEC; `A='Принято'`, `B='Принято'`, equal=True. Лог `copy-session-both-eager-fixed.log`.
- Independent review `3568a3e2-cc53-4e0e-9673-b35d1dfbbca6`: APPROVE как интеграция кода/default baseline; REJECT как полное no-regression/quality acceptance. FA optional, FDEC/both не рекомендованы и не default.
- Review подтвердил сырые строки 8/8, rc=0, отсутствие error/fallback, fdec-check 752/753/880/880 с cos 1.000000 и max_abs до 1.415e-3.
- Условия полного acceptance: baseline/repeats/чередование перед заявлением no-regression; quality, MTP/copy_session, eager, fallback и backend compile gates. Eager/batch2/session-copy сняты; quality smoke 32k дал 16/22 с needle PASS; MTP2 дал ответ `Принято` и 2/2 drafts. HIP остаётся not-run без toolchain; non-Q6K compile завершён rc=0.
- Quality smoke: general hard suite 16/22; needle `ЛАМПА` PASS; failures `cap3`, `idiom`, `five_words` зафиксированы. Это diagnostic smoke, не полный quality acceptance.
- `exp/integration-combo-final` = `8789c08ac`; `20f7e077c` — дочерний docs-only main. Код candidate идентичен installer build `631d80302`.

## Артефакты

- `glm/2026-11-24_session/integration-combo-summary.json`.
- `glm/2026-11-24_session/integration-combo-raw-audit.json` — пересчёт сырых логов, 8/8 совпали.
- `glm/2026-11-24_session/combo-<variant>-<window>.log`.
- `glm/2026-11-24_session/combo-<variant>-<window>-console.log`.
- `glm/2026-11-24_session/integration-combo-resume.log`.
- `glm/2026-11-24_session/integration-quality-final-summary.md`.
- `glm/2026-11-24_session/mtp2-smoke-final-summary.md`.
