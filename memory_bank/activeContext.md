# Active Context — HorrorGame

## Текущий фокус

**ИТЕРАЦИЯ 2 — PHASE 1: GameManager + PlayerController.** — завершена, закоммичена (`c346774`).

Результаты:
- GameManager: режимы `EXPLORE/COMPUTER/MINIGAME/BLOCKED`, владение курсором, `ui_cancel`, сигнал `mode_changed`.
- PlayerController: настройки через `@export`, гейт по `GameManager.is_exploring()`.
- Мобильный ввод: гейт камеры/прыжка по режиму.
- Headless-проверка — без ошибок. Прогресс: 13%.

## Следующая фаза

**PHASE 2 — Офис (рабочая локация).** Во время следующей сессии:

## Открытые вопросы

- Источник канона для PHASE 15 (TODO).
- Решение по управлению мобильной камерой (потенциальное объединение с PlayerController на PHASE 1).