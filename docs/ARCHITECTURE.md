# ARCHITECTURE.md

Архитектура проекта **HorrorGame** — 3D-хоррор от первого лица с вложенной 2D-игрой.

---

## 1. Целевая структура проекта

```
res://
├── scenes/
│   ├── player/          # Игрок, контроллер перспективы
│   ├── levels/          # Локации (мир, офис, test_room)
│   └── game/            # Компьютер, монитор, кликабельные объекты
├── scripts/             # Общие скрипты-компоненты (не системы)
├── assets/
│   ├── textures/        # Текстуры 3D
│   ├── sprites/         # Спрайты 2D-игры
│   ├── models/          # 3D-модели
│   ├── audio/           # Звуки и музыка
│   └── fonts/           # Шрифты
├── ui/                  # HUD, меню, мобильные контролы
│   └── mobile/          # Touch-управление
├── data/                # Resources (баги, задания, диалоги)
│   ├── bugs/
│   └── tasks/
├── levels/              # Описания 2D-уровней (когда появятся)
├── minigame/            # Тестируемая 2D-игра (внутри монитора)
├── systems/             # Core-системы (менеджеры)
│   ├── game_manager/
│   ├── interaction/
│   ├── computer/
│   ├── camera/
│   ├── bug_system/
│   ├── report/
│   ├── task_system/
│   ├── save/
│   ├── story/
│   ├── horror/
│   └── audio/
├── shaders/
├── tests/               # Скрипты-тесты
├── docs/
└── memory_bank/
```

Правила организации:
- UI-сценарии и сцены НЕ содержат gameplay-логику (правило 5 ТЗ).
- Данные, задающие контент (баги, задания), лежат в `data/` как `Resource`.
- Сюжетные флаги живут в `StoryFlags`, а не в случайных объектах сцены (правило 8).
- Никаких «магических чисел» в коде — только `@export`/`Resource`/ProjectSettings (правило 6-7).

---

## 2. Основные сцены

| Сцена | Путь | Назначение |
|---|---|---|
| `world.tscn` | `scenes/levels/world.tscn` | Корневая сцена (точка входа) |
| `test_room.tscn` | `scenes/levels/test_room/test_room.tscn` | Прототип комнаты: пол, стены, стол, монитор, свет |
| `player.tscn` | `scenes/player/player.tscn` | `CharacterBody3D` от первого лица (WASD, мышь, прыжок) |
| `mobile_controls.tscn` | `ui/mobile/mobile_controls.tscn` | Виртуальный джойстик + прыжок (только мобильные) |

Планируемые сцены (фазы 1+):
- `office` — полноценная рабочая локация (стол, компьютер, окружение).
- `computer` — интерактивный компьютер (монитор + интерфейс).
- `monitor` — SubViewport, в который рендерится 2D-игра.
- `minigame` — тестируемая 2D pixel-art игра.

---

## 3. Ключевые системы и их связи

Целевая схема всего цикла (ПМ2-промта):

```
3D WORLD (офис)
   │  E → interact
   ▼
COMPUTER ──▶ MONITOR (SubViewport) ──▶ 2D GAME
   │                                         │
   └─── (запуск/выход)                       │ find bug
                                             ▼
                                    BUG detection ──▶ PHOTO (evidence)
                                             │
                                             ▼
                       REPORT ──▶ TASK complete ──▶ NEXT TASK
```

Центральные менеджеры (создаются по фазам):

| Система | Ответственность | Не отвечает за | Статус |
|---|---|---|---|
| `GameManager` | Общая координация, режимы (explore/computer/minigame/blocked), владение курсором, роутинг ввода | Контент | ✅ PHASE 1 |
| `InteractionSystem` | Реестр интерактивных объектов, подсказки, обработка E | Контент объектов | PHASE 3 |
| `ComputerSystem` | Вход/выход в компьютер, запуск программ | 2D-геймплей | PHASE 4 |
| `MinigameSystem` | 2D-игра внутри SubViewport | UI компьютера | PHASE 6 |
| `CameraSystem` | Фото + `PhotoEvidence` | Сохранение изображений на диск | PHASE 8 |
| `BugSystem` | Реестр багов, триггеры, статусы | Сюжет | PHASE 7 |
| `ReportSystem` | Отправка отчётов, ответы разработчиков | Задания | PHASE 9 |
| `TaskSystem` | Текущее задание, условия завершения, цепочка | Сюжетная логика | PHASE 10 |
| `StoryFlags` | Единственный источник сюжетных флагов | UI | PHASE 12 |
| `SaveSystem` | Сериализация прогресса | Геймплей | PHASE 11 |
| `HorrorSystem` | Уровни напряжения (TENSION_0..5), события | Скримерный спам | PHASE 13 |
| `AudioManager` | Музыка/эмбиент/SFX, громкости, переходы | Сюжет | PHASE 17 |

