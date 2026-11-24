# Feudal Wars — AI Handoff Document
> Этот файл — единый источник правды для любой другой ИИ. Дополнять при каждом изменении. Формат: `[x]` выполнено, `[ ]` не выполнено.

## 1. Цель проекта
- KCD:MP Feudal Wars сервер в Pterodactyl: egg + .NET 10 + MySQL + автообновление с GitHub.
- Репо: `https://github.com/lol1luv/kcd-mp-feudalwars`, ветка `main`.
- Гейм-мод: `gamemodes/feudalwars.lua` + UI `gamemodes/feudalwars/ui/` (фреймы `me/hall/admin/notice`).
- SDK — единственный источник API: `sdk/KcdMp.d.lua`. Доки: `https://docs.kcd-mp.com/`.

## 2. Инфраструктура (не менять без спроса)
- Хост `cicada`, VM `201` = `pterodactyl-wings` (QEMU guest agent иногда падает).
- Панель: `https://panel.pingline.xyz`, сервер `https://panel.pingline.xyz/server/9cb7b632/databases`.
- Старый сервер UUID `9cb7b632-fbd9-4fff-97ab-4f062f489e1`, новый `16e44d50-dc1d-4c2d-a6b6-29b9e63c74d4`.
- Образ: `ghcr.io/parkervcp/yolks:dotnet_8` (внутри .NET 8), серверу нужен `.NET 10.0.0` → ставится в `/home/container/dotnet` через `dotnet-install.sh --channel 10.0`.
- STARTUP итог: `bash start.sh`; `start.sh` выставляет `DOTNET_ROOT=$PWD/dotnet`.
- Database Host `test` = `192.168.0.201:3306`. MariaDB на `201` слушает `0.0.0.0:3306`. `KCd` не резолвится → использовать IP.
- Ручная БД `KCD` / юзер `Akne` / пароль `MAratigosha2211`; панельная БД `s46_KCD` / юзер `u46_yKIA2nRFP9` / пароль `^hTZQ9UY=mi3VkX0TA^=W9DC`.
- Пароль панели менялся на `FwPanelDb91xQ` в `.env` на `200` и в MariaDB.
- Билд `KcdMp-server-0.51.1` (linux+windows) в корне; `net10.0`; папка `KcdMp-server-0.51.1/` в `.gitignore`.
- `pterodactyl-start.sh` = `start.sh` в контейнере: чекает `api.github.com/repos/.../commits/main`, сравнивает с `.fw_version`, обновляет бинарники/гейммод/UI. `AUTO_UPDATE=0` отключает.

## 3. Что когда делать (реинсталл / реимпорт / рестарт)
- [x] Запомнить правило:
  - **Restart** — достаточно, если поменялся только `gamemodes/feudalwars.lua` или UI. `start.sh` сам подтянет `main` при старте.
  - **Reimport egg + Restart** — если поменялся `pterodactyl-egg-kcdmp-feudalwars.json` (переменные, `config.files`, install-скрипт). Reimport в Admin → Nests, затем проверить Startup-переменные сервера.
  - **Reinstall** — только если сломан рантайм/dotnet, бинарники, или install-скрипт поменялся кардинально и надо переустановить файлы с нуля. Для смены карты/команд НЕ нужен.
- [x] Смена карты `klaster/trosecko/kutnohorsko`: поменять Startup-переменную `LEVEL` в панели → Restart. Дефолт в egg сейчас `kutnohorsko`.
- Текущий вопрос юзера (2026-11-24): «надо ли реинстал?» → **Нет. Нужны Reimport egg (т.к. дефолт LEVEL поменялся) + смена LEVEL=kutnohorsko в Startup + Restart.**

