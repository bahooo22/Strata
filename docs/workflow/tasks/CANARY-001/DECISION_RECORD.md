# DECISION_RECORD CANARY-001

- decision: ARCHIVED
- reviewer: N `9ba7a8a6-9973-4bce-8a66-93acde030932`, CODE_APPROVED C1–C10
- integration owner: A `443fddf1-c6a1-4de1-a762-0b61e5ca941c`
- evidence: fast 32k шум; full 160k +1.12%, full 200k +0.62%, оба внутри шума
- reason: правило workflow v3 — merge только при progress на обоих full-окнах
- branch: `task/CANARY-001` сохраняется на GitHub, локально удаляется
- default: `STRATA_Q36_READ_WINDOWS=1` не меняется
