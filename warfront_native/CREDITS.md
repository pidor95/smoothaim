# Боевой Фронт — источники данных и ассетов

Карта — реальная местность у Прохоровки (Белгородская область), квадрат 10,4 × 10,4 км.

- Рельеф: AWS Terrain Tiles (Mapzen terrarium; SRTM и др. открытые источники).
- Спутниковый снимок: Sentinel-2 cloudless 2020 by EOX IT Services GmbH (contains modified Copernicus Sentinel data 2020), лицензия CC BY-NC-SA 4.0.
- Здания, леса, дороги, вода: © участники OpenStreetMap, лицензия ODbL.
- Текстуры земли, стен и крыш: ambientCG (CC0). Небо (HDRI): Poly Haven, kloofendal_48d_partly_cloudy_puresky (CC0).
- Деревья: сгенерированы в Blender (Sapling Tree Gen) и запечены в спрайты.
- Модели Су-57, Ми-24, Панцирь-С1, МиГ-29, AH-64, M1 Абрамс: файлы, присланные автором игры, обработаны в Blender (`tools/blender_vehicles.py`, `tools/blender_models2.py`), затенение (AO) запечено скриптом `tools/blender_ao.py`.
- Оружие пехоты (АК-47, Mossberg M500 с глушителем, ПЗРК «Стингер»): модели, присланные автором игры, обработаны скриптом `tools/blender_weapons.py`.
- Солдат: построен скриптом `tools/blender_soldier.py` (отдельные части тела для процедурной анимации и рэгдолла).
- Звуки и спрайты эффектов: синтезированы скриптом `tools/make_fx.py`.

Сборка ассетов: `tools/process_map.py` (карта), `tools/blender_*.py` (Blender 4.5, деревья, здания, техника).