## 4. Выполнено
- [x] Починен entrypoint + `DOTNET_ROOT` inline, затем переход на `bash start.sh`.
- [x] Egg-переменные `DB_DRIVER/HOST/PORT/USERNAME/PASSWORD/DATABASE`; генерация `[gamemode.database]`; Wings-маппинг.
- [x] `mkdir -p /mnt/server/data` (фикс `data/server.db`).
- [x] Созданы БД `KCD`+`Akne` и панельная `s46_KCD`; сервер стартовал `listening on udp/25566`, `mysql at 192.168.0.201:3306/KCD`.
- [x] Обновлены бинарники до `0.51.1`; install-скрипт на `refs/heads/main` с always-refresh.
- [x] Исправлен `feudalwars.lua`: `SendPlayerWebFrame` → `ShowPlayerWebFrame` (4 места).
- [x] `pterodactyl-start.sh`: автообновление с GitHub.
- [x] Модуль работ v1 (`1a95abb`): шахта/ферма/лесопилка у спавна, stock, навыки, `/job mine|farm|forest|done|skills`, таблицы `job_sites`/`job_skills`.
- [x] Видимость работ (`1837202`): compass marker (`CreateMarker`+`ShowMarkerForAll`), иконка карты (`CreateMapIcon`), NPC-бригадир (`CreateActor`+`SetActorPrompt`), точка взаимодействия (`CreateInteraction`), `/goto mine|farm|forest|spawn`.
- [x] Чистка команд: удалены `/farm`, `/craft` (дубли `/job`). Добавлен `/help` с меню всех команд.
- [x] Редактор: `/build list|place|cancel` (каталог tent/stall/palisade/tower, превью 60 сек через `CreateMapObject persist=false` + `DeleteMapObject`), `/editor` (админы, `SetPlayerEditor(pid,"admin")`), `OnPlayerUseMapObject`+`OnPlayerInteract` → старт смены.
- [x] Дефолт карты в egg: `klaster` → `kutnohorsko`.
- [x] Кросс-чек всех вызовов мода против `sdk/KcdMp.d.lua` — чисто (кроме SQL-ключей KEY/VALUES/VARCHAR).

## 5. Не выполнено / следующие шаги
- [x] Карта сменилась на Куттенберг (подтверждено юзером 2026-11-24). Reimport + LEVEL=kutnohorsko + Restart сработали.
- [ ] Проверить в игре: маркеры работ на компасе, иконки на карте (M), F2 меню, E работа / F сбор, `/goto mine`, `/job mine` → `/job done`, `/build list` → `/build place tent`, `/editor` (админ).
- [ ] ВАЖНО: карта меняется только через Startup `LEVEL=kutnohorsko` + Restart. Из Lua сменить карту нельзя.
- [ ] Если маркеров/иконок нет — смотреть лог: `feudalwars: map folder=...`, `marker refused`, `no map icon type`, `map icon refused`. Возможные причины: нет карты на сервере (readOnly), нет типа иконки на уровне (fallback на pin), игрок смотрит не туда.
- [ ] `/editor` требует веб-слой в игре (server interfaces в опциях лаунчера). Без него — сообщение в чат. Это требование движка, не баг мода.
- [ ] Следующий модуль по промту: лавки игроков (`CreateShop` + найм NPC-продавца). Ждёт команды «делай лавки».
- [ ] Починить `hall.js`: кнопки promote/demote/kick шлют пустые payload (`prompt ? undefined : undefined`) — надо слать имя игрока.
- [ ] Добавить `/build` в `HELP_MENU`? Уже есть. Проверить `/help` в игре после рестарта.
- [ ] Меши в `BUILD_CATALOG` — пути предположительные (`tent_a.cgf`, `table_market.cgf`, `palisade_wall.cgf`, `watch_tower.cgf`), проверить через `FindMeshes` в игре или заменить на реальные из `meshes list`.

