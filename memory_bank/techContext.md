# Tech Context — HorrorGame

## Стек и окружение

- **Движок:** Godot 4.7.x (features: `4.7`, `GL Compatibility`).
- **Язык:** GDScript (встроенный).
- **Рендерер:** `gl_compatibility` (desktop + mobile). Преимущество — совместимость с SubViewport 2D, низкие требования.
- **Виндовый драйвер:** `d3d12` (`rendering_device/driver.windows="d3d12"`) — переопределён только для Windows.
- **Физика:** Jolt Physics (`3d/physics_engine="Jolt Physics"`).
- **Аудио:** без бинарных файлов — все SFX/музыка синтезируются в рантайме (`AudioStreamWAV`, 44.1 кГц, 16-бит).
- **Платформы:** desktop (Windows) + мобильная поддержка через touch-контролы (UI), рычаги в `mobile_controls`.
- **Версия проекта:** `config/version="0.1.0"`, `config/name="HorrorGame"`.
- **Контент:** 100% процедурный (17 багов, 15 заданий, 4 уровня, 12 писем, 4 записи канона, 20 хоррор-событий). Внешние ассеты: только `player_model.obj` (не используется).

## Структура входа в проект

- Главная сцена: `res://ui/menus/main_menu.tscn` → `scenes/levels/world.tscn` (`GameRoot`).
- Тестовые сцены: `res://tests/smoke.tscn` (системы и данные), `res://tests/boot.tscn` (точка входа: меню → офис) — запуск реального дерева в headless.

## Autoload-менеджеры (17, порядок в `project.godot` важен)

| Autoload | Путь | Ответственность |
|---|---|---|
| `GameManager` | `systems/game_manager/game_manager.gd` | Режимы, роутинг ввода, владение курсором, is_mobile |
| `StoryFlags` | `systems/story/story_flags.gd` | Единственный источник сюжетных флагов + реестр «seen» |
| `Settings` | `systems/settings/settings_system.gd` | Громкости, геймплейные переключатели, режим окна, масштаб UI (применяет сам) |
| `SaveSystem` | `systems/save/save_system.gd` | Версионированный save/load + миграции |
| `AudioManager` | `systems/audio/audio_manager.gd` | 8 шин, синтез SFX, 3 слоя адаптивной музыки |
| `BugSystem` | `systems/bug_system/bug_system.gd` | Реестр багов, статусы, data-driven триггеры |
| `TaskSystem` | `systems/task_system/task_system.gd` | Цепочка `T00..T14`, условия, `_documents_read` |
| `ReportSystem` | `systems/report_system/report_system.gd` | Отчёты, ответы разработчиков, мутации отчёта, `report_opened` |
| `InteractionSystem` | `systems/interaction/interaction_system.gd` | Реестр интерактивных объектов, `focus_priority`, E |
| `DialogueSystem` | `systems/dialogue/dialogue_system.gd` | Письма/диалоги, `grants_flag`, read-state |
| `PhotoSystem` | `systems/photo/photo_system.gd` | Снимки, `PhotoEvidence`, галерея |
| `CameraSystem` | `systems/photo/camera_system.gd` | Видоискатель: FOV, look, сброс при смене режима |
| `MinigameSystem` | `systems/minigame/minigame_system.gd` | Запуск/остановка 2D-игры в SubViewport |
| `ComputerSystem` | `systems/computer/computer_system.gd` | Вход/выход в компьютер, приложения, boot |
| `HorrorSystem` | `systems/horror/horror_system.gd` | `TENSION_0..5`, 20 событий, `pause_watch()` |
| `StorySystem` | `systems/story/story_system.gd` | Главы, биты, finale-gate |
| `CursorWatcher` | `systems/story/cursor_watcher.gd` | Наблюдает паузу, ставит `saw_pause_anomaly` для `cursor_followed` |

Не autoload: `CanonRegistry` (`RefCounted` со `static` — реестр глоссария канона, `res://data/canon`).

