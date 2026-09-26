# Codex снова подключается после переезда CLI в ChatGPT.app

## Цель

Вернуть мониторинг Codex. После обновления Codex встроился в ChatGPT.app, и Pulse показывает «Codex CLI is not installed», хотя CLI на машине есть.

## Результат для пользователя

Блок Codex в обзоре, строке меню и виджете снова показывает окна лимита. Следующее обновление, которое опять перенесёт CLI, не должно ломать Pulse молча.

## Контекст

Диагностика Claude Code от 2026-09-26:

- `ExecutableLocator.locate("codex")` в `Sources/CodexPulse/Services/CommandRunner.swift` проверяет `/Applications/ChatGPT.app/Contents/Resources/codex`. Этого файла больше нет.
- Новая раскладка (Codex CLI 0.158.0-alpha.2.1, ChatGPT.app 154.0.8037.57):
  - `/Applications/ChatGPT.app/Contents/Resources/codex-cli/codex-package.json` — `{"layoutVersion":1, "entrypoint":"bin/codex", "resourcesDir":"codex-resources", "pathDir":"codex-path", ...}`;
  - `.../codex-cli/bin/codex` — shell-обёртка, делает `exec` в `.../codex-cli/CodexCLI.app/Contents/MacOS/codex`;
  - `codex app-server` в этой версии есть.
- В PATH (`/opt/homebrew/bin`, `/usr/local/bin`) `codex` нет. `~/.codex/bin` не содержит `codex`.
- Правила проекта: `AGENTS.md` (официальный App Server, read-only, CodexBar только как явный fallback).
- CodexBar CLI (`codexbar`) на машине тоже отсутствует. Brew числит cask 0.49.1, приложения нет. Это нормально: Claude идёт через Pulse Connector. В рамках этой задачи CodexBar не трогать.

Проверить вживую, а не по этому тексту: что `account/rateLimits/read` и `account/usage/read` через App Server новой версии отвечают в прежнем формате.

## Изменить

- `ExecutableLocator` для `codex`:
  1. если задана переменная окружения `CODEX_PULSE_CODEX_PATH`, использовать её;
  2. `/Applications/ChatGPT.app/Contents/Resources/codex-cli/codex-package.json` → `entrypoint` относительно этой папки; то же для `~/Applications/ChatGPT.app`;
  3. прямые пути `.../codex-cli/bin/codex` и `.../codex-cli/CodexCLI.app/Contents/MacOS/codex`;
  4. старые пути, включая `/Applications/Codex.app/...`, если он был, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`;
  5. поиск по `PATH` процесса.
- Сообщение об ошибке: вместо «Codex CLI is not installed» перечислить проверенные места и подсказать `CODEX_PULSE_CODEX_PATH`. RU и EN.
- Если формат ответа App Server изменился — адаптировать парсинг в `CodexAppServerProvider.swift`, не ломая старый формат.
- Тесты на новую раскладку (фикстура с `codex-package.json`) и на приоритет путей.
- Строка в `CHANGELOG.md` и в статусе `00_НАЧАТЬ_ЗДЕСЬ.md`.

## Не трогать

- Незакоммиченные правки пользователя в `ResetSignalMonitor.swift`, `ResetSignalCard.swift`, `SettingsView.swift`, `ResetSignalMonitorTests.swift`, `design-qa.md`. Работать поверх них, не откатывать и не смешивать с этой задачей в одном коммите.
- Клон `../Codex Pulse Public` (там свои незакоммиченные правки). Перенос исправления туда — отдельной задачей после согласования.
- Claude-провайдеры, Pulse Connector, CodexBar-мост.
- Коммиты, push, релизы и публикацию делать только по отдельной команде пользователя.

## Проверить

- `Scripts/test.sh`, затем `swift build`.
- Живой запуск: собранный Pulse показывает Codex подключённым с реальными процентами. Ошибочное состояние: при `CODEX_PULSE_CODEX_PATH=/nonexistent` Pulse показывает понятную ошибку с перечнем путей.
- `git diff` только по файлам задачи.
- Установка: `Scripts/install-from-source.sh`. Он сам сохраняет прежнюю версию как `~/Applications/Codex Pulse.backup.<дата>.app`.

## Откат

Вернуть `~/Applications/Codex Pulse.app` из последнего бэкапа, созданного `install-from-source.sh`, и откатить изменённые файлы задачи через `git checkout -- <файлы>` (не трогая чужие незакоммиченные правки).