## 6. Известные ограничения API (не пытаться обойти)
- Нет «призрака» для превью — превью = настоящий объект `persist=false` с автоудалением.
- Нет смены карты из Lua — только `server.toml [server] level` / env `LEVEL` + рестарт.
- Нет рисования на карте из Lua кроме `CreateMapIcon` (тип/icon/name) и `CreateMarker` (компас).
- `/editor` — встроенный редактор движка, свой писать не надо.
- Иконки карты: `type` — имя типа из `GetMapIconTypes()`; если типа нет на уровне — fallback `icon=0`.

## 7. Ключевые файлы
- `gamemodes/feudalwars.lua` (входной, ~180 строк): только `require` модулей + `OnGameModeInit` + все коллбэки.
- `gamemodes/feudalwars/core.lua`: пространство `FW`, конфиг, локализация, БД, деньги, фреймы, пробы мира.
- `gamemodes/feudalwars/world.lua`: промыслы (зоны), люди королевства, высота, перемещение.
- `gamemodes/feudalwars/economy.lua`: труд за удар, травы, охота, станции игры, рынок.
- `gamemodes/feudalwars/factions.lua`: дома, войны, казна, слава, содержание.
- `gamemodes/feudalwars/social.lua`: аккаунты, страница персонажа, /pay, жизненный цикл.
- `gamemodes/feudalwars/build.lua`: зодчий, чертежи.
- `gamemodes/feudalwars/npc.lua`: конструктор NPC + диалоги.
- `gamemodes/feudalwars/justice.lua`: консоль короны, редактор.
- `gamemodes/feudalwars/ui.lua`: меню, диспетчер страниц, все команды.
- `gamemodes/feudalwars/ui/ui.toml`: фреймы `me/hall/admin/notice/menu/auction/build/craft/npc`.
- `pterodactyl-egg-kcdmp-feudalwars.json`: egg (STARTUP, variables, config.files, install).
- `pterodactyl-start.sh`: автообновление + запуск.
- `server.toml.example`: контракт `[gamemode.database]`, `[server] level`, `[world] map`.
- `sdk/KcdMp.d.lua`: API (~13000 строк).

## 9. Архитектура v4 (модульный рефакторинг, 2026-11-24)
- **`require` подтверждён практикой** (локальный boot-тест на .NET 10): резолвится относительно папки скрипта. Вход `gamemodes/feudalwars.lua` → `require("feudalwars.core")` и т.д. `dofile`/`loadfile` — от cwd, НЕ годятся. Модули видят глобалы друг друга, могут регистрировать коллбэки.
- **Корень жалоб найден**: на сервере НЕТ `data/combat/items.json` → каталог предметов пуст → `DefineItem`/`FindItems`/`GetItemInfo`/`GivePlayerItem("pickaxe")` не работают. Старый мод зависел от `fw_*` предметов и мешей → «кирки не появляются», «работу нельзя проверить». Проверено пробами: `items=false` в логе.
- **Новая модель работы**: удар по реальному объекту уровня (`OnPlayerHitScenery` даёт `hit.x/y/z` — высота всегда верная, клиент её знает). Промысел определяется по `hit.surface`/`hit.mesh` (rock→quarry, tree→woods, crop→fields). Работает в ЛЮБОМ месте карты, не только у спавна. Оплата за удар, навык растёт, заработок копится и сообщается раз в 12с.
- **Нативные механики вместо костылей**: травы (`OnPlayerPickHerb`), охота (`CreateAnimal`+`SetActorButcher`+`OnActorDeath`), станции игры (`SetCraftCheck`+`OnPlayerCraft` — алхимия/наковальня/точило), магазины (`CreateShop`+`SetShopItem`+`OpenShop`), диалоги (`ShowPlayerDialogue`+`OnDialogueResponse`), карманничество (`SetPickpocketing`).
- **Высота**: `FW.ground()` пробует collision→navmesh→heightmap→hint. Без данных уровня объекты ставятся на z игрока (там, где он стоит — верно). `CreateMapObject`/`CreateProp`/`CreateActor`/`CreateAnimal`/`CreateHerb` принимают z<0 = «на землю» (клиент резолвит).
- **Промыслы по умолчанию**: кольцо из 5 зон вокруг спавна (quarry/woods/fields/hunt/workshop). Админ переносит их в реальные места командой `/zone here <trade> [label]`. Зона = `CreateArea` (цилиндр) + `CreateMapIcon` + NPC-бригадир.
- **Команды**: игрок — `/menu /me /job /goto /market /house /hall /war /prestige /money /pay /lang /commands`; админ — `/admin /editor /build /arch /npc /zone /reload-zones /kick /ban /give /tp /tphere`.
- **Бинды**: F2 = меню, H = где работа. (F1 занят фоторежимом, E конфликтует с игрой.)
- **БД**: `fw_players/fw_houses/fw_members/fw_sites/fw_people/fw_blueprints/fw_lots/fw_skills`. Без БД всё работает в памяти (деградация чистая).
- **Boot-тест**: `KcdMp.Server.exe --gamemode gamemodes/feudalwars.lua` на .NET 10 (runtime в `%TEMP%\kilo\dotnet\runtime`). Лог: `server.log`. 16 коллбэков, 0 ошибок.

