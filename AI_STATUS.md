# Feudal Wars — AI Handoff Document

> Единый источник правды для любой другой ИИ. Переписан 2026-11-24 по факту (git + код + boot-тест).
> Формат: `[x]` проверено/сделано, `[ ]` не сделано или не проверено в игре.

---

## 1. Что это

- KCD:MP (Kingdom Come: Deliverance Multiplayer) RP-сервер «Feudal Wars» в Pterodactyl.
- Репо: `https://github.com/lol1luv/kcd-mp-feudalwars`, ветка `main`.
- Гейм-мод — **папка**: вход `gamemodes/feudalwars.lua` + 9 модулей в `gamemodes/feudalwars/` (см. §6).
- UI — `gamemodes/feudalwars/ui/` (9 фреймов, см. §7).
- SDK — единственный источник API: `sdk/KcdMp.d.lua` (~13000 строк). Доки: `https://docs.kcd-mp.com/`.
- Язык мода: Lua 5.4 (NLua), скрипты trusted, доступен luanet к .NET.

---

## 2. Инфраструктура

- Хост `cicada`, VM `201` = `pterodactyl-wings` (QEMU guest agent иногда падает).
- Панель: `https://panel.pingline.xyz`. Сервер UUID `16e44d50-dc1d-4c2d-aba6-29b9e63c74d4`.
- MariaDB: `192.168.0.201:3306` (слушает `0.0.0.0`). Имя хоста `KCd` не резолвится — использовать IP.
- Панельная БД: `s46_KCD` / `u46_yKIA2nRFP9` / `^hTZQ9UY=mi3VkX0TA^=W9DC`.
- Образ: `ghcr.io/parkervcp/yolks:dotnet_8` (внутри .NET 8). Серверу нужен **.NET 10** → ставится в `/home/container/dotnet` через `dotnet-install.sh --channel 10.0`.
- STARTUP: `bash start.sh`. `start.sh` выставляет `DOTNET_ROOT=$PWD/dotnet`.
- Билд `KcdMp-server-0.51.1/` (linux+windows) в корне, `net10.0`, в `.gitignore` (в репо лежат только бинарники linux в корне: `KcdMp.Server`, `*.dll`, `*.so`).

---

## 3. Деплой: что когда делать

- **Restart** — если менялся только `gamemodes/feudalwars.lua`, модули или UI. `start.sh` сам подтянет `main` при старте.
- **Reimport egg + Restart** — если менялся `pterodactyl-egg-kcdmp-feudalwars.json` (переменные, `config.files`, install-скрипт). Reimport в Admin → Nests, затем проверить Startup-переменные сервера.
- **Reinstall** — только если сломан рантайм/dotnet, бинарники или install-скрипт. Для смены карты/команд НЕ нужен.
- **Смена карты** `klaster/trosecko/kutnohorsko`: Startup-переменная `LEVEL` → Restart. Из Lua карту сменить нельзя. Дефолт в egg — `kutnohorsko`.
- **Важно про `start.sh`**: он обновляет сам себя, но новая версия применяется **со следующего рестарта**. Поэтому после смены `start.sh` нужны **два рестарта** (первый скачает и заменит скрипт, второй запустит новый).

---

## 4. Как работает `pterodactyl-start.sh` (версия `2026-11-24.2`)

- **Без GitHub API** (он рейт-лимитит общий IP и молча пропускает обновления). Скачивает tarball с `codeload.github.com/.../tar.gz/refs/heads/main`.
- **Манифест всей папки** `gamemodes/feudalwars/`: sha256 от (путь+содержимое каждого файла). Ловит изменение в любом модуле/UI, не только во входном файле.
- Сравнивает: входной `feudalwars.lua` (sha256) и папку мода (манифест). Пишет в лог, что current / updated, число файлов, список модулей, число UI-файлов.
- Retry загрузки 3 раза, потом стартует локальную сборку как есть.
- `AUTO_UPDATE=0` отключает синхронизацию.
- Логи с префиксом `[fw]`. Пример:
  ```
  [fw] Feudal Wars starter 2026-11-24.2
  [fw] entry: gamemodes/feudalwars.lua is current (2de76793a51c)
  [fw] mode: gamemodes/feudalwars/ is current (29 files, a4aeeebb0c3a)
  [fw] mode: modules: build.lua core.lua economy.lua factions.lua justice.lua npc.lua social.lua ui.lua world.lua
  [fw] mode: ui: 20 files
  ```
