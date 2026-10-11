---
name: Баг
about: Сообщить об ошибке в игре
title: "[баг] краткое описание"
labels: bug
assignees: []
---

## Описание

Что произошло? Что вы ожидали и что увидели на самом деле.

## Как воспроизвести

1. ...
2. ...
3. ...

## Платформа

- [ ] Windows (`build/windows/HorrorGame.exe`)
- [ ] Android (`build/android/HorrorGame-debug.apk`)
- Пакет на Android (если приложимость): `com.lucasteamalt12321.horrorgame`
- Версия сборки / дата APK (если известно):

## Ожидаемое поведение

...

## Фактическое поведение

...

## Скриншот / видео

Для визуальных багов (текстуры, хитбоксы, детализация) скриншот обязателен — приложите в issue.

## Лог / системная информация

- Сейв: файл из `user://saves/` (Windows: `%APPDATA%\Godot\app_userdata\HorrorGame\saves\`, Android: каталог files пакета)
- Лог Windows: `%APPDATA%\Godot\app_userdata\HorrorGame\logs\godot.log`
- Лог Android: `adb logcat -s godot:V`
- Краш Android: `adb shell dumpsys dropbox --print` (записи `data_app_native_crash`)

## Дополнительно

- Воспроизводится: всегда / иногда / один раз
- Ещё что-то важное? ...