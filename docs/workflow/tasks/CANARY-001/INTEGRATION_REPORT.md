# INTEGRATION_REPORT CANARY-001

- fast 32k: baseline median1439.3, candidate1435.8, delta -0.24%, шум; sanity pass
- full 160k: +1.12% pp, в шуме
- full 200k: +0.62% pp, в шуме
- verdict: ARCHIVED
- reason: merge требует progress вне шума на обоих full-окнах; получен no_change
- code blockers: отсутствуют
- next: сохранить ветку на GitHub, удалить локальный worktree/ветку