- Install-скрипт egg пишет логи с префиксом `[fw-install]`, шаги `step 1/5 … 5/5`.

---

## 5. Ключевые технические факты (проверены)

- **`require` работает** и резолвится относительно папки скрипта. Вход `gamemodes/feudalwars.lua` → `require("feudalwars.core")` и т.д. Модули видят глобалы друг друга, могут регистрировать коллбэки. Подтверждено локальным boot-тестом.
- **`dofile`/`loadfile` НЕ годятся** — резолвятся от cwd, не от папки скрипта.
- **Корень старых жалоб**: на сервере НЕТ `data/combat/items.json` → каталог предметов пуст → `DefineItem`/`FindItems`/`GetItemInfo`/`GivePlayerItem("pickaxe")` не работают. Старый мод зависел от `fw_*` предметов и мешей → «кирки не появляются», «работу нельзя проверить». В логе: `items=false`.
- **Нет данных уровня**: `data/` пуста (только `README.md`). `GetTerrainHeight`/`GetGroundZ`/`GetNavmeshHeight`/`RayCast` → nil. `HasNavmesh()=false`, `HasCollision()=false`. Высота известна только у спавна.
- **Высота объектов**: `CreateMapObject`/`CreateProp`/`CreateActor`/`CreateAnimal`/`CreateHerb` принимают `z < 0` = «на землю» (клиент резолвит). `FW.ground()` пробует collision→navmesh→heightmap→hint.
- **Работа = удар по реальному объекту уровня**: `OnPlayerHitScenery(pid, hit)` даёт `hit.x/y/z` (высота от клиента всегда верная), `hit.surface`, `hit.mesh`, `hit.kind`. Промысел определяется по ним (rock→quarry, tree→woods, crop→fields). Работает в ЛЮБОМ месте карты.
- **UI-события фреймов** приходят в `OnClientEvent` (через `KcdMp.emitServer`), НЕ в `OnPlayerWebSurfaceEvent`. Фокус фрейма = `focus="open"`. Закрытие = `DestroyPlayerWebFrame` + снять фокус + `SetPlayerCursor(pid,false)`.
- **Бинды**: F2 = меню (`fw.menu`), H = где работа (`fw.work`). F1 занят фоторежимом, E конфликтует с игрой.
- **Кириллица**: НЕ править через PowerShell `Set-Content` (ломает кодировку + BOM). Только Node-скрипты, писать `UTF8Encoding $false`.
- **egg JSON**: панель декодирует строгим `json_decode(JSON_THROW_ON_ERROR)`, BOM = ошибка. Качать только Raw-ссылкой, не пересохранять. Правки — через Node (`JSON.stringify`), не PowerShell.

---

## 6. Структура мода (v4, модульная)

