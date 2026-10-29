# NPC WAR (бывш. PHYSICS BOX) — заметки для следующих сессий

Отвечать пользователю **по-русски**. После каждого изменения: собрать, закоммитить,
запушить в ветку `ccr-5eac52f9-uj40jt`, дождаться CI и дать прямую ссылку:
https://github.com/pidor95/smoothaim/releases/download/latest/PhysicsBox.apk

Пользователь хочет, чтобы модели, анимации, гибы, иконки и звуки делались
**«через блендер»** — скрипты в `physicsbox/tools/blender/`.

## Стек
- Godot 4.5.1 (`/opt/godot/Godot_v4.5.1-stable_linux.x86_64`), Mobile renderer, Jolt.
- Blender 4.2.3 headless (`/opt/blender/blender-4.2.3-linux-x64/blender -b -P script.py`).
- Android: arm64, `physicsbox/android/debug.keystore` (androiddebugkey / android),
  экспорт `build/PhysicsBox.apk`. CI: `.github/workflows/physicsbox-android.yml`
  (пуш в `physicsbox/**` → релиз `latest`).
- Тесты: `tools/war_test.gd`, `tools/mechanics_test.gd`, `tools/explosives_test.gd`;
  в `-s` скриптах автолоады только через `root.get_node("Settings")`;
  скриншоты через `xvfb-run ... --rendering-driver vulkan --rendering-method mobile --fixed-fps 60`
  (без `--fixed-fps` время в тестах по кадрам «плывёт» из-за медленного рендера).

## Что уже есть
- **NPC WAR** (новое имя, папка/APK прежние): только война, карт «дом»/«магазин»
  нет (house.gd/shop.gd удалены). Меню: «В БОЙ», настройки, «АВТОРЫ МОДЕЛЕЙ».
- Карта ФРОНТ 300×340 м: `build_trenches.py` (чанки рельефа `Terrain_i_j` с
  шагом 0.5/1/2 м и «юбками», мебель траншей разбита по ячейкам 60 м
  `Planks_i_j`…, пустышки `B_<Proto>_<A|B|N>_k` — где стоят здания, Spawn/Post/Player).
  Здания — прототипы `build_buildings.py` → `buildings.glb` (`P_<Name>`; дети
  `<Mat>__<Name>`, `C__<Name>` коллизия, маркеры `Glass__`/`Door__`/`Post__`;
  Panel5 = пятиэтажка как на видео, HouseBrick, HouseWood, Ruin2, Garages, CarWreck).
  `trench_level.gd` инстансит их (общая trimesh-форма), ставит GlassPane/Door,
  посты по сторонам. Навмеш запечён заранее: `godot --headless -s res://tools/bake_nav.gd`
  → `assets/maps/trenches_nav.res` (cell 0.2/0.1, agent_radius 0.2 — иначе
  лестницы и двери закрываются). После правки карты — перезапечь!
- Война вокруг игрока: `game.gd` `TEAM_ALIVE`=9, `TICKETS`=120, `ACTION_RADIUS`
  — спавны/посты ближе к игроку; подкрепления всегда (нет авто/ИИ/замедления/+враг).
- Солдат: `npc.gd` — `_faint` (без сознания `unconscious`, `_out_cold`, добить),
  `_death_throes` (судороги после смерти), `_shove`/сильнее пружины и BALANCE_COST
  (физика попаданий), шея: `_wild_left` (стреляет вслепую только 5 с и с шансом 50 %),
  после подъёма снова берёт АК. Остальное (стаггеры, шея, гор, приказы,
  самоубийство, раненые на земле) — как раньше.
- Игрок: `player.gd` — `hits` (5-я пуля = смерть), `blood`/`bleed_rate`, `bpm`,
  `consciousness`, `ear_ring` (звон `tinnitus.wav` + LowPass на Master), `heartbeat.wav`,
  `death_t` (HUD: чёрный экран и белая точка), камера на груди качается.
  Explosion: `take_damage(..., "blast")`.
- HUD: панель слева внизу (состояние, пульс+ЭКГ, кровь, сознание), хотбар
  (АК, M500, РГД-5, FPV; иконки из `build_icons.py`), стрелки FPV (`drone_arrows`,
  клавиши-стрелки `fpv_*`), хитмаркера нет.
- Бодикам: `bodycam.gd` + `assets/shaders/bodycam.gdshader` (CanvasLayer 0 под HUD),
  настройка `Settings.bodycam`, +14° FOV.
- Оружие игрока: АК-74М (`ak74_fp.glb`, авто, `trigger_held`) и M500; пистолета нет
  (у NPC пистолет для самоубийства остался). Граната — анимация `grenade_fp.glb`
  "throw", отпуск на `THROW_RELEASE` → `player.release_grenade()`.
- Sketchfab (CC-BY, авторы в README и меню): АК-74М, РГД-5, FPV-дрон. Токен —
  у пользователя (в репо не класть): `SKETCHFAB_TOKEN=... python3 tools/fetch_sketchfab.py`
  → `tools/model_sources/` (gitignore) → `build_sketchfab_kit.py` (АК FP, бросок,
  `npc_rifle.glb` — `RIFLE_MUZZLE` печатает скрипт, `grenade.glb`, `fpv_drone.glb` с Prop0..3).
- Тесты: `tools/war_test.gd`, `tools/mechanics_test.gd` (обморок, судороги,
  шея 5 с, авто-огонь, граната, стрелки FPV, смерть игрока), `tools/explosives_test.gd`.
  В контейнере Vulkan нет — Godot сам падает на OpenGL (llvmpipe), это медленно.
- Взрывы, гранаты, FPV, кровь, гор, двери, стёкла, звуки — см. README.
