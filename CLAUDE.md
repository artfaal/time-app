# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Что это

RestTimer — персональное watchOS-приложение (таймер отдыха между подходами в зале).
Watch-only, SwiftUI, два таргета: `RestTimer` (апп) и `RestTimerComplication`
(WidgetKit-компликация). Ставится на личные часы через Xcode с бесплатным Apple ID —
никакого App Store. Функциональность и шаги установки — в README.md, план развития
со статусами — в plan.md; оба держим актуальными при изменениях поведения.

## Команды

`xcode-select` указывает на CommandLineTools, поэтому для xcodebuild/simctl нужен
`DEVELOPER_DIR`:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# Сборка под симулятор (без подписи)
xcodebuild -project RestTimer.xcodeproj -scheme RestTimer \
  -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath build build CODE_SIGNING_ALLOWED=NO

# Прогон в симуляторе (UDID смотреть в `xcrun simctl list devices available`)
xcrun simctl boot <udid> && xcrun simctl install <udid> build/Build/Products/Debug-watchsimulator/RestTimer.app
xcrun simctl launch <udid> ru.artfaal.RestTimer
xcrun simctl io <udid> screenshot shot.png   # верификация экранов — скриншотами

# Сборка на реальные часы (подпись Personal Team, часы должны быть разблокированы)
xcodebuild -project RestTimer.xcodeproj -scheme RestTimer \
  -destination 'platform=watchOS,name=Apple Watch — Max' \
  -allowProvisioningUpdates build
```

Тестов нет. Верификация = сборка + прогон цикла в симуляторе со скриншотами
+ установка на часы (⌘R делает пользователь).

## Грабли окружения

- **Бесплатный Apple ID**: подпись живёт 7 дней (еженедельный ⌘R с кабелем);
  bundle ID глобально уникальны на всю Apple — `ru.artfaal.RestTimer.Complication`
  оказался занят, поэтому виджет называется `ru.artfaal.RestTimer.LaunchWidget`.
- **Shared-схема RestTimer** намеренно с выключенным дебаггером
  (`selectedDebuggerIdentifier = ""`): Run ставит и запускает без «Attaching to…».
  Не «чинить».
- **project.pbxproj написан руками** (objectVersion 77, PBXFileSystemSynchronized
  RootGroup): новые файлы в папках подхватываются без правки проекта. Файлы в
  pbxproj не перечислять.

## Архитектура — что нужно понять до правок

Центральная задача аппа — вибрация в конце отдыха при любом состоянии процесса,
**без** собственной workout-сессии (параллельно живёт родное «Тренировка»; система
разрешает одну активную сессию, наша убила бы её). Отсюда трёхканальная схема:

1. **Апп активен** — `.task(id: model.phase)` в SessionView спит до `end-10` и
   `end` и зовёт `model.restDeadlineTick()`; апп вибрирует сам
   (`WKInterfaceDevice`). Никакого поллинга.
2. **Апп заморожен** (рука опущена) — вибрируют заранее запланированные локальные
   уведомления (`NotificationManager.scheduleRestEnd`: warning в `end-10`, серия
   в `end`/`+2.5`/`+5`).
3. **Пробуждение** — `onChange(scenePhase)` зовёт `model.catchUp()`: догоняет
   состояние по фактическому времени **молча** (уведомления уже отвибрировали).

Инварианты этой схемы (ломаются легко, чинились код-ревью):

- `willPresent` в RestTimerApp возвращает `[]` **только** при
  `applicationState == .active`; в always-on (frontmost-but-inactive) уведомление
  обязано показаться — его вибрация там единственная.
- Любая смена `model.phase` (включая `adjustRest`) пересоздаёт `.resting` →
  `.task(id:)` перезапускается и дедлайны/уведомления пересинхронизируются сами.
  Новые механизмы времени строить на этом же принципе, а не на таймерах.
- Серии вибраций — только через `playHaptics()` (отменяемый `hapticsTask`);
  скип/новый подход/выход обрывают недоигранное.
- `cancelAll()` сносит все уведомления аппа разом (апп других не шлёт);
  стартовая чистка в `applicationDidFinishLaunching` обязательна — уведомления
  переживают смерть процесса.

## Конвенции UI (watchOS-специфика, выстрадано)

- Тикающие в AOD элементы — только системные (`Text(timerInterval:)`).
  Самонарисованное (кольцо отдыха `PhaseRing` из `Views/Theme.swift`, рисуется
  через `TimelineView`) прячется при `isLuminanceReduced`.
- Дизайн-токены (цвета фаз, фоновые градиенты) и геометрия колец — в
  `Views/Theme.swift` (направление 1e «Радиальный / арка»). Кольца изначально
  выведены из SVG-эталона хэндоффа (viewBox 200, r=88), затем по просьбе
  пользователя сознательно укрупнены ~×1.2 (экран Ultra на максимум: кольца
  почти во всю ширину, поля ужаты) — пропорции 1e при этом сохранены. Актуальные
  числа — только в `Views/Theme.swift`, не выдумывать. Эталонные ассеты —
  `/Users/artfaal/Downloads/handoff-RestTimer-1e`; при сверке сравнивать
  пропорции, а не абсолютные размеры.
- Экраны сессии обёрнуты в полноэкранные `Button` ради Double Tap
  (`.handGestureShortcut(.primaryAction)`, один на экран). Побочка: внешние
  жесты поверх кнопок вешать через `.simultaneousGesture` (long-press) или
  `.highPriorityGesture` (свайп) — обычные модификаторы кнопка съедает.
- Digital Crown биндить в локальный `@State` Double и синхронизировать через
  `.onChange`; биндинг с get/set в `@AppStorage` создаёт петлю и ломает
  накопление поворота. Крутить «шагами» (1 щелчок = 1 шаг), не секундами.
- Колесо на отдыхе: мёртвая зона ~1.5 щелчка + превью дельты + применение через
  0.8 сек — числа подобраны пользователем на железе, без запроса не менять.
- UI-строки на русском; фаза кодируется цветом всего экрана (работа —
  зелёный, отдых — оранжевый).
