# ARCHITECTURE.md

Архитектура проекта **HorrorGame** — 3D-хоррор от первого лица с вложенной 2D-игрой.

---

## 1. Целевая структура проекта

```
res://
├── scenes/
│   ├── player/          # Игрок, контроллер перспективы
│   ├── levels/          # Локации (world, office, test_room)
│   └── game/            # Компьютер, SubViewport-монитор
├── scripts/             # Скрипты-компоненты вне систем
│   └── office/          # OfficeDirector + интерактивные пропы офиса
├── ui/                  # HUD, меню, компьютерные приложения, мобильные контролы
│   ├── hud/
│   ├── menus/
│   ├── computer/        # Приложения: bug_tracker, mail, notes, files
│   └── mobile/          # Touch-управление
├── data/                # Resources + контент в .tres
│   ├── resources/       # Классы ресурсов
│   ├── bugs/            # 17 багов
│   ├── tasks/           # 15 заданий T00..T14
│   ├── levels/          # 4 уровня 2D-игры
│   ├── emails/          # 12 писем
│   ├── canon/           # 4 записи глоссария
│   └── horror/          # 20 хоррор-событий
├── minigame/            # Тестируемая 2D-игра (внутри монитора)
├── systems/             # Core-системы (менеджеры)
│   ├── game_manager/    # Режимы, роутинг ввода, курсор
│   ├── settings/
│   ├── save/
│   ├── audio/
│   ├── interaction/
│   ├── bug_system/
│   ├── report_system/
│   ├── task_system/
│   ├── dialogue/
│   ├── photo/
│   ├── computer/
│   ├── minigame/
│   ├── story/
│   └── horror/
├── shaders/             # Пост-обработка (grain, vignette, scanlines)
├── tests/               # Headless smoke-тест
├── docs/
└── memory_bank/
```

Правила организации:
- UI-сценарии и сцены НЕ содержат gameplay-логику (правило 5 ТЗ).
- Данные, задающие контент (баги, задания, уровни, письма, канон, события), лежат в `data/` как `Resource`.
- Сюжетные флаги живут в `StoryFlags`, а не в случайных объектах сцены (правило 8).
- Никаких «магических чисел» в коде — только `@export`/`Resource`/ProjectSettings (правило 6-7).
- Наполнение геометрией создаётся кодом (`OfficeDirector`, `minigame/game_director.gd`); сцены содержат только каркас. Бинарных ассетов нет, кроме неиспользуемого `player_model.obj`.

---

## 2. Основные сцены

| Сцена | Путь | Назначение |
|---|---|---|
| `main_menu.tscn` | `ui/menus/main_menu.tscn` | **Главная сцена проекта**; переход в `world.tscn` |
| `world.tscn` | `scenes/levels/world.tscn` | Корень игрового мира: `GameRoot` + офис + игрок + mobile-контролы |
| `office.tscn` | `scenes/levels/office/office.tscn` | Локация офиса: комната, стол, монитор, компьютер, `Director` |
| `computer.tscn` | `scenes/game/computer/computer.tscn` | Монитор + SubViewport + 4 приложения рабочего стола |
| `test_room.tscn` | `scenes/levels/test_room/test_room.tscn` | Секретная локация (референс геометрии) |
| `player.tscn` | `scenes/player/player.tscn` | `CharacterBody3D` от первого лица (WASD, мышь, прыжок) |
| `mobile_controls.tscn` | `ui/mobile/mobile_controls.tscn` | Джойстик + Interact/Photo/Pause/Jump (только мобильные) |
| `smoke.tscn` | `tests/smoke.tscn` | Headless-прогон реального дерева в CI (системы и данные) |
| `boot.tscn` | `tests/boot.tscn` | Headless-прогон точки входа: меню → новая игра → офис |

Секретный `test_room` разблокируется тремя способами (по дизайну, не взаимоисключающе): панель TEST_ROOM в офисе, сюжетные биты `T08`/`T13`, флаг `final_test_started`.

---

## 3. Ключевые системы и их связи

```
3D WORLD (офис) — OfficeDirector расставляет интерактивные объекты
   │  E → InteractionSystem → ComputerSystem
   ▼
COMPUTER ──▶ MONITOR (SubViewport) ──▶ 2D GAME (minigame/game_director.gd)
   │                                         │
   │                            баг в зоне → BugSystem
   │                                         ▼
   └─── (выход)                 PHOTO (photo) → PhotoSystem → PhotoEvidence
                                             ▼
                                    REPORT → TaskSystem → NEXT TASK
                                             ▼
                            StorySystem / HorrorSystem (TENSION, биты, finale)
```

