# Progress — HorrorGame

## Статус

- **Текущая итерация:** ИТЕРАЦИЯ 5 (QA, canon-аудит, настройки, release) — завершена и закоммичена как `3e96600`; проверки: smoke 221/221, boot 24/24, экспорт PCK без warning.
- **Прогресс по Project Deliverables:** 96% (см. `projectbrief.md`; 96 = 100 − 4 из `in_progress` DL-14, DL-15).
- **Last checked commit:** `3e96600` (HEAD; рабочая копия чистая)

## Что сделано до этого контекста (git history)

Краткая хронология:
- `c017618` — Initial commit (Godot horror game project).
- `4e1c664` — Added player (capsule, WASD, mouse look).
- `3866bb0`..`0b1d342` — mobile controls: joystick, camera, jump.
- `c61ffb1`..`ec0f28a` — исправления touch-обработки.
- `646d86d`..`e2a4389` — мобильные контролы: скрытие на desktop, стили.
- `1fa4558`..`48c633f` — размеры и масштаб стола/монитора в test_room.
- `a4740ea`..`67aaf93` — PHASE 2: офисная локация, синхронизация MB/docs.
- `3e96600` — ИТЕРАЦИИ 4-5: 17 autoload-систем, контент (90 `.tres`), 2D-игра, компьютер, фото, хоррор, тесты (221/221, 24/24), export-пресет, docs/MB. 209 файлов, +13688/−381.

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

## Изменения ИТЕРАЦИИ 3 (сделано, закоммичено)

- `scenes/levels/office/office.tscn` — полная геометрия офиса; подключение в `world.tscn`.
- Геометрические фиксы: клавиатура выровнена, шкаф на полу, перемычка двери, окно вплотную к стене, растение, монитор на столе, дверь по центру рамы.
- Синхронизация `memory_bank/*`.

## Изменения ИТЕРАЦИИ 4 (сделано, НЕ закоммичено)

Ядро и контент:
- 15 autoload-систем: GameManager, StoryFlags, Settings, SaveSystem, AudioManager, BugSystem, TaskSystem, ReportSystem, InteractionSystem, DialogueSystem, PhotoSystem, MinigameSystem, ComputerSystem, HorrorSystem, StorySystem. Плюс статический реестр `CanonRegistry` (`RefCounted`, не autoload).
- Resource/record-классы в `data/resources/`; контент: 17 багов, 15 заданий `T00..T14`, 4 уровня, 12 писем, 4 записи канона, 20 хоррор-событий.
- 2D-игра (`minigame/`) целиком процедурная: геометрия уровня, игрок, враги, пикапы, зоны багов, 8 визуальных веток `BugEffect`.
- Компьютер: `scenes/game/computer/computer.tscn` + SubViewport, 4 приложения рабочего стола (bug_tracker, mail, notes, files).
- UI: HUD, главное меню, пауза, настройки, галерея фото; `scripts/game_root.gd` владеет UI-сессией.
- Офис: `scripts/office/office_director.gd` + `office_prop.gd` + `office_npc.gd` + `test_room_door.gd` — 4 читаемых документа, сидячий коллега (исчезает к главе 10), панель TEST_ROOM, второе рабочее место.
- Аудио: 8 шин, синтез всех звуков в рантайме, 3 слоя адаптивной музыки (`music_calm` / `music_tension` / `music_peak`) по TENSION.

Исправленные дефекты:
- 12 parse-ошибок скриптов Godot 4.7 (is_mobile, Variant inference, has_node в record-классах, boot countdown, horror shake/report API, `focus_priority` из-за нативного `Area3D.priority`, конфликт `flash`/`flash_rect`).
- 4 ошибки в minigame: `area.body_entered` вместо `body_entered`, несуществующий `_build_tear()`, необъявленный `zone` в `_spawn_effect()`, двойной `add_child` для бейджа в `player_2d.gd`, несуществующее `Area2D.size`.
- `post_overlay.gdshader`: удалённый `SCREEN_TEXTURE` → `hint_screen_texture`.
- `T09_TEST_ROOM` закрывался мгновенно на активации (условие `ENTER_TEST_ROOM` не обрабатывалось в `_evaluate`); `TALK_TO` вообще не считался. Оба условия реализованы + `_documents_read` в save.
- `grants_flag` писем не применялся — `T08`/`T13` были невыполнимы. Теперь флаг ставится при `unlock_email` и `mark_read`.
- Завершённая задача могла реактивироваться и повторно проигрывать свои сюжетные биты.
- `AudioManager.set_tension` пересобирал многосекундный буфер drone при каждом вызове только ради сравнения.
- `OfficeProp` не вызывал `super()`, из-за чего `interact_performed` не доходил до директора.
- Панель TEST_ROOM зависела от возврата `unlock_secret_level()` и могла «закрыться» обратно.
- Mobile: кнопки E/Photo/Pause отсутствовали, не было safe-area, камера цеплялась за тапы по кнопкам, прыжок писал `velocity` в обход `request_jump()`.
- `project.godot`: добавлено отсутствовавшее действие `objective_toggle`; `pause` (P) теперь читается в `game_root.gd`.

