# Active Context — HorrorGame

## Текущий фокус

**ИТЕРАЦИЯ 2 — PHASE 1: GameManager + PlayerController.**

Задача взята в работу.
- GameManager: режимы `EXPLORE/COMPUTER/MINIGAME/BLOCKED`, роутинг ввода, управление мышью, обработка `ui_cancel`.
- PlayerController: `player.gd` рефакторинг — настройки через `@export`, гейт по `GameManager.is_exploring()`.
- Мобильный ввод: гейт камеры/прыжка по режиму.

## Активные решения

| Решение | Обоснование |
|---|---|
| Переход `mode_changed` + владение курсором передан GameManager | Единая точка управления вводом между режимами |
| `player.gd` не контролирует `Input.set_mouse_mode` | Снято с игрока; парной логики не дублируем |
| PlayerController гейтится через `is_exploring()`, а не наоборот | Игрок passive; активную систему роутит GameManager |
| Мобильные кнопки читают `GameManager` | Один источник режима |

## Приоритеты сессии

1. (P1) GameManager (modes) — создан.
2. (P1) PlayerController — @export настройки, гейт.
3. (P1) Мобильный гейт.
4. (P2) Синхронизация MB/docs.
5. (P2) Headless-проверка Godot.

## Следующие шаги (после PHASE 1)

- PHASE 2: полноценный офис.
- PHASE 3: InteractionSystem (подхватывает mode EXPLORE).

## Открытые вопросы

- Источник канона для PHASE 15 (TODO).
- Решение по управлению мобильной камерой (потенциальное объединение с PlayerController на PHASE 1).