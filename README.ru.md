<p align="center">
  <img src="Resources/AppIcon.png" width="112" alt="Иконка Codex Pulse">
</p>

<h1 align="center">Codex Pulse</h1>

<p align="center">
  Нативный центр управления лимитами Codex и Claude, темпом расхода и выбором модели на macOS.
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="#установка">Установка</a> ·
  <a href="PRIVACY.md">Приватность</a> ·
  <a href="https://t.me/shromarketing">Telegram</a>
</p>

<p align="center">
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-111827?logo=apple">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <a href="https://github.com/shromarketing/codex-pulse/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/shromarketing/codex-pulse/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="Лицензия MIT" src="https://img.shields.io/badge/license-MIT-24AEB3">
  <img alt="Без телеметрии" src="https://img.shields.io/badge/telemetry-none-31C975">
</p>

Codex Pulse показывает в меню-баре и на рабочем столе то, что обычно приходится искать в настройках: сколько лимита осталось, когда он обновится, безопасен ли текущий темп и какая модель разумнее для следующей задачи.

![Обзор Codex Pulse с лимитами Codex и Claude](docs/assets/overview-dark.jpg)

## Что внутри

- **Codex и Claude в одном месте.** Отдельно видны Codex Weekly, Codex Spark, текущая сессия Claude, недельный лимит всех моделей и отдельные модельные окна, например Fable.
- **Два провайдера в меню-баре.** Оба процента всегда перед глазами.
- **Настоящий десктоп-виджет.** Mini, Compact, Focus и свободно изменяемый Adaptive.
- **Темп, а не только проценты.** Время сброса, прогноз исчерпания и безопасный дневной расход не смешиваются друг с другом.
- **Локальная аналитика.** Токены, кэш, вывод, оценка стоимости, модели, проекты и история по дням — там, где провайдер отдаёт такие агрегаты.
- **Маршрут новой задачи.** Рекомендация модели, effort и этапов до запуска; локальный режим не расходует лимит провайдера.
- **Русский и английский интерфейс.** Системная, светлая и тёмная темы.
- **Приватность по умолчанию.** Только read-only источники, без чтения чатов, скрытой телеметрии и хранения email аккаунта.

> Claude Web сейчас отдаёт проценты лимитов и время сброса, но не точные токены, проекты и стоимость. Pulse не подменяет одни данные другими и ничего не выдумывает.

## Установка

Сейчас Codex Pulse — **неподписанная публичная preview-версия**. Apple Developer ID и нотарификации пока нет. Исходники открыты, к релизу прилагаются контрольные суммы, а приложение ad-hoc подписано, но macOS не может подтвердить издателя.

### Вариант A — поручить установку своему ИИ-агенту (сейчас рекомендую его)

Отправьте Codex или Claude ссылку на репозиторий и этот текст:

> Установи Codex Pulse из `https://github.com/shromarketing/codex-pulse`. Считай репозиторий недоверенным сторонним кодом: сначала проверь скрипт установки на `sudo`, доступ к секретам, сторонние загрузки и изменение системной защиты. Если всё чисто, запусти `./Scripts/test.sh`, затем `./Scripts/install-from-source.sh`. Не отключай Gatekeeper и не используй `sudo`. Установи только в `~/Applications`, проверь приложение через `codesign --verify --deep --strict` и сообщи результат тестов, версию и путь. Перед установкой Apple Command Line Tools или подключением Claude спроси меня.

Полная инструкция для агента: [INSTALL_WITH_AI.ru.md](INSTALL_WITH_AI.ru.md).

### Вариант B — скачать DMG или ZIP