Тесты:
- `tests/smoke.tscn` + `tests/smoke.gd` — headless-прогон реального дерева сцены: базы данных, world wiring, офис, фото, компьютер, цепочка заданий, отчёт с фото, 2D-уровень, канон, пауза-аномалия, панель TEST_ROOM, save round trip, финал. **62/62 PASS.**

## Изменения ИТЕРАЦИИ 5 (сделано, НЕ закоммичено)

Расширение тестового покрытия:
- `tests/smoke.gd` вырос с 62 до **221 проверок**: `CameraSystem` и фонарь, все 4 уровня 2D-игры (геометрия, спавн, достижимость цели, согласованность зон, активация бага с учётом гейт-дизайна, старт/стоп, пикапы), horror-приёмники офиса (утечка, переписывание, возврат), галерея фото, `CanonRegistry.validate()`. Добавлены помощники `_world_child_count`, `_find_leaked`, `_all_props_visible`, `_press_action`.
- `tests/boot.gd` + `tests/boot.tscn` — новый тест точки входа: главное меню → `New` → `world.tscn`; проверяет, что офис пригоден для игры, что игрок реально ходит (оси смещаются), вход/выход из компьютера и автосохранение. Драйвер переживает `change_scene_to_file`, оставаясь в корне. **24/24 PASS.**
- В headless клик мышью по `Button` не маршрутизируется, поэтому кнопка меню активируется через `ui_accept` — это ограничение окружения, не бага проекта.

Canon-аудит:
- Все 4 записи канона переписаны: `LTL`, `eight-nine`, `Nine Circles` содержат только наблюдаемые факты, `Чайная религия` — только глоссарий терминов. Непроверяемые утверждения удалены, `safe_facts` у всех `Status.TODO` пуст.
- `CanonRegistry.validate()` — новый метод с инвариантом «`TODO` ⇒ `safe_facts` пуст»; `render_markdown()` печатает только `is_safe()`-факты. Проверяется тестом.

Новые системы и фичи:
- `CameraSystem` (autoload): видоискатель на ПКМ (`camera_viewfinder`), плавная анимация FOV, стабилизация look, корректное восстановление при смене режима игры; снимок доступен при поднятом видоискателе. DL-07 закрыт.
- Фонарь на `flashlight` (F): `Head/Flashlight` в `player.tscn`, переключение света. Действие больше не «мёртвое».
- `CursorWatcher` (autoload) + `evt_ch5_cursor_follow`: пауза-аномалия теперь реально ставит `cursor_followed` через флаг `saw_pause_anomaly`. DL-11 закрыт.
- Настройки: удалён дублирующий ключ `screen_shake`; `fullscreen` применяется через `DisplayServer`, `ui_scale` — через `content_scale_factor`; `Settings` применяет режим окна и масштаб сам по `settings_changed`; панель получила строки «Масштаб интерфейса» и «Полный экран»; `touch_controls` подключён к mobile-контролам.
- `ReportSystem.submit()` эмитит `report_opened` и при повторной отправке уже зарегистрированного бага (раньше — только при первом).
- `post.visible` больше не гасит весь overlay при выключенном grain: при TENSION ≥ 3 включается дисторшн, сканлайны и виньетка остаются.

