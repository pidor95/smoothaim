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
- Карта ФРОНТ 840×680 м (увеличена ×2 по просьбе; X0 = −590, Z0 = −340 — эти числа ещё в
  `bake_heights.gd` и `trench_level.gd` HEIGHTS_ORIGIN/NAV_AABB; траншеи −582..42, западнее −270
  доски только у 30 % участков — экономия памяти; деревни в глубоком тылу z ≈ ±200/±290): `build_trenches.py` (чанки рельефа `Terrain_i_j` с
  шагом 0.5/1/2 м и «юбками», мебель траншей разбита по ячейкам 60 м
  `Planks_i_j`…, пустышки `B_<Proto>_<A|B|N>_k` — где стоят здания, Spawn/Post/Player).
  Здания — прототипы `build_buildings.py` → `buildings.glb` (`P_<Name>`; дети
  `<Mat>__<Name>`, `C__<Name>` коллизия, маркеры `Glass__`/`Door__`/`Post__`;
  Panel5 = пятиэтажка как на видео, HouseBrick, HouseWood, Ruin2, Garages, CarWreck).
  `trench_level.gd` инстансит их (общая trimesh-форма), ставит GlassPane/Door,
  посты по сторонам. Навмеш запечён заранее: `godot --headless -s res://tools/bake_nav.gd`
  → `assets/maps/trenches_nav.res` (cell 0.2/0.1, agent_radius 0.2 — иначе
  лестницы и двери закрываются). После правки карты — перезапечь!
  Коллизия земли — НЕ trimesh (съедала ~130 МБ, телефоны вылетали/зависали): `tools/bake_heights.gd`
  → `assets/maps/trenches_height.res` (Image RF, шаг 0.5 м, высоты ×2), `trench_level._build_ground`
  режет на квадратные HeightMapShape3D 65×65 (Jolt делает height field только из квадратных) со
  scale 0.5. После правки карты: build_trenches.py → bake_heights.gd → bake_nav.gd.
- Вылеты/зависания на Samsung (жалоба): кроме памяти был баг — попадание в таз искало несуществующий
  клип `knee_fall_s`, солдат ломался и каждый кадр сыпал ошибки. Лог пишется в файл
  (`debug/file_logging`), `game._report` раз в 30 с пишет память; в меню НАСТРОЙКИ → «ЖУРНАЛ ОШИБОК»
  показывает и копирует лог прошлого запуска — просить пользователя прислать его.
  `tools/soak_test.gd` — долгий бой (память, объекты, худший кадр).
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
- Sketchfab (CC-BY, авторы в README и меню): АК-74М, РГД-5, FPV-дрон, СВД, «Кобра», ПБС-1. Токен — у пользователя (в репо не класть):
  `SKETCHFAB_TOKEN=... python3 tools/fetch_sketchfab.py [имена]`
  → `tools/model_sources/` (gitignore) → `build_sketchfab_kit.py` (АК FP, бросок,
  `npc_rifle.glb` — `RIFLE_MUZZLE` печатает скрипт, `grenade.glb`, `fpv_drone.glb` с Prop0..3).
- АС «Вал» (`asval_fp.glb`, Sketchfab SLIVA21; `build_sniper_fp("asval")` + `val_parts` — магазин отделён
  по loose-частям; модель: ствол −Y, право −X): DEFS `integral` = встроенный глушитель (звук `val_*`),
  открытый прицел — кость `sight` на линии целик–мушка. `npc_asval.glb` — что падает из рук при смерти.
- Прицел АК: в `ak74_fp.glb` два прицела — «Кобра» (Kobra/RedDot, кость `sight`) и круглый коллиматор
  Aim Point Pro (Aimpoint/RedDot2, `sight2`, AIM_AT в build_sketchfab_kit.py); DEFS `sights`,
  `Settings.sight`, `Weapon.sight_of()`/`apply_mods()` переключают видимость и `ads`. По умолчанию коллиматор.
- Экран снаряжения перед боем (`main_menu._build_loadout`, KIT): «В БОЙ» → карточки → «В БОЙ ▶».
- Первая помощь (`player.start_treat`: bandage / promedol / medkit, `TREAT_TIMES`, `Weapon.busy` опускает
  оружие; `call_medic` → `game.call_medic`), ряд над хотбаром `Hud.AID_IDS`. Аптечки на карте —
  `game._place_medkits` (`assets/props/medkit.glb` из IFAK, `build_medical.py`), подбор `_medkit_pickups`.
- Медики: `Npc.medic` (повязка + IFAK на груди), `State.TREAT`, клип `medic_treat` (build_mannequin_anims.py),
  `_medic_think` ищет `needs_medic()` (без сознания / `_downed`), `patched_up()` → встаёт;
  `game.MEDICS` = 2 на сторону, `_medic_wanted` — вызов без медика рядом.
- GoPro: `Settings.camera` ("bodycam"/"gopro"), кнопка «КАМЕРА» / K: `player.GOPRO_AT`, `GOPRO_GUN`,
  `_helmet` (сфера с камуфляжем у камеры), шейдер bodycam с параметрами из `bodycam.gd`.
- Смерть как на видео: `Hud._draw_death` (красный → белая вспышка → серое со свечением `_glow` →
  чёрное, точка гаснет), `Weapon.drop()` (вьюмодель выскальзывает, падает `WORLD_GUNS`), RESPAWN_TIME 8.
