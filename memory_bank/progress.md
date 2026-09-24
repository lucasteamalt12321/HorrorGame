# Progress — HorrorGame

## Статус

- **Текущая итерация:** ИТЕРАЦИЯ 3 (PHASE 2) — завершена, готова к коммиту.
- **Прогресс по Project Deliverables:** 21% (DL-01..03; см. `projectbrief.md`).
- **Last checked commit:** `c3467749521fd701cf85bc1dee8244a236d8af14` (PHASE 2 в рабочей копии, не закоммичена)

## Что сделано до этого контекста (git history)

Краткая хронология:
- `c017618` — Initial commit (Godot horror game project).
- `4e1c664` — Added player (capsule, WASD, mouse look).
- `3866bb0`..`0b1d342` — mobile controls: joystick, camera, jump.
- `c61ffb1`..`ec0f28a` — исправления touch-обработки.
- `646d86d`..`e2a4389` — мобильные контролы: скрытие на desktop, стили.
- `1fa4558`..`48c633f` — размеры и масштаб стола/монитора в test_room.

## Изменения ИТЕРАЦИИ 1 (сделано)

- Реорганизация в подкаталоги: `scenes/player/`, `scenes/levels/`, `scenes/levels/test_room/`, `ui/mobile/`; обновлены ext_resource пути и `project.godot` main_scene.
- `project.godot`: добавлены actions `jump` (Space), `interact` (E), `photo` (ЛКМ).
- `player.gd`: прыжок переведён с `ui_accept` на action `jump`.
- Созданы `docs/ARCHITECTURE.md`, `docs/README.md`, полный `memory_bank/`.

## Изменения ИТЕРАЦИИ 2 (сделано)

- `systems/game_manager/game_manager.gd` — новый autoload `GameManager` (режимы, mouse, ui_cancel).
- `project.godot` — добавлен `[autoload] GameManager`.
- `scenes/player/player.gd` — рефактор: `@export speed/jump_velocity/mouse_sensitivity`, гейт по `GameManager.is_exploring()`, курсор больше не трогает.
- `ui/mobile/mobile_controls.gd` — камера/прыжок гейтятся по режиму.
- Закоммичено и запушено: `c346774`.

## Known Issues

- [x] Константы `SPEED/JUMP_VELOCITY/MOUSE_SENSITIVITY` в `player.gd` — решено в PHASE 1 (`@export`).
- [ ] (TODO, PHASE 15) Отсутствует справочник канона: Олеговирус, LTL, Чайная религия, Nine Circles, eight-nine. Не выдумывать факты канона до уточнения.
- [ ] `player_model.obj` импортируется, но не используется — требует решения (удалить/использовать на PHASE 21).

## Changelog

| Дата | Что | Файлы |
|---|---|---|
| 2026-09-23 | PHASE 0: архитектура, структура, Memory Bank, actions | `docs/*`, `memory_bank/*`, `project.godot`, перемещённые `scenes/*`, `ui/*` |
| 2026-09-23 | PHASE 1: GameManager (modes/routing/mouse) + PlayerController | `systems/game_manager/*`, `scenes/player/player.gd`, `ui/mobile/mobile_controls.gd`, `project.godot` |
| 2026-09-23 | PHASE 2: офис (комната, стол, монитор, клавиатура, мышь, стул, дверь, шкаф, окно, растение, свет) | `scenes/levels/office/office.tscn`, `scenes/levels/world.tscn`, `docs/*`, `memory_bank/*` |
| 2026-09-24 | PHASE 2 fixes: геометрия офиса (клавиатура выровнена, шкаф на полу, перемычка двери, окно вплотную, растение, монитор на столе, дверь по центру рамы) | `scenes/levels/office/office.tscn` |

## Чек-лист завершения сессии

- [ ] Проверен `git status` на неожиданные изменения.
- [ ] Обновлены `progress.md` и `activeContext.md`.
- [ ] Синхронизирован `docs/README.md` при изменении архитектуры.
- [ ] Указан новый `last_checked_commit`.