Компьютер и приложения (найдено в конце ИТЕРАЦИИ 5, критично):
- **Окна приложений не создавались вообще.** `desktop.gd` искал сцены в `APP_SCENES`, заданном ключами-энумами `ComputerSystem.App.*`, а `_on_app_changed()` передаёт строковые id (`"bugtracker"` и т.д.). `Dictionary.has()` со строкой давал `false`, `_ensure_window()` выходил молча — баг-трекер, почта, заметки, файлы и настройки не открывались. Теперь словари задан строковыми id, заголовки берутся из `APP_TITLES`, а неудачная загрузка или инстанцирование сцены пишет `push_error` вместо тихого `return`. Баг не ловился, потому что ни один тест не открывал приложение.
- `mail_app.gd` и `files_app.gd` обращались к `$VBox/Body/Split/...`, а в их сценах узла `Split` нет (есть `VBox/Body/Left` и `VBox/Body/Right`): `@onready` давал `Node not found`, а `mail_app._ready()` падал на `list.item_selected`. Пути исправлены, мёртвый `log_list` удалён.
- `bug_tracker.gd`: повторный выбор уже отправленного бага показывает тред отчёта вместо сырого описания; на `ReportSystem.report_opened` подписан `_on_report_opened`.
- Свип всех `$`-путей и `get_node("...")` по 16 сценам: других битых путей нет.

Прочий долг, закрытый в той же итерации:
- `AudioManager.shutdown()` останавливает все голоса, обнуляет `stream` и чистит `_stream_cache`; вызывается из `_exit_tree()`. Кэш синтезированных WAV больше не живёт до конца процесса.
- Удалён неиспользуемый `player_model.obj` (+ `.import`) — проект действительно без бинарных ассетов.
- `tests/boot.gd`: `WATCHDOG_SECONDS` теперь действительно используется (жёсткий стоп на 25 с), мёртвый хелпер `_first_in_group` удалён.
- `tests/smoke.gd` 207 → **221**: открытие окон всех 5 приложений компьютера, boot-последовательность, «баг-трекер показывает тред отчёта», «у `report_opened` есть живой потребитель», идемпотентный повтор отчёта.

Release:
- `export_presets.cfg` — пресет `Windows Desktop` (x86_64, GL Compatibility, `all_resources`), исключает `tests/`, `docs/`, `memory_bank/`.
- `--export-pack` собирает `build/windows/HorrorGame.pck` (0.44 MB) без единого warning; `/build/` добавлен в `.gitignore`.
- `--export-release` не собирает `.exe`: на машине нет export templates 4.7 (`%APPDATA%\Godot\export_templates\4.7.stable`). Это внешний блокер, а не ошибка пресета.
- Найдена и исправлена сломанная галерея: `gallery.tscn` ссылалась на несуществующий путь родителя, из-за чего при загрузке молча пропадал контейнер сетки. Пути в `gallery.gd` не совпадали с реальной иерархией сцены. Теперь галерея открывается, показывает превью, метаданные, счётчик и закрывается — всё покрыто smoke-проверками.

Документация: синхронизированы `docs/README.md`, `docs/ARCHITECTURE.md`, `memory_bank/*` (автолоады 15 → 17, действия 13, `camera_viewfinder` реализован, тесты 207/24, инвариант канона, сборка релиза).

## Known Issues

Решённые ранее (закрыты в ИТЕРАЦИИ 4-5):