- Меню оружия (`game._build_weapon_menu`): вкладки ОРУЖИЕ (взять / убрать из снаряжения / убрать из рук),
  СНАРЯЖЕНИЕ (гранаты, FPV), МОДИФИКАЦИИ (глушитель ПБС-1), БЕССМЕРТИЕ.
  `Settings.loadout` / `Settings.suppressed` (сохраняются), `Settings.carries(id)`;
  `Weapon.holstered`/`holster()`/`toggle(i)`/`apply_mods()`; хотбар (`Hud._slots()`) — только взятое.
- Глушитель: `suppressor.glb` (ПБС-1, Sketchfab 3dYaroslav) на BoneAttachment3D кости `muzzle`, размер — DEFS
  "suppressor"; без вспышки/света, звук `rifle_sup`/`sniper_sup` (`build_suppressed_sounds.py`),
  `alert × SUPPRESSED_ALERT`.
- Дрон-сброс (Mavic с двумя Ф-1) был сделан и по просьбе пользователя УБРАН целиком — не возвращать.
  Глушитель строит `build_suppressor.py`. У FpvDrone остались хуки `trigger_pressed`/`exit_pressed`.
- Раны в форме: `wound_atlas.png` (`build_wound_atlas.py`, 2×2: вход ×2, выход, осколок) →
  `Blood.body_wound` (изогнутый патч на радиус части, MultiMesh на часть, `npc._wear` = кадр/радиус/длина;
  грудь — по разгрузке), шейдер `wound_decal.gdshader`. ВАЖНО: INSTANCE_CUSTOM в Compatibility
  (OpenGL — в контейнере и, возможно, на части телефонов) урезается до 8 бит 0..1 — всё кодировать в 0..1!
  (у старых `blood_decal_mm` время/номер клетки там ломаются). Выходные раны — `npc.exit_wound` из weapon._shoot.
- Прямое попадание FPV / граната под ногами: `npc.torn_apart` (Explosion: power ≥ 1.3 и d < 1.8 или d < 0.7),
  культи `_stump` при `sever`.
- Физика рэгдолла: `_ragdoll_step` — тонус мышц `TONE` (затухает за `_tone_len`), лимит скорости частей,
  засыпание мёртвого тела (`_settled`, freeze; `wake_ragdoll()` от пули/взрыва/шага игрока; мета "settled"
  у частей и гора). Пулы: Blood `_burst` (mist/dust), вспышки NPC `_flashes`.
- Тесты: `tools/war_test.gd`, `tools/gore_test.gd`, `tools/kit_test.gd` (кобура, снаряжение, глушитель, меню),
  `tools/medic_test.gd` (прицелы, ВАЛ, GoPro, первая помощь, медик, смерть),
  `tools/mechanics_test.gd` (обморок, судороги,
  шея 5 с, авто-огонь, граната, стрелки FPV, смерть игрока), `tools/explosives_test.gd`.
  В контейнере Vulkan нет — Godot сам падает на OpenGL (llvmpipe), это медленно.
- Вылет при входе в бой (жалоба): текстуры оружия были 2048 без VRAM-сжатия (~250 МБ видеопамяти)
  и загрузка 10+ с одним кадром (ANR на Android). Сейчас: в `.import` 3D-текстур `compress/mode=2`
  (+ `size_limit=1024` у оружия) — новые текстуры тоже так ставить! Меню грузит тяжёлое в потоках
  (`main_menu.PRELOAD` → `Settings.preloaded`), `TrenchLevel` строится кусками (`_breathe`, сигнал
  `built`, `is_built`, экран «ЗАГРУЗКА ФРОНТА»), `game._ready` ждёт его; тесты ждут `game.hud`.
- Взрывы, гранаты, FPV, кровь, гор, двери, стёкла, звуки — см. README.

## Как работать с этим пользователем (выводы прошлых сессий)
- Пишет коротко и по-русски, проверяет на своём Samsung. Если просьба неоднозначна (какая модель,
  как выглядит) — спросить с вариантами/фото со Sketchfab, а не угадывать: дрон-сброс переделывался
  трижды (Mavic → UAV-самолёт → Mavic по фото) и в итоге был убран.
- Всё видимое проверять скриншотами (xvfb + Godot); звук проверить нельзя — хотя бы что поток
  загружается (глушитель однажды был «тишиной»: звуки не были прописаны в `Sfx.SOUNDS`).
- Новые звуки — в `sfx.gd` SOUNDS; новые 3D-текстуры — `compress/mode=2` (+mipmaps) в `.import`.
- Карта ×2: trenches.glb 71 МБ (сборка в Blender ~40 мин!), в бою (xvfb/OpenGL) ~222–290 МБ ОЗУ и 156 МБ
  видео (было 138/111). Навмеш 161 тыс. полигонов: после загрузки карта навигации синхронизируется
  несколько секунд — солдаты (и медик) стоят, `Npc._reachable` возвращает точку как есть, пока карта пуста.
  Если на телефоне снова вылеты — первым делом уменьшать рельеф (шаг чанков у траншей) и число деревьев.
- Медик сам приходит к раненому игроку раз в `game.MEDIC_ROUND` = 90 с (просьба пользователя), без вызова.
- Тесты: `medic_ai_test.gd` (быстрый headless: медик лечит лежащего и игрока), `map_test.gd` (кадры
  новых участков, память), `menu_test.gd` (экран снаряжения), `medic_test.gd` (env FROM=<шаг>).
- Не проверено на телефоне / открыто: вылеты на Samsung (ждём журнал из «ЖУРНАЛ ОШИБОК»);
  старые пятна крови на земле (`blood_decal_mm`) кривые в OpenGL/Compatibility (8-бит INSTANCE_CUSTOM).
- Долгие тесты: `pgrep -f <имя теста>` в until-цикле находит сам цикл — ждать по строке в логе.