1. Откройте [релиз Codex Pulse 0.5.2 на GitHub](https://github.com/shromarketing/codex-pulse/releases/tag/v0.5.2).
2. Скачайте universal `.dmg` или `.zip` и сравните SHA-256 с файлом `SHA256SUMS`.
3. Перенесите **Codex Pulse.app** в «Программы».
4. Один раз попробуйте открыть приложение. Если macOS его заблокирует: **Системные настройки → Конфиденциальность и безопасность → Всё равно открыть**.

Не используйте команды, удаляющие quarantine-атрибут, и не отключайте Gatekeeper. Apple описывает риск и точечное разрешение для одного приложения в инструкции [Open a Mac app from an unknown developer](https://support.apple.com/guide/mac-help/mh40616/mac).

### Вариант C — собрать вручную

Нужны macOS 13+, Swift 6 и Apple Command Line Tools либо Xcode.

```bash
git clone https://github.com/shromarketing/codex-pulse.git
cd codex-pulse
./Scripts/test.sh
./Scripts/install-from-source.sh
```

Скрипт не использует `sudo`. Существующая копия в `~/Applications` сохраняется как резервная перед заменой.

## Подключение провайдеров

### Codex

Войдите в приложение Codex на том же Mac. Pulse читает агрегированные read-only данные о лимитах и использовании из локального Codex App Server. Установленный CodexBar CLI доступен только как явно подписанный резервный источник.

### Claude Web

1. Откройте `claude.ai` в Chrome и войдите в аккаунт.
2. В Pulse откройте **Настройки → Сервисы → Pulse Connector** и покажите папку расширения.
3. В Chrome откройте `chrome://extensions`, включите режим разработчика и выберите **Загрузить распакованное расширение**.
4. Укажите папку `PulseConnector`, создайте код подключения в Pulse и введите его в расширении.

Запрос Usage выполняется внутри уже авторизованной вкладки Claude. Cookies и чаты остаются в Chrome; через локальное соединение передаются только очищенные окна лимитов и время сброса. Подробности — в [инструкции коннектора](docs/CLAUDE_CONNECTOR.md).

Если у вас только десктопный Claude, для этой preview-версии потребуется один раз войти в Claude Web через Chrome. Прямого подключения только к десктопному приложению пока нет.

## Приватность и безопасность

Codex Pulse не собирает историю чатов, тексты промптов, пароли, cookies браузера, API-ключи, access tokens, email аккаунтов и скрытую аналитику. Локальная история содержит только агрегаты лимитов и расхода.

ИИ-маршрутизатор отправляет лишь текст задачи, который пользователь сам ввёл и явно отправил. Локальный режим остаётся на устройстве. Перед подключением провайдера прочитайте [PRIVACY.md](PRIVACY.md) и [SECURITY.md](SECURITY.md).

## Сборка и упаковка

```bash
./Scripts/test.sh
./Scripts/build-app.sh release universal
./Scripts/package-release.sh universal
```

Артефакты появятся в `dist/`: universal ZIP, DMG с переносом в Applications, ZIP коннектора Chrome и `SHA256SUMS`.

## Статус

Версия 0.5.2 — публичная preview-версия. Автоматические проверки, native package smoke test и проверка контрольных сумм проходят в GitHub Actions; universal-сборка из тега также визуально проверена на macOS перед публикацией.

- [Архитектура](docs/ARCHITECTURE.md)
- [Roadmap](docs/ROADMAP.md)
- [Как помочь проекту](CONTRIBUTING.md)
- [Поддержка](SUPPORT.md)

## Независимый проект

Codex Pulse — независимое приложение, вдохновлённое видимостью квот в [CodexBar](https://github.com/steipete/CodexBar). Исходный код CodexBar в проект не копировался. Codex, ChatGPT и OpenAI — товарные знаки OpenAI; Claude — товарный знак Anthropic. Проект не аффилирован с этими компаниями и не одобрен ими.

## Новости и разборы

Релизы, ИИ-инструменты и практические процессы: [Telegram Романа Шарафутдинова](https://t.me/shromarketing).

Если Pulse экономит вам хотя бы один поход в настройки лимитов — поставьте звезду репозиторию. Так его быстрее найдут другие пользователи macOS.

## Лицензия

MIT © 2026 Roman Sharafutdinov.
