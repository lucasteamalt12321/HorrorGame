# System Patterns — HorrorGame

## Архитектурные принципы

- **Не монолит.** Системы делятся по ответственности; нет единого «god script».
- **Слои зависимостей** направлены вниз к core-системам. Сцены вызывают системы; системы не управляют чужими сценами напрямую.
- **Разделение срезов** (правило 5 ТЗ): gameplay / UI / story / data / audio — не смешиваются в одном узле. Если система затрагивает несколько срезов — выделяется менеджер/интерфейс.
- **Данные отдельно от логики** (правило 6): контент (баги, задания, диалоги) — `Resource` в `res://data/`, а не хардкод.
- **Story Flags централизованы** (правило 8): сюжетные флаги живут в `StoryFlags`; сцены их только читают/устанавливают через API.

## Паттерн «Менеджер»

Каждый горизонтальный срез имеет менеджера-автозагрузчика или single-node:
`GameManager`, `InteractionSystem`, `BugSystem`, `ReportSystem`, `TaskSystem`, `StoryFlags`, `SaveSystem`, `HorrorSystem`, `AudioManager`, `CameraSystem`.

Общий профиль менеджера:
- `class_name` + `extends Node`;
- автозагрузка через `project.godot` (autoload) для систем доступа из любой сцены;
- только своя ответственность; публичные методы вместо прямого доступа к нодам.

## Модель «вложение 2D-игры»

```
PlayerInput (контекст про разный ввод)
  → GameManager.mode (explore | computer | minigame | blocked)
  → роутинг ввода в активную систему
Monitor:
  SubViewport (pixel resolution, scaling ≈ 3)
    → Minigame (Node2D platformer scene)
  → ViewportTexture → материал экрана монитора
```

Ввод никогда не должен попадать одновременно и в Player, и в Minigame.

## Механика «Баг → Доказательство → Отчёт»

1. `BugTrigger` (в 2D-сцене) сообщает `BugSystem: bug_appeared(id)`.
2. Игрок делает фото → `CameraSystem` проверяет попадание объекта бага в кадр → `PhotoEvidence`.
3. `evidence_ready` → игрок может оформить отчёт через `ReportSystem`.
4. `ReportSystem` помечает баг, учёт ведёт `TaskSystem`.
5. Завершение цепочки заданий двигает сюжет (`StoryFlags`).

## Хоррор-система

- Шкала напряжения `TENSION_0..5` управляется `HorrorSystem`; события запускаются по `StoryFlags`, а не по «случайности».
- События бывают: light, audio, object jump, text mutation, npc behavior, 2D-leak, off-screen events.
- Все события контролируемые (правило: не ломать прохождение). Скримеры редкие.

## Паттерн данных

- `BugResource` / `TaskResource` — `class_name … extends Resource` в `data/`.
- Реестры: `BugDB` (грузит все `data/bugs/*.tres`), `TaskDB`.
- Сохранение: `SaveSystem` пишет версионированный `Dictionary` (schema_version), устойчивый к миграциям.

## Правило «не дублировать» (правило 4)

Перед созданием новой системы — проверить `systems/` и `scripts/` на аналоги. Например, не писать вторую систему взаимодействия, когда есть InteractionSystem.