| Файл | Строк | Содержание |
|---|---|---|
| `gamemodes/feudalwars.lua` | 186 | вход: `require` модулей + `OnGameModeInit` + 15 коллбэков |
| `gamemodes/feudalwars/core.lua` | 570 | пространство `FW`, конфиг, локализация, БД, деньги, фреймы, пробы мира |
| `gamemodes/feudalwars/world.lua` | 372 | промыслы (зоны), люди королевства, высота, перемещение |
| `gamemodes/feudalwars/economy.lua` | 273 | труд за удар, травы, охота, станции игры, рынок |
| `gamemodes/feudalwars/factions.lua` | 241 | дома, войны, казна, слава, содержание |
| `gamemodes/feudalwars/social.lua` | 129 | аккаунты, страница персонажа, `/pay`, жизненный цикл |
| `gamemodes/feudalwars/build.lua` | 188 | зодчий, чертежи |
| `gamemodes/feudalwars/npc.lua` | 164 | конструктор NPC + диалоги |
| `gamemodes/feudalwars/justice.lua` | 38 | консоль короны, редактор |
| `gamemodes/feudalwars/ui.lua` | 607 | меню, диспетчер страниц, все команды |

- **Коллбэки** (15): `OnGameModeInit`, `OnPlayerConnect`, `OnPlayerDisconnect`, `OnPlayerRequestSpawn`, `OnPlayerSpawn`, `OnPlayerDeath`, `OnPlayerCraft`, `OnPlayerHitScenery`, `OnClientEvent`, `OnPlayerPickHerb`, `OnActorDeath`, `OnPlayerInteractActor`, `OnDialogueResponse`, `OnPlayerWebSurfaceEvent`, `OnPlayerKeyBinding`.
- **Нативные механики**: травы (`OnPlayerPickHerb`), охота (`CreateAnimal`+`SetActorButcher`+`OnActorDeath`), станции игры (`SetCraftCheck`+`OnPlayerCraft` — алхимия/наковальня/точило), магазины (`CreateShop`+`SetShopItem`+`SetActorShop`+`OpenShop`), диалоги (`ShowPlayerDialogue`+`OnDialogueResponse`), карманничество (`SetPickpocketing`).
- **Промыслы по умолчанию**: кольцо из 5 зон вокруг спавна (quarry/woods/fields/hunt/workshop). Админ переносит командой `/zone here <trade> [label]`. Зона = `CreateArea` (цилиндр) + `CreateMapIcon` + NPC-бригадир.
- **БД** (8 таблиц): `fw_players`, `fw_houses`, `fw_members`, `fw_sites`, `fw_people`, `fw_blueprints`, `fw_lots`, `fw_skills`. Без БД всё работает в памяти (чистая деградация).
- **Нет** папок `client/` и `sounds/` — мод их не использует.

---

## 7. UI (9 фреймов)

`gamemodes/feudalwars/ui/ui.toml` объявляет фреймы: `me`, `hall`, `admin`, `notice`, `menu`, `auction`, `build`, `npc`, `craft`.

- **События, которые мод ШЛЁТ** (`FW.push`): `me`, `hall`, `admin`, `menu`, `auction`, `build`, `npc`, `notice`.
- **События, которые мод ОБРАБАТЫВАЕТ** (`FW.web_event`): `menu.close|cursor|lang|run`, `me.close`, `house.close|donate|prestige|declare|peace`, `auction.close|sell|buy|cancel`, `market.refresh`, `build.close|new|save|stamp|cancel`, `npc.close|action|remove|stock|place`, `admin.close|kick|ban|heal|money|tp|tphere`.
- **Секции меню** (по `menu.js`): `main`, `world`, `work`, `house`, `trade`, `build`, `settings`. Мод раскладывает карточки по этим секциям.
- **Известные расхождения (не баги, но долг)**:
  - `ui.toml`-комментарии устарели: описывают старые события (`me.show`, `house.show`, `admin.show`, `menu.show {commands}`), которых код уже не шлёт.
  - Фрейм `craft` объявлен и `craft.js` существует, но мод его **не открывает** и не шлёт `craft.*` — крафт идёт через нативные станции игры, а не через этот фрейм. Либо задействовать, либо удалить.

---

## 8. Команды (28 зарегистрированных)