- [x] Константы `SPEED/JUMP_VELOCITY/MOUSE_SENSITIVITY` в `player.gd` — решено в PHASE 1 (`@export`).
- [x] Канон не выдумывается: 4 записи используются только как неоднозначные игровые строки.
- [x] Нет `CameraSystem` (видоискатель/зум/выдержка) — добавлен autoload `CameraSystem`; видоискатель на ПКМ, смена FOV, стабилизация look.
- [x] `cursor_followed` и `evt_ch5_cursor_follow` объявлены, но не реализованы — реализовано через `CursorWatcher` + `saw_pause_anomaly`.
- [x] Действие `flashlight` объявлено в `project.godot`, но фонаря в офисе нет — добавлен `Head/Flashlight`, переключение на F.
- [x] `CanonEntryResource` требует пустой `safe_facts` для `Status.TODO`, а часть TODO-записей заполняла его — аудит выполнен, все 4 записи исправлены, инвариант проверяется `CanonRegistry.validate()` в тесте.
- [x] Дублирующий ключ `screen_shake` в настройках; `fullscreen` и `ui_scale` не применялись — исправлено.
- [x] `ui/photo/gallery.tscn` ссылалась на несуществующий путь родителя, узлы падали при загрузке — исправлено, покрыто тестом.
- [x] Нет export-пресетов — создан `Windows Desktop`, `.pck` собирается чисто.
- [x] Окна приложений компьютера не создавались (`APP_SCENES` ключуется enum'ом) — исправлено, покрыто тестом на все 5 приложений.
- [x] Битые `$`-пути в `mail_app.gd` и `files_app.gd` — исправлены, мёртвый `log_list` удалён.
- [x] `report_opened` без потребителя — подключён в баг-трекере, поведение покрыто тестом.
- [x] `player_model.obj` не используется — удалён вместе с `.import`.

Открытые:

- [ ] `.exe` не собирается: нет export templates 4.7 в `%APPDATA%\Godot\export_templates\4.7.stable`. Нужен `tpz` для 4.7.stable (≈1 GB) либо оформление сборки на стороне CI/машины разработчика. **Внешний блокер.**
- [ ] 12 (smoke) / 18 (boot) объектов `AudioStreamPlaybackWAV` в warnings при принудительном выходе из headless. Проверено экспериментом: `AudioManager.shutdown()` (остановка голосов, обнуление `stream`, чистка `_stream_cache`) плюс 3 кадра перед `quit()` не меняют число — объекты удерживает `AudioServer`, а не проект, и освобождаются только при обработке аудиопотока. Для игры и для тестов безвредно, из GDScript не лечится.
- [ ] Ручной прогон в окне не выполнялся: хоррор-темп, читаемость UI, звук и ощущение от 3D-офиса не проверены человеком. Это последнее, что закрывает DL-14.
- [ ] Нет QA на физическом мобильном устройстве (клавиатура/touch отправляет тот же action, но safe-area и тач-таргеты вживую не проверены).

## Changelog

| Дата | Что | Файлы |
|---|---|---|
| 2026-09-23 | PHASE 0: архитектура, структура, Memory Bank, actions | `docs/*`, `memory_bank/*`, `project.godot`, перемещённые `scenes/*`, `ui/*` |
| 2026-09-23 | PHASE 1: GameManager (modes/routing/mouse) + PlayerController | `systems/game_manager/*`, `scenes/player/player.gd`, `ui/mobile/mobile_controls.gd`, `project.godot` |
| 2026-09-23 | PHASE 2: офис (комната, стол, монитор, клавиатура, мышь, стул, дверь, шкаф, окно, растение, свет) | `scenes/levels/office/office.tscn`, `scenes/levels/world.tscn`, `docs/*`, `memory_bank/*` |
| 2026-09-24 | PHASE 2 fixes: геометрия офиса | `scenes/levels/office/office.tscn` |
| 2026-09-27 | ИТЕРАЦИЯ 4, часть 1: 16 autoload-систем, resource-классы, контент (17/15/4/12/4/20), 2D-игра, компьютер + SubViewport, приложения рабочего стола, UI-сессия, шейдер пост-обработки; устранено 12 parse-ошибок Godot 4.7 | `systems/**`, `data/**`, `minigame/**`, `scenes/game/**`, `ui/**`, `shaders/**` |
| 2026-09-27 | ИТЕРАЦИЯ 4, часть 2: 4 ошибки minigame + `Area2D.size`; smoke-тест 32/44 → 44/44; `ENTER_TEST_ROOM`/`TALK_TO`; `grants_flag`; защита от реактивации задач; canon-quotes | `minigame/minigame.gd`, `minigame/bug_effect.gd`, `minigame/player/player_2d.gd`, `systems/task_system/task_system.gd`, `systems/dialogue/dialogue_system.gd`, `tests/smoke.gd` |
| 2026-09-27 | ИТЕРАЦИЯ 4, часть 3: `OfficeDirector` (4 документа, коллега, панель TEST_ROOM, 2-е рабочее место); тест-покрытие офиса 62/62 | `scripts/office/**`, `scenes/levels/office/office.tscn`, `tests/smoke.gd` |
| 2026-09-27 | ИТЕРАЦИЯ 4, часть 4: 3 слоя адаптивной музыки, устранена пересборка drone-буфера; mobile safe-area + кнопки E/Photo/Pause; `objective_toggle` | `systems/audio/audio_manager.gd`, `ui/mobile/mobile_controls.{gd,tscn}`, `scripts/game_root.gd`, `project.godot` |
| 2026-09-27 | ИТЕРАЦИЯ 4, часть 5: синхронизация docs и Memory Bank | `docs/*`, `memory_bank/*` |
| 2026-09-28 | ИТЕРАЦИЯ 5, часть 1: smoke 62 → 221 проверок (все 4 уровня 2D-игры, камера/фонарь, horror-приёмники, галерея, canon-валидация) | `tests/smoke.gd` |
| 2026-09-28 | ИТЕРАЦИЯ 5, часть 2: новый тест точки входа `tests/boot.tscn` (меню → офис, движение, компьютер, автосохранение), 24/24 | `tests/boot.gd`, `tests/boot.tscn` |
| 2026-09-28 | ИТЕРАЦИЯ 5, часть 3: `CameraSystem` (видоискатель) и фонарь; закрыт DL-07 | `systems/photo/camera_system.gd`, `scenes/player/player.{gd,tscn}`, `project.godot` |
| 2026-09-28 | ИТЕРАЦИЯ 5, часть 4: canon-аудит (4 ресурса) + `CanonRegistry.validate()`; закрыт DL-11 | `data/canon/*.tres`, `systems/story/canon_registry.gd` |
| 2026-09-28 | ИТЕРАЦИЯ 5, часть 5: `CursorWatcher` и `cursor_followed` через `saw_pause_anomaly` | `systems/story/cursor_watcher.gd`, `systems/horror/horror_system.gd`, `data/horror/*` |
| 2026-09-28 | ИТЕРАЦИЯ 5, часть 6: настройки — `fullscreen`, `ui_scale`, `touch_controls`, удалён дубль `screen_shake`; `report_opened` при повторе; `post.visible` не гасит overlay | `systems/settings/settings_system.gd`, `ui/menus/settings_panel.gd`, `ui/mobile/mobile_controls.gd`, `systems/report_system/report_system.gd`, `scripts/game_root.gd` |
| 2026-09-28 | ИТЕРАЦИЯ 5, часть 7: `export_presets.cfg` + чистый `.pck`; найдена и исправлена сломанная `gallery.tscn`/`gallery.gd` | `export_presets.cfg`, `.gitignore`, `ui/photo/gallery.{gd,tscn}` |
| 2026-09-28 | ИТЕРАЦИЯ 5, часть 8: синхронизация docs и Memory Bank, deliverables 67% → 96% | `docs/*`, `memory_bank/*` |
| 2026-09-28 | ИТЕРАЦИЯ 5, часть 9: **баг-релиз-блокер** — окна приложений компьютера не создавались (`APP_SCENES` ключуется enum'ом, роутер передаёт строки); битые `$`-пути в `mail_app.gd` и `files_app.gd`; трекер показывает тред отчёта при повторном выборе; `report_opened` подключён; удалён `player_model.obj`; `AudioManager.shutdown()`; рабочий watchdog в `boot.gd`; smoke 221/221 | `ui/computer/desktop.gd`, `ui/computer/apps/mail_app.gd`, `ui/computer/apps/files_app.gd`, `ui/computer/apps/bug_tracker.gd`, `systems/audio/audio_manager.gd`, `tests/*` |

## Проверка

```powershell
# Импорт/регистрация class_name (обязательно после новых скриптов)
& "D:\Godot 4.7\Godot_v4.7-stable_win64_console.exe" --headless --path "D:\VariousProjects\horror-game" --editor --quit

# Системы, данные, уровни, галерея, канон (ожидается 221/221, RESULT: PASS)
& "D:\Godot 4.7\Godot_v4.7-stable_win64_console.exe" --headless --path "D:\VariousProjects\horror-game" res://tests/smoke.tscn

# Точка входа: главное меню → новая игра → офис (ожидается 24/24, RESULT: PASS)
& "D:\Godot 4.7\Godot_v4.7-stable_win64_console.exe" --headless --path "D:\VariousProjects\horror-game" res://tests/boot.tscn

# Сборка: .pck собирается без templates, .exe требует export templates 4.7
& "D:\Godot 4.7\Godot_v4.7-stable_win64_console.exe" --headless --path "D:\VariousProjects\horror-game" --export-pack "Windows Desktop" build/windows/HorrorGame.pck
& "D:\Godot 4.7\Godot_v4.7-stable_win64_console.exe" --headless --path "D:\VariousProjects\horror-game" --export-release "Windows Desktop" build/windows/HorrorGame.exe
```

## Чек-лист завершения сессии

- [x] Проверен `git status` на неожиданные изменения.
- [x] Обновлены `progress.md` и `activeContext.md`.
- [x] Синхронизированы `docs/README.md` и `docs/ARCHITECTURE.md`.
- [x] Указан новый `last_checked_commit`.