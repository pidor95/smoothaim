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
- Тесты: `godot --headless -s tools/smoke_test.gd`, `tools/gore_test.gd`, `tools/npc_behaviour_test.gd`;
  скриншоты через `xvfb-run ... --rendering-driver vulkan --rendering-method mobile`.

## Что уже есть
- Оружие: M1911, M500 (дробовик), меню оружия (B/Tab, кнопка «ОРУЖ.»).
- Карты: ДОМ (`house.gd`), МАГАЗИН (`shop.gd`, наследует House).
- NPC (`npc.gd`): анимации из Blender (`mannequin_anims.glb`), стаггеры зависят от места
  попадания, колено → падение, держится за рану (clutch), рэгдолл, встаёт.
  Стаггеры — на месте (качает, перебирает ногами), без отхода назад.
- Шея → State.CHOKE: руки на горле до конца, кашляет кровью, health < 28 → на колени,
  истекает (`_choke_drain`). Клипы `choke_stand`, `choke_knees`.
- Приказы (`Npc.ORDERS`, State.ORDER, `game.give_order`, кнопка «ПРИКАЗ», клавиши 3–9):
  клипы `hands_up`, `kneel_hands_head`.
- Пистолеты у NPC (`npc_pistol.glb`, 35%), `_despair_check` → `_start_suicide`
  (оверлей `suicide_r`, поза решается FK-поиском в build_mannequin_anims.py).
- Гор: взрыв головы/мозг, органы, кишки с дробовика, отрыв конечностей, артерии-фонтаны.
- Кровь не исчезает (MultiMesh-декали, высыхание в шейдере), простреливаемые двери.
- Убрано по просьбе: звуки крови, падения, гильз, перезарядки; надписи «ХЕДШОТ», «УБИТ».