- **Игрок**: `/menu` `/help` `/me` `/money` `/pay` `/job` `/goto` `/market` `/auction` `/trade` `/house` `/hall` `/prestige` `/war` `/lang` `/commands`.
- **Админ** (`admin=true`): `/admin` `/editor` `/build` `/arch` `/npc` `/zone` `/reload-zones` `/kick` `/ban` `/give` `/tp` `/tphere`.
- `/commands` и `/commands admin` — списки команд (RU/EN).

---

## 9. Проверено / не проверено

- [x] Boot-тест на .NET 10 (`KcdMp.Server.exe --gamemode gamemodes/feudalwars.lua`): 15 коллбэков, 0 ошибок, чистая деградация без БД и данных уровня.
- [x] `require` модулей, манифест-синхронизация `start.sh` (проверено end-to-end в тестовой папке).
- [x] Кросс-чек всех вызовов мода против `sdk/KcdMp.d.lua` — имена API существуют.
- [ ] **В игре не проверено**: зоны промыслов (иконки/бригадиры), F2-меню, удары по объектам и оплата, травы, охота, станции, магазины, диалоги, `/zone`, `/goto`, `/editor`.
- [ ] Меши в `FW.CATALOG` (build.lua) — пути предположительные, проверить через `FindMeshes` в игре.
- [ ] `hall.js` кнопки promote/demote/kick — в текущем `hall.js` их нет (только donate/prestige/declare/peace); проверить, нужны ли.

---

## 10. Известные ограничения API (не пытаться обойти)

- Нет смены карты из Lua — только `[server] level` / env `LEVEL` + рестарт.
- Нет «призрака» для превью — превью = настоящий объект `persist=false` с автоудалением.
- Рисование на карте из Lua: только `CreateMapIcon` (тип/icon/name) и `CreateArea` (зоны). Компасных маркеров (`CreateMarker`) мод не использует.
- `/editor` — встроенный редактор движка (`SetPlayerEditor(pid,"admin")`), требует веб-слой в игре (server interfaces в лаунчере). Свой писать не надо.
- Иконки карты: `type` — имя типа из `GetMapIconTypes()`; если типа нет на уровне — fallback на `icon`-номер.
- Без `data/combat/items.json` каталог предметов пуст: `DefineItem`/`FindItems`/`GetItemInfo`/`GivePlayerItem` по имени не работают. Мод это учитывает (`FW.ready()`).

---

## 11. Ключевые файлы

- `gamemodes/feudalwars.lua` + `gamemodes/feudalwars/*.lua` — мод (см. §6).
- `gamemodes/feudalwars/ui/` — фреймы + `feudalwars.css` (пергамент/сургуч) + `ui.toml`.
- `pterodactyl-start.sh` — синхронизация (codeload + манифест), LEVEL enforce, `[world] map` enforce, запуск.
- `pterodactyl-egg-kcdmp-feudalwars.json` — egg (STARTUP, variables, config.files, install).
- `server.toml.example` — контракт `[gamemode.database]`, `[server] level`, `[world] map` и др.
- `data/README.md` — инструкция по экспорту данных уровня.
- `sdk/KcdMp.d.lua` — API (~13000 строк).
- `README.md` — **устарел** (описывает старые `/farm`, `/craft`, `panel.json`). Требует переписи.

---

## 12. Лог изменений (новые сверху)