| Система | Ответственность | Не отвечает за | Статус |
|---|---|---|---|
| `GameManager` | Режимы (explore/computer/minigame/blocked), владение курсором, роутинг ввода | Контент | готово |
| `Settings` | Громкости, геймплейные переключатели, режим окна и масштаб интерфейса (применяет сам при `settings_changed`) | Геймплей | готово |
| `SaveSystem` | Версионированный `Dictionary` (`SCHEMA_VERSION = 3`) + `migrate()` | Геймплей | готово |
| `InteractionSystem` | Реестр интерактивных объектов, `focus_priority`, подсказки, обработка E | Контент объектов | готово |
| `ComputerSystem` | Вход/выход в компьютер, boot-последовательность, приложения | 2D-геймплей | готово |
| `MinigameSystem` | Запуск/остановка 2D-игры в SubViewport, роутинг ввода в неё | UI компьютера | готово |
| `PhotoSystem` | Снимки, `PhotoEvidence`, галерея | Сохранение изображений на диск | готово |
| `BugSystem` | Реестр багов, статусы (appeared → photographed → reported) | Сюжет | готово |
| `ReportSystem` | Отправка отчётов, ответы разработчиков, мутации отчёта | Задания | готово |
| `TaskSystem` | Цепочка `T00..T14`, `condition_kind`, `_documents_read` | Сюжетная логика | готово |
| `DialogueSystem` | Письма, `grants_flag`, read-state | Геймплей | готово |
| `StoryFlags` | Единственный источник сюжетных флагов | UI | готово |
| `StorySystem` | Главы, биты, finale-gate, prologue-подписки | Геймплей | готово |
| `HorrorSystem` | `TENSION_0..5`, 20 событий, `pause_watch()` | Скримерный спам | готово |
| `AudioManager` | 8 шин, синтез SFX/музыки в рантайме, 3 слоя адаптивной музыки; `stream` играющего плеера не подменяется | Сюжет | готово |
| `CanonRegistry` | Статический реестр глоссария канона (`RefCounted`, не autoload), `validate()` правила 11 | Геймплей | готово |
| `CameraSystem` | Видоискатель: плавный FOV, look, смена режима | — | готово |
| `CursorWatcher` | Наблюдает за паузой; если аномалия случилась, метка `cursor_followed` | Контент | готово |

Зависимости направлены вниз: `GameManager` вызывает системы, системы НЕ обращаются к `GameManager` за геймплеем. `StoryFlags` и `SaveSystem` доступны всем (автозагрузчики). Системы со состоянием регистрируются в `SaveSystem.register(id, self)`.

---

## 4. Связь 3D → 2D (монитор)

```
Monitor (MeshInstance3D, ShaderMaterial с экраном ViewportTexture)
   ▼
SubViewport (пиксельное разрешение 2D-игры, canvas_transform scale ≈ 3)
   ▼
Minigame (Node2D: game_director + player_2d + зоны багов + bug_effect)
```

- 2D-игра живёт в `SubViewport`, её текстура вешается на материал экрана монитора.
- **Инвариант привязки** (проверяется в `tests/smoke.gd`, не визуально): `Screen.material_override` — `ShaderMaterial` с непустым `shader`; параметр `screen_texture` — `ViewportTexture`, чей `viewport_path` указывает именно на `ScreenViewport`; `SubViewport.render_target_update_mode == UPDATE_ALWAYS`; внутри `ScreenViewport` есть инстанс `Desktop`. Нарушение любого пункта даёт не пустой чёрный экран, а белый сэмплер → `EMISSION` в 1.69 → горизонтальные розовые полосы сканлайнов. Статической текстурой экран не заменяется: он обязан оставаться живым.
- Управление при активном мониторе маршрутизируется в `MinigameSystem`, а не в `Player`.
- Никаких отдельных окон ОС — всё внутри игрового мира (ТЗ, стадия 10).
- `minigame/game_director.gd` собирает уровень из `LevelResource` кодом (платформы, зоны, пикапы, точки появления).

### 4.1 Мышь на мониторе (обязательный маршрут)

Godot не доставляет события из корневого `Viewport` в 3D-встроенный `SubViewport`, поэтому маршрут задан явно:

```
InputEvent (корень, координаты viewport)
   ▼ GameRoot._input() — пока GameManager.is_in_computer()
ComputerSystem.get_monitor().route_input(event)
   ▼ Computer.screen_position_for_uv / camera ray
экранный quad (PlaneMesh) → локальный UV
   ▼ ScreenViewport.push_input(event)
GUI рабочего стола и окон приложений
```