## Input actions (13, актуальный список из `project.godot`)

| Action | Клавиша | Назначение |
|---|---|---|
| `move_forward` / `move_backward` / `move_left` / `move_right` | W / S / A / D | движение |
| `jump` | Space | прыжок (3D и 2D) |
| `interact` | E | взаимодействие / вход в 2D-игру |
| `photo` | ЛКМ | снимок (работает и с поднятым видоискателем) |
| `pause` | P | пауза-аномалия |
| `minigame_jump` | Space (в контексте 2D) | прыжок в 2D-игре |
| `gallery` | G | галерея фото |
| `camera_viewfinder` | ПКМ | поднять/опустить камеру-видоискатель |
| `flashlight` | F | фонарь (`Player.Head.Flashlight`) |
| `objective_toggle` | Tab | развернуть/свернуть задание |

## Известные особенности окружения

- `.godot/` — кэш редактора, в репозиторий не коммитится.
- Файлы `.gd.uid` — генерируются Godot 4.4+, хранят uid скриптов и переносятся вместе со скриптом.
- **После добавления нового `class_name` требуется переимпорт** (`--headless --editor --quit`), иначе scene-ссылки не резолвятся. Каждый новый скрипт с `class_name` получает свой `.gd.uid`, который коммитится вместе с ним.
- `.tres` сериализует enum-поля **числами**, а `PackedVector2Array` — плоским списком компонентов. Ручная правка этих полей ломает загрузку; генерировать контент кодом.
- `player_model.obj` — импортируется, но не используется в сцене.
- Искажение кириллицы в выводе PowerShell — кодовая страница консоли, файлы на диске в UTF-8.

## CI/CD / проверки

- `ruff` к GDScript неприменим; ручная проверка по чек-листу правил ТЗ.
- Три обязательные команды перед завершением сессии:

```powershell
# 1. Импорт + регистрация class_name (после новых скриптов)
& "D:\Godot 4.7\Godot_v4.7-stable_win64_console.exe" --headless --path "D:\VariousProjects\horror-game" --editor --quit

# 2. Системы, данные, уровни, галерея, канон (ожидается "221/221 checks passed" + "RESULT: PASS")
& "D:\Godot 4.7\Godot_v4.7-stable_win64_console.exe" --headless --path "D:\VariousProjects\horror-game" res://tests/smoke.tscn

# 3. Точка входа: меню → офис (ожидается "24/24 checks passed" + "RESULT: PASS")
& "D:\Godot 4.7\Godot_v4.7-stable_win64_console.exe" --headless --path "D:\VariousProjects\horror-game" res://tests/boot.tscn
```

- У обоих тестов внутренний watchdog 25 с; внешний timeout в CI — 60 с (smoke) и 60 с (boot).
- При принудительном выходе headless печатается warning о `AudioStreamWAV`/`AudioStreamPlaybackWAV` в кэше сессии — не регрессия, подтверждено `--verbose`.
- В headless клик мышью по `Button` не маршрутизируется; кнопки в тестах активируются через `ui_accept`.

## Сборка и релиз

- Пресет `Windows Desktop` в `export_presets.cfg`: x86_64, GL Compatibility, `export_filter="all_resources"`, `exclude_filter="tests/*, docs/*, memory_bank/*"`, выход `build/windows/HorrorGame.exe`, версия `0.1.0`.
- `/build/` в `.gitignore` — артефакты сборки не коммитятся.
- `--export-pack` работает без дополнительных зависимостей: `build/windows/HorrorGame.pck` (~0.44 MB), 0 warning.
- `--export-release` **требует export templates 4.7** в `%APPDATA%\Godot\export_templates\4.7.stable` (файлы `windows_debug_x86_64.exe` и `windows_release_x86_64.exe`). На текущей машине их нет — установка `tpz` (≈1 GB) или CI со скачиванием шаблонов.