- `e569d2c` (2026-11-24): `start.sh` + egg: честные логи деплоя и проверка всей папки мода. Манифест `gamemodes/feudalwars/` (путь+содержимое каждого файла) вместо сравнения только входного файла; retry загрузки; баннер с версией; install-скрипт egg с шагами `step 1/5…5/5`. Правки egg — через Node (без BOM).
- `2624c48` (2026-11-24): **v4 — полный рефакторинг на модули + перепись на нативных механиках.** Монолит 2473 строки → вход + 9 модулей через `require`. Работа переведена на удары по реальным объектам уровня. Найдена и обойдена корневая проблема: пустой каталог предметов (нет `data/combat/items.json`). Добавлены травы, охота, станции игры, магазины, диалоги, карманничество, зоны промыслов, `/zone`, `/goto`, `/commands`.
- `a132fce` (2026-11-24): NPC неуязвимы + страница на каждого NPC, редизайн UI (пергамент/сургуч, CSS-текстуры).
- `5d36a07` (2026-11-24): `start.sh` включает `[world] map` в server.toml, если его нет (без реинсталла).
- `59ea32d` (2026-11-24): `[world] map` в egg (CreateMapObject отказывал), реальные меши игры, `OnPlayerInteractActor` для NPC, список `/commands`.
- `5b381b9` (2026-11-24): синхронизация без GitHub API (codeload + sha256), egg: одна загрузка, server.toml сохраняется при реинсталле.
- `7217131` (2026-11-24): чистка только плановых узлов работ (чертёжные валуны остаются), компасных маркеров нет.
- `3c48e02` (2026-11-24): узлы как map-объекты на земле (z<0 авто-снап), чистка устаревших строк site/node, фикс битой кириллицы, убраны E-подсказки.
- `791fea6` (2026-11-24): конструктор NPC: таблица `fw_npcs`, `/npc add|list|remove`, торговцы со stock+ценами, админ-фрейм, персист.
- `5b7c57d` (2026-11-24): убран бинд E (блокировал подбор), нет компасных кругов, ground snap через navmesh, реальные меши через `FindMeshes`, RU-чат для работ.
- `e207052` (2026-11-24): `MENU_TEXT` форвард-декларирован (был nil → меню мертво), восстановлены кириллические тексты меню.
- `cc8d384` (2026-11-24): ядро разрушаемых узлов, работы по Kuttenberg, зодчий (NPC + `/arch`), двухпанельное меню, редизайн CSS.
- `2aeedc7` (2026-11-24): ресурсы (DefineItem fw_*), аукцион с UI, стройка только админам, действия меню через UI.
- `8dc95d0` (2026-11-24): immersive работ (удар по жиле, проверка инструмента, эффекты/звук, `/job kit`).
- `9b913e1` (2026-11-24): реальные типы иконок, пропсы на точках, `/jobsite`, все фреймы RU/EN.
- `5cafb37` (2026-11-24): полная сверка UI (`rm -rf` + точная копия из гита при каждом обновлении).
- `f7017b3` (2026-11-24): БАГ вложенности `cp -rf feudalwars` → `feudalwars/feudalwars/`; исправлено на `feudalwars/.`.
- `5102786` (2026-11-24): БАГ `web_event` была `local` после `OnClientEvent` → кнопки меню мертвы.
- `a8a0c4e` (2026-11-24): egg install: `cp start.sh` перенесён ДО `rm -rf tmp/main`.
- `e1db2fd` (2026-11-24): egg JSON: убран BOM (панельный `json_decode` его не принимает).
- `e35c2bd` (2026-11-24): install-скрипт: дефолт `level` klaster→kutnohorsko.
- `e5dc913` (2026-11-24): LEVEL enforce перенесён ДО update-check.
- `b94c63c` (2026-11-24): `focus=open` у всех фреймов, авто-курсор, закрытие через `DestroyPlayerWebFrame`.
- `8a4bddc` (2026-11-24): `start.sh` принудительно прописывает `level` в server.toml.
- `a6a2de5` (2026-11-24): главное меню на F2 (F1 занят фоторежимом).
- `e223763` (2026-11-24): UI-события через `OnClientEvent` (emitServer), бинды, action hints, меню-фрейм.
- `1837202` (2026-11-24): видимые точки работ, `/help`, `/goto`, `/build` preview, `/editor`, дефолт kutnohorsko.
- `1a95abb` (2026-11-24): модуль работ v1 (mine/farm/forest, stock, skills, `/job`, db).
- `bb0f70d` и ранее: бинарники 0.51.1, фикс `ShowPlayerWebFrame`, автообновление `start.sh`.