- `ComputerSystem` владеет `ui_cancel`: он же закрывает окно, потом выводит из сессии.
- `ComputerSystem.is_booting()` — единственный источник состояния загрузки; у экрана и у системы не должно быть своих таймеров.
- Маппинг quad ↔ SubViewport строится по AABB меша, а не по фиксированным осям: поворот `PlaneMesh` не должен ломать клики.
- `mouse_filter` любого полноэкранного `Control` в `desktop.tscn` обязан быть `IGNORE`. В Godot `PASS` не «пропускает» событие вниз, а затеняет всё, что под ним: окно открывается, выглядит нормально, но ни одна кнопка под ним не нажимается. `smoke.tscn` проверяет это настоящим motion-событием по каждому окну.

---

## 5. Форматы данных

Все ресурсы — `class_name … extends Resource` в `data/resources/`, контент — `.tres` в соответствующих каталогах `data/`.

```gdscript
class_name BugResource extends Resource
@export var id: String            # "BUG_NPC_WALL"
@export var title: String
@export var description: String
@export var category: String      # "navmesh", "animation", "physics", ...
@export var severity: int         # 1..5
@export var trigger: String
@export var location: String
@export var photo_required: bool
@export var report_required: bool
```

```gdscript
class_name TaskResource extends Resource
@export var id: String            # "T09_TEST_ROOM"
@export var title: String
@export var description: String
@export var condition_kind: String  # find_bug | take_photo | read_documents | talk_to | enter_test_room
@export var required_bug_ids: PackedStringArray
@export var required_photo_ids: PackedStringArray
@export var next_task_id: String
```

Остальные: `LevelResource` (слои, платформы, зоны багов, спавны), `EmailResource` (`grants_flag`, `body_sections`), `HorrorEventResource` (тип, триггер, TENSION), `CanonEntryResource` (`safe_facts`, `open_questions`, `Status`).

`PhotoEvidence` — внутренняя запись (`bug_id`, `timestamp`, `valid`, `image_ref`), не файл на диске.

`StoryFlags` — `Dictionary` флагов. Единственный владелец — `StorySystem`; остальные читают через `has_flag`/`set_flag`.

**Важно:** `.tres` сериализует enum-поля числами, а `PackedVector2Array` — плоским списком компонентов. Ручная правка этих полей ломает загрузку.

---

## 6. Input actions

Объявлены в `project.godot` (13 действий):

| Action | Клавиша | Назначение |
|---|---|---|
| `move_forward` / `move_backward` / `move_left` / `move_right` | W / S / A / D | движение |
| `jump` | Space | прыжок (3D) |
| `interact` | E | взаимодействие / вход в 2D-игру |
| `photo` | ЛКМ | снимок |
| `pause` | P | пауза (аномалия при паузе) |
| `minigame_jump` | Space в контексте 2D | прыжок 2D-игры |
| `gallery` | G | галерея фото |
| `objective_toggle` | Tab | развернуть/свернуть задание |
| `camera_viewfinder` | ПКМ | поднять камеру-видоискатель (`CameraSystem`) |
| `flashlight` | F | фонарь (`Player.Head.Flashlight`) |

`photo` и `camera_viewfinder` не конфликтуют: снимок делается и при поднятом видоискателе.
Touch-кнопки не дублируют логику: `ui/mobile/mobile_controls.gd` шлёт `InputEventAction` с тем же action, что и клавиатура, через `Input.parse_input_event()`.

---

## 7. Порядок разработки (маппинг на PHASE)

| Фаза | Содержание | Архитектурные файлы | Статус |
|---|---|---|---|
| PHASE 0 | Архитектура, Memory Bank, структура | `docs/*`, `memory_bank/*` | готово |
| PHASE 1 | PlayerController, GameManager (режимы) | `scenes/player/`, `systems/game_manager/` | готово |
| PHASE 2 | Офис, окружение | `scenes/levels/office/` | готово |
| PHASE 3 | InteractionSystem | `systems/interaction/` | готово |
| PHASE 4 | ComputerSystem + вход/выход | `systems/computer/`, `scenes/game/` | готово |
| PHASE 5 | Monitor/SubViewport | `scenes/game/computer/` | готово |
| PHASE 6 | 2D-платформер (minigame) | `minigame/` | код готов, все 4 уровня проверяются smoke |
| PHASE 7 | BugSystem + данные | `systems/bug_system/`, `data/bugs/` | готово |
| PHASE 8 | Фото + Evidence | `systems/photo/` | готово (видоискатель `CameraSystem` на ПКМ) |
| PHASE 9 | ReportSystem | `systems/report_system/`, `ui/computer/` | готово |
| PHASE 10 | TaskSystem | `systems/task_system/`, `data/tasks/` | готово |
| PHASE 11 | SaveSystem | `systems/save/` | готово |
| PHASE 12 | Story/StoryFlags | `systems/story/` | готово |
| PHASE 13 | HorrorSystem, TENSION | `systems/horror/`, `data/horror/` | готово |
| PHASE 14-15 | Meta horror, канон | `systems/horror/`, `data/canon/`, `systems/story/cursor_watcher.gd` | готово (`cursor_followed`, `saw_pause_anomaly`; канон без неподтверждённых фактов) |
| PHASE 16-17 | UI, Audio | `ui/`, `systems/audio/` | готово |
| PHASE 18 | Mobile | `ui/mobile/` | готово (нет проверки на устройстве) |
| PHASE 19-22 | Контент, полировка, темп | `data/` | контент есть, темп не проверен |
| PHASE 23 | QA, release | `tests/`, `export_presets.cfg` | smoke 226/226, boot 34/34; `.pck` собирается, пресет `Android` (universal APK) валиден; `.exe`/`.apk` ждут export templates, JDK и Android SDK |