## 8. Лог изменений
- `v4` (2026-11-24): ПОЛНЫЙ РЕФАКТОРИНГ НА МОДУЛИ + ПЕРЕПИСЬ НА НАТИВНЫХ МЕХАНИКАХ. Монолит 2473 строки → входной файл + 9 модулей через `require` (подтверждён boot-тестом). Работа переведена на удары по реальным объектам уровня (высота от клиента, работает везде). Найдена и обойдена корневая проблема: пустой каталог предметов (нет `data/combat/items.json`) — мод больше не зависит от `fw_*` предметов. Добавлены: травы, охота, станции игры, магазины, диалоги, карманничество, зоны промыслов с иконками/бригадирами, `/zone`, `/goto`, `/commands`. См. раздел 9.
- `cc8d384` (2026-11-24): ПОЛНАЯ ПЕРЕРАБОТКА. (1) Ядро разрушаемых узлов: единый реестр `nodes`, HP, дроп, респаун 300с, персист в `fw_nodes` (mesh/label/is_map/mapid). (2) Работы разнесены по Kuttenberg: 2 шахты (каменоломня 2870/2960, штрек 3130/800), 2 поля (1520/1990, 3060/770), 2 леса (660/3260, 1740/2810); z из `GetTerrainHeight`. (3) Зодчий: NPC «Master Builder Havel» у спавна + `/arch new|save|stamp|list|cancel`; черновик из реальных map-объектов, камень бьётся и даёт руду, сохранение в `fw_blueprints`, тиражирование куда угодно с рабочими узлами. (4) UI: двухпанельное меню (rail: Обзор/Мир/Работа/Дом/Торг/Стройка/Настройки) + карточки, полный редизайн CSS, новый build-фрейм. (5) Исправлены баги порядка объявлений: `isAdmin`, `close_frame`, `lang_of`, `arch_open`, `bp_load_all`, `db`, `fmt`, `earn`, `save_money`, `job_skill_*` — все форвард-декларированы (иначе nil при вызове).
- `2aeedc7` (2026-11-24): ресурсы уголь/железо/серебро/золото/камень/дерево/зерно (DefineItem fw_*, взвешенный дроп, в сумку), аукцион с UI (лоты в БД, продажа/покупка/снятие без чата), стройка только админам через визуальное меню (без грошей), все кнопки меню делают действие через UI (menu_do), каталог стройки RU/EN.
- `8dc95d0` (2026-11-24): immersive работ: удар по жиле оружием в руках (OnPlayerHitScenery), проверка инструмента (кирка/молот/топор/серп), эффекты+звук при ударе, осколки-пикапы, жила-валун с истощением и респауном, `/job kit` выдача инструмента, НИЧЕГО не блокируется (E только подсказка, F убран, таймеров смен нет).
- `9b913e1` (2026-11-24): продакшн работ: реальные типы иконок (troskyQuarry/miller/camp + icon numbers), пропсы на точках (бочки/ящики/костёр/наковальня), `/jobsite <id|new> <kind>` для привязки к реальным местам, E по site id + диагностика в лог, команды в меню НЕ переводятся (только названия/описания), все фреймы me/hall/admin/menu RU/EN + редизайн, каталог стройки на реальных мешах.
- `5cafb37` (2026-11-24): полная сверка UI: `rm -rf gamemodes/feudalwars` + точная копия из гита при каждом обновлении (сносит вложенность от старого cp-бага и stale-файлы), плюс diff-отчёт disk-vs-git в лог. То же в install-скрипте egg.
- `f7017b3` (2026-11-24): БАГ: `cp -rf feudalwars /mnt/server/gamemodes/` при существующей папке кладёт `feudalwars/feudalwars/` (вложенность) — сервер отдавал старый UI. Исправлено на `feudalwars/.`. Юзер: меню не закрывается, редизайна нет — сервер крутит старый UI.
- `5102786` (2026-11-24): БАГ: `web_event` была `local` после `OnClientEvent` → кнопки меню слали события в nil (закрытие/Run мертвы). Починен порядок. Меню-хаб: русские названия + описания, кнопка Настройки с выбором EN/RU (`/lang`, `menu.lang`), редизайн в стиле KCD (сургучная печать, золото, пергамент).
- 2026-11-24: реинсталл прошёл после Restart (Wings подхватил обновлённый egg). Карта/меню/фокус — проверять в игре: F2 меню, E/F работы, `feudalwars on kutnohorsko` в логе.
- `a8a0c4e` (2026-11-24): egg install: `cp start.sh` перенесён ДО `rm -rf tmp/main` (скрипт копировался из уже удалённой папки → `cannot stat .../pterodactyl-start.sh`). Ошибка вылезла при реинсталле.
- `e1db2fd` (2026-11-24): egg JSON: убран BOM (PowerShell записал файл с BOM, панельный json_decode с JSON_THROW_ON_ERROR его не принимает → Syntax error при реимпорте). Качать egg только кнопкой Download/GitHub Raw без пересохранения.
- `e35c2bd` (2026-11-24): install-скрипт: дефолт `level` klaster→kutnohorsko; start.sh пишет диагностику LEVEL env + level до/после. Юзер: браузер показывает Sedletz Monastery после реимпорта + LEVEL=kutnohorsko + рестарта.
- `e5dc913` (2026-11-24): LEVEL enforce перенесён ДО update-check (иначе новый start.sh применялся только со 2-го рестарта). Юзер видит Sedletz Monastery (klaster) в браузере несмотря на LEVEL=kutnohorsko в Startup.
- `b94c63c` (2026-11-24): focus=open у всех фреймов (клавиатура сразу, без клика), авто-курсор при открытии, закрытие через DestroyPlayerWebFrame + снятие фокуса, кнопка Free the mouse в меню.
- `8a4bddc` (2026-11-24): start.sh принудительно прописывает `level = "$LEVEL"` в server.toml (Wings иногда не переписывает его из Startup-переменной).
- `a6a2de5` (2026-11-24): главное меню на F2 (F1 занят фоторежимом), меню-хаб с кнопками Character/House hall/Crown's console, убраны отдельные бинды F2-F4.
- `e223763` (2026-11-24): UI events via OnClientEvent (emitServer!), key bindings E/F/F1-F4, action hints, menu frame, editor web check, marker diagnostics, Esc closes frames, SetPlayerWebFocus on open.
- `1837202` (2026-11-24): visible job sites, /help, /goto, /build preview, /editor, kutnohorsko default.
- `1a95abb` (2026-11-24): jobs module (mine/farm/forest, stock, skills, /job, db).
- `bb0f70d` и ранее: 0.51.1 бинарники, ShowPlayerWebFrame фикс, start.sh автообновление.
