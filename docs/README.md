# HorrorGame — структура проекта

Горизонтальный срез документации проекта. Отдельного README в корне репозитория нет — здесь точка входа в документацию.

## Документация

- [ARCHITECTURE.md](ARCHITECTURE.md) — архитектура, системы, цикл, форматы данных, input actions, ограничения.
- [../memory_bank/projectbrief.md](../memory_bank/projectbrief.md) — цели, рамки, `Project Deliverables` (канонический источник прогресса).
- [../memory_bank/activeContext.md](../memory_bank/activeContext.md) — текущий фокус и следующие шаги.
- [../memory_bank/systemPatterns.md](../memory_bank/systemPatterns.md) — паттерны: Manager, Director, condition_kind, единый ввод, headless-тест.
- [../memory_bank/techContext.md](../memory_bank/techContext.md) — стек, autoload-ы, input actions, команды проверки.
- [../memory_bank/progress.md](../memory_bank/progress.md) — статус, Known Issues, Changelog, `last_checked_commit`.

## Описание проекта

3D-хоррор от первого лица с вложенной 2D-игрой. Игрок — QA-тестировщик, работающий с 2D-проектом на рабочем компьютере. Основной цикл: задание → компьютер → 2D-игра → обнаружение бага → фото-доказательство → отчёт → новое задание → сюжетный хоррор.

Движок: Godot 4.7, GDScript, GL Compatibility renderer, Jolt Physics. Весь контент процедурный (17 багов, 15 заданий, 4 уровня, 12 писем, 20 хоррор-событий, 4 записи канона), бинарных ассетов нет. 17 autoload-систем, 13 input actions, версия `0.1.0`.

## Сборка релиза

Пресет `Windows Desktop` лежит в `export_presets.cfg`, результат — `build/windows/HorrorGame.exe`.

```powershell
& "D:\Godot 4.7\Godot_v4.7-stable_win64_console.exe" --headless --path "D:\VariousProjects\horror-game" --export-release "Windows Desktop" build/windows/HorrorGame.exe
```

Требуются export templates версии 4.7 (`%APPDATA%\Godot\export_templates\4.7.stable`); без них Godot собирает только `.pck` через `--export-pack`.

## Проверка проекта

```powershell
# импорт ресурсов и регистрация class_name
& "D:\Godot 4.7\Godot_v4.7-stable_win64_console.exe" --headless --path "D:\VariousProjects\horror-game" --editor --quit
# системы и данные: 226 проверок
& "D:\Godot 4.7\Godot_v4.7-stable_win64_console.exe" --headless --path "D:\VariousProjects\horror-game" res://tests/smoke.tscn
# точка входа: главное меню → новая игра → офис → компьютер: 34 проверки
& "D:\Godot 4.7\Godot_v4.7-stable_win64_console.exe" --headless --path "D:\VariousProjects\horror-game" res://tests/boot.tscn
```

Оба теста печатают `RESULT: PASS` и вызывают `quit(0)`; ненулевой код возврата означает провал.

`boot.tscn` проверяет компьютер так, как им пользуется игрок: подойти, нажать E, дождаться загрузки, кликнуть по иконке мышью и выйти по ESC. Клик идёт через `Input.parse_input_event` — тот же путь, что у настоящего указателя; `Viewport.push_input` кормит только локальный GUI и никогда не доходит до `_input` узлов, поэтому для интеграционных проверок он не годится.
