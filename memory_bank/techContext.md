# Tech Context — HorrorGame

## Стек и окружение

- **Движок:** Godot 4.7.x (features: `4.7`, `GL Compatibility`).
- **Язык:** GDScript (встроенный).
- **Рендерер:** `gl_compatibility` (desktop + mobile). Преимущество — совместимость с SubViewport 2D, низкие требования.
- **Виндовый драйвер:** `d3d12` (`rendering_device/driver.windows="d3d12"`) — переопределён только для Windows.
- **Физика:** Jolt Physics (`3d/physics_engine="Jolt Physics"`).
- **Аудио:** без бинарных файлов — все SFX/музыка синтезируются в рантайме (`AudioStreamWAV`, 44.1 кГц, 16-бит).
- **Платформы:** Windows (релиз) + Android (релиз) + мобильное управление через touch-контролы (UI, джойстик, кнопки) с безопасной зоной.
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

# 2. Системы, данные, уровни, галерея, канон (ожидается "226/226 checks passed" + "RESULT: PASS")
& "D:\Godot 4.7\Godot_v4.7-stable_win64_console.exe" --headless --path "D:\VariousProjects\horror-game" res://tests/smoke.tscn

# 3. Точка входа: меню → офис → компьютер (ожидается "34/34 checks passed" + "RESULT: PASS")
& "D:\Godot 4.7\Godot_v4.7-stable_win64_console.exe" --headless --path "D:\VariousProjects\horror-game" res://tests/boot.tscn
```

- У обоих тестов внутренний watchdog 25 с; внешний timeout в CI — 60 с (smoke) и 60 с (boot).
- При принудительном выходе headless печатается warning о `AudioStreamWAV`/`AudioStreamPlaybackWAV` в кэше сессии — не регрессия, подтверждено `--verbose`.
- Мышь в headless работает, если событие подаётся через `Input.parse_input_event`; `Viewport.push_input` до `_input` узлов не доходит (только локальный GUI). Координаты задаются в пикселях окна — движок применяет трансформ content-scale, который в headless равен `окно / 1280` (напр. 0.05 при окне 64×64). Указатель в headless устроен как настоящий, поэтому клики проверяются по всей цепочке.

## Сборка и релиз

- Пресеты в `export_presets.cfg`:
  - `Windows Desktop` — x86_64, GL Compatibility, `export_filter="all_resources"`, `exclude_filter="tests/*, docs/*, memory_bank/*"`, выход `build/windows/HorrorGame.exe`, версия `0.1.0`.
  - `Android` — universal APK, `build/android/HorrorGame.apk`. Архитектуры `armeabi-v7a`/`arm64-v8a`/`x86`/`x86_64`, `gradle_build/use_gradle_build=false` (готовые templates, NDK не нужен), `package/signed=true` (debug-keystore → ставится через `adb install`), `package/unique_name="com.lucasteamalt12321.horrorgame"`, `package/app_category=1`, `version/code=1`, `version/name="0.1.0"`, `screen/immersive_mode=true`, `screen/edge_to_edge=true`, `screen/support_{small,normal,large,xlarge}=true`, `screen/background_color` = clear color проекта, `splash_screen/disable_godot_boot_splash=true` (совпадает с `boot_splash/show_image=false`), `launcher_icons/*` из `res://icon.svg` (adaptive background пуст), `texture_format/{s3tc_bptc,etc2_astc}=true`, `permissions/custom_permissions` пуст, `keystore/*` пуст.
- Ориентация — проектная настройка, в 4.7 в пресете её нет: `display/window/handheld/orientation=4` в `project.godot` = `Sensor Landscape` (enum: 0 Landscape, 1 Portrait, 2 Reverse Landscape, 3 Reverse Portrait, 4 Sensor Landscape, 5 Sensor Portrait, 6 Sensor). Портрет не используется: 3D-офис и 2D-игра в мониторе рассчитаны на альбом.
- Мобильный ввод не дублируется: `input_devices/pointing/emulate_mouse_from_touch` по умолчанию `true` и нужен, чтобы touch работал в UI компьютера. `display/window/energy_saving/keep_screen_on` по умолчанию `true`.
- `/build/` и `/android/` в `.gitignore` — артефакты сборки и каталог gradle-исходников не коммитятся.
- `--export-pack` работает без дополнительных зависимостей: `build/windows/HorrorGame.pck` (~0.45 MB), 0 warning.
- `--export-release` **требует export templates 4.7** в `%APPDATA%\Godot\export_templates\4.7.stable` (файлы `windows_debug_x86_64.exe`, `windows_release_x86_64.exe`, `android_debug.apk`, `android_release.apk`). На текущей машине их нет — установка `tpz` (≈1 GB) или CI со скачиванием шаблонов.
- Android дополнительно требует Java SDK 17+ и Android SDK (`platform-tools` + `build-tools` c `apksigner`); пути задаются в Editor Settings → Export → Android. На машине есть только `C:\Android\platform-tools\adb.exe` (1.0.41) — `build-tools`, platforms и JDK отсутствуют, поэтому `--export-release "Android"` доходит до проверки пресета и падает на этих зависимостях, а не на самом пресете.
- Сборка только на ПК: `git pull` на телефоне синхронизирует код, но Godot 4.7 Android Editor экспериментальный и не заменяет ПК-сборку.
- Проверка Android-конфигурации без зависимостей: `--export-release "Android" <tmp>.apk` — пресет должен узнаваться (иначе `Unknown export preset`), а ошибки должны быть только про templates/JDK/SDK.
- **Устройство для QA:** Infinix X6873, Android 16 (SDK 36), `arm64-v8a`, Mali-G615 MC6, OpenGL ES 3.2, серийник `143332559S104172`. Проект разворачивается вручную в `/sdcard/HorrorGame` и запускается Godot 4.7 Android Editor `org.godotengine.editor.v4`; отдельного APK на устройстве нет.
- **Тулчейн установлен (03.10.2026), внешний блокер DL-16 по зависимостям снят.** export templates 4.7 в `%APPDATA%\Godot\export_templates\4.7.stable` (35 файлов), JDK 17 в `C:\Android\jdk17\jdk-17.0.20.1+1`, Android SDK в `C:\Android` (`build-tools` 34/35/36, `platforms;android-36`, `platform-tools`), cmdline-tools в `C:\Android\cmdline-tools\latest`, debug-keystore в `%APPDATA%\Godot\keystores\debug.keystore` (alias `androiddebugkey`, storepass `android`). Пути прописаны в **`editor_settings-4.7.tres`**, не в `-4.4` — Godot 4.7 читает только свой файл, и это стоило нескольких неудачных попыток экспорта.
- Три настройки, без которых экспорт Android падает, и каждая диагностируется только по тексту ошибки:
  1. `rendering/textures/vram_compression/import_etc2_astc=true` в `project.godot` — иначе «Для экспорта под Android требуется сжатие текстур ETC2/ASTC». Включение заставляет переимпортировать все текстуры.
  2. `gradle_build/min_sdk` и `gradle_build/target_sdk` в `export_presets.cfg` должны быть пустыми, пока `use_gradle_build=false`, иначе «Целевой SDK можно переопределить, только если включён параметр "Использовать сборку Gradle"».
  3. Нужен `build-tools`, версия которого совпадает с целевым SDK: при `target_sdk=""` Godot берёт значение по умолчанию и требует соответствующий `build-tools` (34.0.0 не подошёл, понадобились 35.0.0 и 36.0.0).
- `--export-debug "Android"` даёт подписанный APK, готовый к `adb install -r` (109.9 MB, universal 4 ABI). `--export-release` требует release-keystore; для QA достаточно debug.
- Редактор при пересохранении `project.godot` затирает секцию `[debug]` и дописывает `[editor_plugins]`. После любого запуска редактора/экспорта `git diff -- project.godot` нужно проверять и откатывать churn, иначе в коммит уедет удаление `gdscript/warnings/unsafe_*=0`.
- В рабочем дереве есть неотслеживаемые `addons/copy_all_errors/` и `tools/check_plugin_install.gd` — посторонние, не коммитятся и не удаляются без решения владельца.
- **Инвариант привязки текстуры монитора проверяется тестом, а не глазами.** `Screen.material_override` обязан быть `ShaderMaterial` с непустым `shader`, а параметр `screen_texture` — `ViewportTexture`, чей `viewport_path` указывает на `ScreenViewport`; сам `SubViewport` обязан иметь `UPDATE_ALWAYS` и содержать инстанс `Desktop`. Проверки в `tests/smoke.gd` (8 штук). Смысл: непривязанный `sampler2D` в `shaders/monitor.gdshader` возвращает белое, `EMISSION` уходит в 1.69, полосы сканлайнов и glow окрашивают это в розовый — ровно тот симптом, что игрок видел на Android.
- **Свойство `ViewportTexture` называется `viewport_path` (NodePath), метода `get_viewport_path()` нет.** Ошибка вызова даёт `Invalid call. Nonexistent function`, а `_check` после него не вызывается — smoke падает по watchdog «test did not finish in 25s» с 21/22, а не с внятным сообщением. Любая новая проверка с вызовом несуществующего метода даёт такой же неочевидный симптом.
- **Где смотреть нативные краши без логгера:** `adb shell dumpsys dropbox --print data_app_native_crash`. Это единственный источник, который переживает перезапуск процесса — `logcat` к моменту разбора уже ротирован. Поле `Process-Runtime` в заголовке Dropbox — реальное время жизни процесса в миллисекундах; `Process uptime` в самом tombstone относится к системе и вводит в заблуждение (в нашем случае читался как 76-84 с, на деле 6.0-6.5 с). Записи `AudioTrack` с `SIGSEGV` в `libgodot_android.so` означают порчу кучи в аудиопотоке Godot, а не ошибку скрипта.