---

## 8. Ограничения и решения

- **Не смешивать** gameplay/UI/story/data/audio — менеджер на каждый срез.
- **Не дублировать** системы: перед созданием новой проверять, не существует ли аналогичная.
- **Рендер:** GL Compatibility (поддерживает SubViewport 2D), физика Jolt.
- **Ассеты:** процедурные; бинарных файлов нет. Текстуры и звуки генерируются кодом, чтобы проект открывался в Godot Editor без внешних пакетов.
- **Канон (Олеговирус, LTL, Чайная религия, Nine Circles, eight-nine):** внешнего источника нет. Термины используются только как неоднозначные игровые строки; `CanonEntryResource` фиксирует `safe_facts` и `open_questions`, ничего не утверждая о вселенной. Факты не выдумываются. Инвариант: у записи со `Status.TODO` `safe_facts` обязан быть пустым — иначе глоссарий напечатает догадку как факт. Проверяется `CanonRegistry.validate()`, который вызывает smoke-тест.
- **Сохранения** — версионированные (`SCHEMA_VERSION`), миграции только в `migrate()`.
- **Тесты:** `tests/smoke.tscn` — headless-прогон реального дерева (системы, данные, уровни, галерея, канон), ожидается `RESULT: PASS`. `tests/boot.tscn` — точка входа `main_menu → новая игра → офис`, включая проверку, что игрок ходит. После добавления `class_name` обязателен `--headless --editor --quit`.
- **Сцена не должна ссылаться на несуществующий путь родителя:** такое молча роняет узел при загрузке. Ловится экспортом (`--export-pack` печатает `has vanished when instantiating`) и smoke-проверкой узлов галереи.
- **Ключи словарей — того же типа, что и приходит в роутер:** `Dictionary` в GDScript не приводит типы, поэтому поиск по ключу другого типа молча даёт «не найдено». `DesktopShell` хранит `APP_SCENES`/`APP_TITLES`/`APP_ICONS` по строковым app id, которые приходят в `_on_app_changed(app_id)`, а не по enum `ComputerSystem.App`; из-за enum-ключей окна всех пяти приложений не создавались, и ни один тест этого не замечал. Неудачная загрузка сцены пишет `push_error`, а не выходит тихо.
- **Скрипт и его сцена сверяются по полным путям:** `$`-пути в `@onready` проверяются против иерархии `.tscn` (у `mail_app` и `files_app` был выдуманный узел `Split`). Smoke открывает каждое окно компьютера, чтобы `@onready`-пути падали сразу, а не в релизной сборке.
- **Тест не повторяет архитектуру, а проходит по ней:** проверка через `grab_focus()` + `ui_accept` обходит мышь целиком и пропускает целый класс релизных багов (затенение кнопок, отсутствие маршрута ввода). Boot-тест жмёт E, кликает иконку и выходит по ESC настоящими событиями ввода.
- **Headless-тесту нужны настенные часы, а не кадры:** без окна Godot проходит кадры намного быстрее реального времени, поэтому всё, что считает таймер (boot-анимация, затухания), ждётся через `create_timer(...)`/`_wait_until_wall`. Координаты мыши задаются в пикселях окна: `Input.parse_input_event` применяет трансформ content-scale (`Viewport.get_final_transform()`), и координаты вьюпорта попали бы в другую точку экрана.
- **Мобильная совместимость задаётся пресетом, а не кодом:** один universal APK (`armeabi-v7a`/`arm64-v8a`/`x86`/`x86_64`) без Gradle-сборки, `GL Compatibility`, `Sensor Landscape`, `immersive` + `edge-to-edge`, ETC2/ASTC-текстуры, ноль разрешений. Ввод не дублируется под мобильные кнопки — работает `input_devices/pointing/emulate_mouse_from_touch` (включён по умолчанию), поэтому touch тянет и джойстик, и 2D-игру в мониторе, и все `Button`. Правки мобильности проверяются `--export-release "Android"`: пресет, которого нет, падает как «unknown preset», а не как «нет templates».