Зависимости направлены вниз: `GameManager` вызывает системы, системы НЕ обращаются к GameManager за геймплеем. `StoryFlags` и `SaveSystem` доступны всем (автозагрузчики).

---

## 4. Связь 3D → 2D (монитор)

Архитектура вложенной 2D-игры:

```
Monitor (MeshInstance3D ShaderMaterial/ViewportTexture)
   ▼
SubViewport (размер = разрешение пиксельного рендера, scale not empty: 3)
   ▼
Minigame (Node2D, world = простой 2D-платформер)
```

- 2D-игра живёт в `SubViewport`, её текстура вешается на материал экрана монитора.
- Управление при активном мониторе маршрутизируется в `MinigameSystem`, а не в Player.
- Никаких отдельных окон ОС — всё внутри игрового мира (ТЗ, стадия 10).

---

## 5. Форматы данных

### BugResource (`data/bugs/*.tres`)
```gdscript
class_name BugResource extends Resource
@export var id: String            # "BUG_NPC_WALL"
@export var title: String
@export var description: String
@export var category: String      # "navmesh", "animation", "physics", ...
@export var severity: int         # 1..5
@export var trigger: String       # условие появления (код/событие)
@export var location: String      # где в 2D-игре
@export var photo_required: bool
@export var report_required: bool
```

### PhotoEvidence (внутренняя запись, не файл на диске)
```gdscript
class PhotoEvidence:
  var bug_id: String
  var timestamp: int
  var valid: bool
  var image_ref: String   # ссылка внутри камеры, при необходимости
```

### TaskResource (`data/tasks/*.tres`)
```gdscript
class_name TaskResource extends Resource
@export var id: String
@export var title: String
@export var description: String
@export var required_bug_ids: PackedStringArray
@export var next_task_id: String
```

### StoryFlags
`Dictionary` флагов (`met_unknown_npc`, `found_ltl`, ...). Единственный владелец — система `story`. Остальные системы читают через его API (`has_flag`, `set_flag`).

---

## 6. Input actions

В `project.godot` уже объявлены (и будут расширяться):
- `move_forward/backward/left/right` — WASD
- `jump` — Space
- `interact` — E
- `photo` — ЛКМ

Планируемые: `computer_close` (Esc/E), `minigame_jump`, `pause`.

---

## 7. Порядок разработки (маппинг на PHASE)

| Фаза | Содержание | Архитектурные файлы |
|---|---|---|
| PHASE 0 | Архитектура, Memory Bank, структура | `docs/ARCHITECTURE.md`, `memory_bank/*` |
| PHASE 1 | PlayerController, GameManager (режимы) | `scenes/player/`, `systems/game_manager/` |
| PHASE 2 | Офис, окружение | `scenes/levels/office/` |
| PHASE 3 | InteractionSystem | `systems/interaction/` |
| PHASE 4 | ComputerSystem + вход/выход | `systems/computer/`, `scenes/game/` |
| PHASE 5 | Monitor/SubViewport | `scenes/game/monitor/` |
| PHASE 6 | 2D-платформер (minigame) | `minigame/` |
| PHASE 7 | BugSystem + данные | `systems/bug_system/`, `data/bugs/` |
| PHASE 8 | CameraSystem/Evidence | `systems/camera/` |
| PHASE 9 | ReportSystem | `systems/report/`, `ui/` |
| PHASE 10 | TaskSystem | `systems/task_system/`, `data/tasks/` |
| PHASE 11 | SaveSystem | `systems/save/` |
| PHASE 12+ | Story/StoryFlags | `systems/story/` |
| PHASE 13 | HorrorSystem, TENSION уровни | `systems/horror/` |
| PHASE 14-15 | Meta horror, канон | `systems/horror/`, `data/` |
| PHASE 16+ | UI, Audio, Mobile, контент, QA | `ui/`, `systems/audio/` |

---

## 8. Ограничения и решения

- **Не смешивать** gameplay/UI/story/data/audio — менеджер на каждый срез.
- **Не дублировать** системы: перед созданием новой проверять, не существует ли аналогичная.
- **Рендер:** GL Compatibility (поддерживает SubViewport 2D), физика Jolt.
- **Канон (Олеговирус, LTL, Чайная религия, Nine Circles, eight-nine):** используется только на PHASE 15, пока — TODO в Memory Bank.
- Сохранения — устойчивые к версиям данных (версионирование схемы на PHASE 11).