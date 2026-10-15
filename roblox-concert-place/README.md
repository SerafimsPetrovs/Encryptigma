# Virtual Concert Place — концепция и каркас

Плейс в Roblox как инструмент промоушена виртуальной музыкальной группы: стадион со сценой,
регулярные концерты по расписанию, открытая сцена для игроков в остальное время и режим съёмки
вертикального видео под TikTok.

Папка содержит две вещи: документы с планом и рабочий каркас кода для Roblox Studio.

## Документы

| Файл | О чём |
| --- | --- |
| [docs/01-concept.md](docs/01-concept.md) | Продуктовая концепция, петля вовлечения, зачем это группе |
| [docs/02-architecture.md](docs/02-architecture.md) | Архитектура плейса, структура карты, что уже есть в коде |
| [docs/03-music-and-show.md](docs/03-music-and-show.md) | Синхронизация музыки, таймлайн шоу, риггинг и липсинк |
| [docs/04-open-stage.md](docs/04-open-stage.md) | Открытая сцена: очередь, слоты, модерация, антиспам |
| [docs/05-monetization.md](docs/05-monetization.md) | Экономика: цены, расчёты, что Roblox запрещает |
| [docs/06-marketing-tiktok.md](docs/06-marketing-tiktok.md) | Воронка, контент-план, вирусные механики, коллаборации |
| [docs/07-performance-limits.md](docs/07-performance-limits.md) | Технические ограничения Roblox и способы их обойти |
| [docs/08-policy-moderation.md](docs/08-policy-moderation.md) | Правила платформы, текст песен, права, возрастной рейтинг |
| [docs/09-roadmap.md](docs/09-roadmap.md) | Пошаговый план по фазам с критериями готовности |
| [docs/10-metrics.md](docs/10-metrics.md) | Какие метрики считать и какие значения считать нормой |

## Каркас кода

Структура разложена под [Rojo](https://rojo.space): `default.project.json` собирает исходники
в дерево Roblox. Можно работать и без Rojo — вручную перенести файлы по тем же путям.

```
src/shared   -> ReplicatedStorage/Shared          (ModuleScript)
src/server   -> ServerScriptService/Concert       (Script + modules)
src/client   -> StarterPlayer/StarterPlayerScripts/Concert (LocalScript)
```

| Модуль | Назначение |
| --- | --- |
| `shared/ShowConfig.luau` | Единственное место с сетлистом, кью, ценами, id продуктов |
| `shared/MusicClock.luau` | Общие часы и расчёт долей такта |
| `shared/Net.luau` | Создание и поиск RemoteEvent/RemoteFunction |
| `shared/ClientBus.luau` | Локальная шина событий внутри клиента |
| `server/Bootstrap.server.luau` | Запуск сервисов и обработчики покупок |
| `server/modules/ShowDirector.luau` | Расписание концертов, объявление треков |
| `server/modules/StageQueue.luau` | Очередь на открытую сцену, слоты, эффекты, модерация |
| `server/modules/Monetization.luau` | `ProcessReceipt`, геймпассы, идемпотентность покупок |
| `server/modules/Profiles.luau` | DataStore: оплаченные выходы, билеты, рейтинг |
| `server/modules/VipAccess.luau` | Доступ в VIP и первый ряд, серверная проверка |
| `server/modules/SafeText.luau` | Фильтрация пользовательского текста |
| `server/modules/Anchors.luau` | Точки телепортации на карте |
| `client/ShowRunner.client.luau` | Воспроизведение музыки, кью света, пиро, экранов |
| `client/StageUI.client.luau` | HUD: очередь, VIP, реакции, панель перформера |
| `client/CinemaMode.client.luau` | Режим съёмки 9:16, операторские планы, скриншот |
| `client/CrowdLod.client.luau` | Локальная массовка и LOD |

### Что нужно сделать перед первым запуском

1. Загрузить трек в Roblox (от лица группы, владеющей плейсом) и вписать `rbxassetid` в `ShowConfig.Songs`.
2. Создать Developer Products и Game Pass, вписать их id в `ShowConfig.Products` и `ShowConfig.Passes`.
3. Собрать на карте `Workspace/StageAnchors` с частями `PerformerSpot`, `AudienceSpot`, `VipSpot`, `FrontRowSpot`.
4. Расставить теги: `StageLight`, `StageFog`, `StagePyro`, `StageScreen`, `CrowdZone`, `VipGate`, `FrontRowGate`.
5. Включить в настройках места Studio доступ к DataStore (API Services) и выставить `MaxPlayers`.
6. Добавить свой `userId` в `ShowConfig.Admins`, чтобы снимать перформеров со сцены и запускать шоу вручную.

Подробности в [docs/02-architecture.md](docs/02-architecture.md) и [docs/09-roadmap.md](docs/09-roadmap.md).

### Форматирование

```bash
stylua src/
```

Настройки в `.stylua.toml`.
