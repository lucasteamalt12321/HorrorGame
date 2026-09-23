# Tech Context — HorrorGame

## Стек и окружение

- **Движок:** Godot 4.7.x (проект открыт в 4.7, features: `4.7`, `GL Compatibility`).
- **Язык:** GDScript (встроенный).
- **Рендерер:** `gl_compatibility` (desktop + mobile). Преимущество — совместимость с SubViewport 2D, низкие требования.
- **Виндовый драйвер:** `d3d12` (`rendering_device/driver.windows="d3d12"`) — переопределён только для Windows.
- **Физика:** Jolt Physics (`3d/physics_engine="Jolt Physics"`).
- **Платформы:** desktop (Windows) + мобильная поддержка через touch-контролы (UI), рычаги в `mobile_controls`.

## Структура входа в проект

- Главная сцена: `res://scenes/levels/world.tscn`.
- Autoload-менеджеры:
  - `GameManager` → `res://systems/game_manager/game_manager.gd` (режимы, роутинг ввода, курсор). Добавлен в PHASE 1.
  - Остальные — по мере фаз.

## Input actions (актуально на PHASE 0)

| Action | Клавиша | Назначение |
|---|---|---|
| `move_forward` | W | движение вперёд |
| `move_backward` | S | назад |
| `move_left` | A | влево |
| `move_right` | D | вправо |
| `jump` | Space | прыжок |
| `interact` | E | взаимодействие (задел PHASE 3) |
| `photo` | ЛКМ | фото-камера (задел PHASE 8) |

Планируются: `computer_close`, `minigame_jump`, `pause`, `screenshot`.

## Известные особенности окружения

- `.godot/` — кэш редактора, в репозиторий не коммитится.
- Файлы `.gd.uid` — генерируются Godot 4.4+, хранят uid скриптов и переносятся вместе со скриптом.
- `player_model.obj` — импортируется, но пока не используется в сцене.

## CI/CD / проверки

- Актуальный `ruff`-линтер к GDScript не применим; ручная проверка по чек-листу правила 10 ТЗ.
- Для проверки проекта использовать Godot в headless-режиме (`--headless --import`), при наличии исполняемого файла.