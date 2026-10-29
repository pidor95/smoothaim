# PHYSICS BOX — заметки для следующих сессий

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
- Тесты: `godot --headless -s tools/smoke_test.gd`, `tools/gore_test.gd`, `tools/npc_behaviour_test.gd`
  (уровень «дом»), `tools/war_test.gd`, `tools/explosives_test.gd` (окопы);
  в `-s` скриптах автолоады только через `root.get_node("Settings")`;
  скриншоты через `xvfb-run ... --rendering-driver vulkan --rendering-method mobile`.

## Что уже есть
- ВОЙНА (по видео пользователя с окопным шутером): гражданских
  манекенов больше нет, все NPC — солдаты двух команд (`Npc.team` 0 = «ВИТЯЗЬ»
  игрока, 1 = «ОПОЛЧЕНИЕ»), тикеты/подкрепления/раунды в `game.gd`
  (`spawn_soldier`, `TEAM_ALIVE`, `TICKETS`), счёт в HUD. Рентген удалён по просьбе.
- Карта ОКОПЫ (по умолчанию, `trench_level.gd` грузит `assets/maps/trenches.glb` из
  `build_trenches.py`; пустышки SpawnA/B_*, PostA/B_*, Player; коллизии C_*; навмеш
  cell 0.25/0.1). Пол траншей плоский до стены (FLAT), стены — выпуклые призмы.
- Солдат: камуфляж (`build_war_textures.py`), каска/бронежилет (`soldier_gear.glb`),
  АК (`npc_rifle.glb`, `RIFLE_BASIS` = RIFLE_ATTACH из build_mannequin_anims.py,
  позы `rifle_ready/aim` — аналитическая IK `rifle_pose`). ИИ: `_war_think`
  (поиск целей), `_shoot_process` (очереди), `_war_move` (hold/assault), гранаты
  `_throw_grenade`; свои не стреляют сквозь своих.
- Раненые: `SURVIVE_CHANCE`, `_downed` → пол (`down_floor/down_roll_l/r`), добивание.
- Взрывы `explosion.gd` (огонь/дым/грязь CPUParticles, Decal, ударная волна
  `Npc.blast`, осколки), гранаты `grenade.gd` (РГД-5, `build_explosives.py`),
  FPV `fpv_drone.gd` (игрок пилотирует через камеру, враги пикируют; модель там же).
- Оружие: M1911, M500 (дробовик), меню оружия (B/Tab, кнопка «ОРУЖ.»).
- Карты: ДОМ (`house.gd`), МАГАЗИН (`shop.gd`, наследует House) — тоже с войной
  (точки делятся по дальности от игрока).
- NPC (`npc.gd`): анимации из Blender (`mannequin_anims.glb`), стаггеры зависят от места
  попадания, колено → падение, держится за рану (clutch), рэгдолл, встаёт.
  Стаггеры — на месте (качает, перебирает ногами), без отхода назад.
- Шея → State.CHOKE, `_choke_phase` 0 стоит → 1 колени → 2 падает → 3 катается по полу
  (клипы `choke_stand/knees/fall/floor`, поза лёжа через `lying()` в Blender-скрипте);
  руки на горле до конца, кашляет кровью, истекает (`_choke_drain`). Сбитый с ног
  с раной шеи не встаёт — `_start_floor_choke` (общий `_freeze_from_ragdoll`).
- Пол при шее: `_pick_floor_clip` — случайно `choke_floor` (корчится) / `choke_roll_l/r`
  (перекат, горизонталь таза → root motion), случайный темп.
- Стрельба NPC: State.SHOOT (`_wants_to_fight` в alert, `_shoot_process`, `_fire_at`),
  при удушье `_wild_fire`; оверлеи руки `pistol_ready`/`pistol_aim` (+ поворот плеча
  `_aim_yaw/_aim_pitch`), позы решает `solve_gun` в build_mannequin_anims.py.
- Игрок: `Player.health/take_damage/dead/_respawn`, `Player.immortal` (вкладка в меню
  оружия), гранаты/дроны с восполнением, тряска камеры `add_shake`.
- `panic_run` — спринт (бег солдат при атаке, `_speed` > 3).
- Приказы (`Npc.ORDERS`, State.ORDER, `game.give_order`, кнопка «ПРИКАЗ», клавиши 3–9, 0;
  «suicide» — застрелись):
  клипы `hands_up`, `kneel_hands_head`.
- Пистолеты у NPC (`npc_pistol.glb` из `assets/m1911/m1911.fbx`, текстура общая с FP),
  `_despair_check` → `_start_suicide`
  (оверлей `suicide_r`, поза решается FK-поиском в build_mannequin_anims.py).
- Гор: взрыв головы/мозг, органы, кишки с дробовика, отрыв конечностей, артерии-фонтаны.
- Кровь не исчезает (MultiMesh-декали, высыхание в шейдере), простреливаемые двери.
- Звуки выстрелов (пистолет, АК), стекла, взрывов, дрона — записи с zvukipro.com
  (`tools/sound_sources/`, нарезка `build_recorded_sounds.py`).
- Sketchfab: скачивание моделей требует API-токен (без него 401) — его нет. Кандидаты
  (CC-BY): FPV «FPV kamikaze drone Low-poly» 87f5bbb5b08641b782bc084ddd4082a7,
  AK-74M SeveN-Models 84bb0a58a18047069706047639b82899, РГД-5 886637c9482b4cc4960d0112684baac6.
- Убрано по просьбе: звуки крови, падения, гильз, перезарядки; надписи «ХЕДШОТ», «УБИТ».
