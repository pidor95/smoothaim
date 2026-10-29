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
- Карта ФРОНТ 420×340 м (траншеи ~300 м — «длиннее окопы», X0 = −270): `build_trenches.py` (чанки рельефа `Terrain_i_j` с
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
  (АК, СВД, РГД-5, FPV; иконки из `build_icons.py`), стрелки FPV (`drone_arrows`,
  клавиши-стрелки `fpv_*`), хитмаркера нет.
- Бодикам: `bodycam.gd` + `assets/shaders/bodycam.gdshader` (CanvasLayer 0 под HUD),
  настройка `Settings.bodycam`, +14° FOV.
- Оружие игрока: АК-74М с «Коброй» (`ak74_fp.glb`, авто, `trigger_held`, sight = красная точка;
  высота «Кобры» — `dot_at` в build_sketchfab_kit.py, опущена по просьбе; стекло прозрачное, точка
  в центре окна `KOBRA_DOT`; ads_dist 0.4, бедро ниже — пользователь дважды жаловался «прицел высоко»,
  dot_at.z = 1.4 — корпус утоплен в крышку). От бедра вместо перекрестия — маленькая белая точка (просьба).
  СВД+ПСО-1 (`svd_fp.glb`); у DEFS ключ `scope` ("pso") → `Weapon.scoped()`, HUD `_draw_scope`;
  дробовика, пистолета и Мосинки нет (убраны по просьбе; у NPC пистолет для самоубийства остался).
- Бег/присед: `player.sprint`/`sprint_stick` (джойстик за кольцом вверх)/Shift, `stamina`,
  `block_sprint` при выстреле, `Weapon._sprint_t` поза; `set_crouch` (капсула 1.15, глаза 1.0,
  проверка потолка), NPC целятся в `eye_height() - 0.3`.
- NPC: бронеплиты (`plate` в take_hit: центр груди, импульс < `HEAVY_ROUND`), `collapse`
  — шанс упасть от попадания в корпус/бедро, `_down_time`; снайперы `weapon == "svd"`
  (`npc_svd.glb`, `SVD_MUZZLE`, `game.SNIPER_CHANCE`, посты выше 3 м).
- Дрон игрока (`fpv_drone.gd` `_pilot_flight`): висит сам, ▲ вперёд по камере, ▼ назад,
  ◀ ▶ поворот, `drone_climb` (ВЫШЕ/НИЖЕ, E/Q).
- Бодикам-движение: `player._bodycam_motion` (отставание при поворотах, удары шагов,
  раскачка, дыхание от пульса, `_jolt`/`cam_kick` на выстрел/попадание/приземление),
  `scope_shift` для оптики. Граната — анимация `grenade_fp.glb`
  "throw", отпуск на `THROW_RELEASE` → `player.release_grenade()`.
- Sketchfab (CC-BY, авторы в README и меню): АК-74М, РГД-5, FPV-дрон, СВД, «Кобра», Mavic 2 Pro,
  Ф-1, ПБС-1. Токен — у пользователя (в репо не класть):
  `SKETCHFAB_TOKEN=... python3 tools/fetch_sketchfab.py [имена]`
  → `tools/model_sources/` (gitignore) → `build_sketchfab_kit.py` (АК FP, бросок,
  `npc_rifle.glb` — `RIFLE_MUZZLE` печатает скрипт, `grenade.glb`, `fpv_drone.glb` с Prop0..3).
- Меню оружия (`game._build_weapon_menu`): вкладки ОРУЖИЕ (взять / убрать из снаряжения / убрать из рук),
  СНАРЯЖЕНИЕ (гранаты, FPV, дрон-сброс), МОДИФИКАЦИИ (глушитель ПБС-1), БЕССМЕРТИЕ.
  `Settings.loadout` / `Settings.suppressed` (сохраняются), `Settings.carries(id)`;
  `Weapon.holstered`/`holster()`/`toggle(i)`/`apply_mods()`; хотбар (`Hud._slots()`) — только взятое.
- Глушитель: `suppressor.glb` (ПБС-1, Sketchfab 3dYaroslav) на BoneAttachment3D кости `muzzle`, размер — DEFS
  "suppressor"; без вспышки/света, звук `rifle_sup`/`sniper_sup` (`build_suppressed_sounds.py`),
  `alert × SUPPRESSED_ALERT`.
- Дрон-сброс (пользователь прислал фото: Mavic 3 с белым печатным сбросом и двумя Ф-1 по бокам —
  не самолёт-UAV и не FPV!): `bomb_drone.gd` (`BombDrone extends FpvDrone`, висит, сам взлетает на 22 м,
  камера-подвес вниз, `trigger_pressed` = сброс, `exit_pressed` = домой → `player.bomber_back`),
  модель `build_drone_kit.py` (Mavic 2 Pro MattMaksymowicz + Ф-1 notcplkerry), падающая Ф-1 —
  `Grenade.throw(..., f1.glb, impact=true)`. Только у игрока, клавиша X.
- Тесты: `tools/war_test.gd`, `tools/kit_test.gd` (кобура, снаряжение, глушитель, дрон-сброс, меню),
  `tools/mechanics_test.gd` (обморок, судороги,
  шея 5 с, авто-огонь, граната, стрелки FPV, смерть игрока), `tools/explosives_test.gd`.
  В контейнере Vulkan нет — Godot сам падает на OpenGL (llvmpipe), это медленно.
- Вылет при входе в бой (жалоба): текстуры оружия были 2048 без VRAM-сжатия (~250 МБ видеопамяти)
  и загрузка 10+ с одним кадром (ANR на Android). Сейчас: в `.import` 3D-текстур `compress/mode=2`
  (+ `size_limit=1024` у оружия) — новые текстуры тоже так ставить! Меню грузит тяжёлое в потоках
  (`main_menu.PRELOAD` → `Settings.preloaded`), `TrenchLevel` строится кусками (`_breathe`, сигнал
  `built`, `is_built`, экран «ЗАГРУЗКА ФРОНТА»), `game._ready` ждёт его; тесты ждут `game.hud`.
- Взрывы, гранаты, FPV, кровь, гор, двери, стёкла, звуки — см. README.
