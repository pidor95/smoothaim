extends RefCounted
## Vehicle and weapon tables, same numbers as the browser version of the game.

const G := 9.8
const ZONE := 4700.0             # battle zone radius, m
const ZONE_KILL := 5600.0

const TYPES := {
	"su57": {"cat": "plane", "name": "Су-57", "hp": 100.0, "r": 10.0, "vmax": 330.0, "maneuver": true, "model": "su57", "small": 0.3,
		"desc": "Истребитель 5-го поколения. 8 ракет с автонаводкой, пушка, флаеры, сверхманёвренность (кобра, кульбит, разворот).",
		"slots": [{"w": "gun", "n": "Пушка", "a": 250}, {"w": "aam", "n": "Ракеты", "a": 8}, {"w": "flare", "n": "Флаеры", "a": 240}]},
	"mig29": {"cat": "plane", "name": "МиГ-29", "hp": 100.0, "r": 10.0, "vmax": 310.0, "maneuver": false, "model": "mig29", "small": 0.3,
		"desc": "Фронтовой истребитель. 8 ракет с автонаводкой, пушка, флаеры.",
		"slots": [{"w": "gun", "n": "Пушка", "a": 250}, {"w": "aam", "n": "Ракеты", "a": 8}, {"w": "flare", "n": "Флаеры", "a": 240}]},
	"su27": {"cat": "plane", "kind": "Истребитель", "name": "Су-27", "hp": 110.0, "r": 10.0, "vmax": 345.0, "maneuver": false, "model": "su27", "small": 0.3,
		"desc": "Тяжёлый истребитель. Пушка ГШ-30-1, ракеты ближнего боя Р-73 и средней дальности Р-27, бомбы ФАБ-250, флаеры.",
		"slots": [{"w": "gun30", "n": "ГШ-30-1", "a": 150}, {"w": "r73", "n": "Р-73", "a": 4}, {"w": "r27", "n": "Р-27", "a": 2},
			{"w": "fab250", "n": "ФАБ-250", "a": 4}, {"w": "flare", "n": "Флаеры", "a": 96}]},
	"su25": {"cat": "plane", "kind": "Штурмовик", "name": "Су-25М", "hp": 170.0, "r": 9.0, "vmax": 265.0, "maneuver": false, "model": "su25", "small": 0.12,
		"desc": "Бронированный штурмовик «Грач». Пушка ГШ-30-2, 40 НАР С-8, бомбы ФАБ-250, управляемые ракеты Х-25 по наземным целям, 2 ракеты Р-60 для самообороны, флаеры.",
		"slots": [{"w": "gun30", "n": "ГШ-30-2", "a": 250}, {"w": "rkt", "n": "НАР С-8", "a": 40}, {"w": "fab250", "n": "ФАБ-250", "a": 4},
			{"w": "kh25", "n": "Х-25", "a": 2}, {"w": "r60", "n": "Р-60", "a": 2}, {"w": "flare", "n": "Флаеры", "a": 256}]},
	"su24": {"cat": "plane", "kind": "Бомбардировщик", "name": "Су-24М", "hp": 140.0, "r": 11.0, "vmax": 360.0, "maneuver": false, "model": "su24", "small": 0.2,
		"desc": "Фронтовой бомбардировщик с изменяемой стреловидностью крыла. Пушка ГШ-6-23, 2 крылатые ракеты Storm Shadow (дальность 20 км, полёт у земли), бомбы ФАБ-500, 2 ракеты Р-60, флаеры.",
		"slots": [{"w": "gun23", "n": "ГШ-6-23", "a": 500}, {"w": "storm", "n": "Storm Shadow", "a": 2}, {"w": "fab500", "n": "ФАБ-500", "a": 4},
			{"w": "r60", "n": "Р-60", "a": 2}, {"w": "flare", "n": "Флаеры", "a": 120}]},
	"ah64": {"cat": "heli", "name": "AH-64 Апач", "hp": 140.0, "r": 8.0, "vmax": 82.0, "model": "apache", "small": 0.25,
		"desc": "Ударный вертолёт. Пушка 360° с разрывными снарядами, 5 ракет с автонаводкой, 10 НАР, флаеры.",
		"slots": [{"w": "gun360", "n": "Пушка 360°", "a": 1200}, {"w": "atgm", "n": "Ракеты", "a": 5}, {"w": "rkt", "n": "НАР", "a": 10}, {"w": "flare", "n": "Флаеры", "a": 160}]},
	"mi24": {"cat": "heli", "name": "Ми-24", "hp": 160.0, "r": 9.0, "vmax": 86.0, "model": "mi24", "small": 0.15,
		"desc": "Летающий танк. Пушки по бокам, 4 ракеты с автонаводкой, 10 НАР, флаеры.",
		"slots": [{"w": "sidegun", "n": "Пушки", "a": 1000}, {"w": "atgm", "n": "Ракеты", "a": 4}, {"w": "rkt", "n": "НАР", "a": 10}, {"w": "flare", "n": "Флаеры", "a": 160}]},
	"abrams": {"cat": "tank", "name": "M1 Абрамс", "hp": 300.0, "r": 5.5, "vmax": 19.0, "model": "abrams", "small": 0.0,
		"desc": "Основной танк. 120-мм пушка, пулемёт, дымовая завеса (в дыму ракеты не наводятся).",
		"slots": [{"w": "cannon", "n": "120 мм", "a": 40}, {"w": "mg", "n": "Пулемёт", "a": 1500}, {"w": "smoke", "n": "Дым", "a": 4}]},
	"pantsir": {"cat": "tank", "kind": "ЗРПК", "name": "Панцирь-С1", "hp": 180.0, "r": 5.5, "vmax": 23.0, "model": "pantsir", "small": 0.04,
		"turn": 0.9, "turret_rate": 1.6, "pitch_rate": 1.1, "pitch_max": 1.45, "muzzle": 2.5, "aim_h": 3.6,
		"desc": "Зенитный ракетно-пушечный комплекс на колёсах. 12 зенитных ракет с автонаводкой (только по воздушным целям) и спаренные 30-мм пушки во вращающейся башне.",
		"slots": [{"w": "aa30", "n": "30-мм пушки", "a": 1400}, {"w": "sam", "n": "Ракеты ЗУР", "a": 12}, {"w": "smoke", "n": "Дым", "a": 2}]},
	"soldier": {"cat": "inf", "kind": "Пехота", "name": "Пехотинец", "hp": 100.0, "r": 0.6, "vmax": 4.4, "model": "soldier",
		"desc": "Солдат с АК-47, дробовиком и ПЗРК «Стингер» (сбивает самолёты и вертолёты). Попадание в голову — сразу насмерть.",
		"slots": [{"w": "ak", "n": "АК-47", "a": 240}, {"w": "shotgun", "n": "Дробовик", "a": 40}, {"w": "stinger", "n": "Стингер", "a": 3}]},
	# fortifications at the assault points (red side); they never respawn during a match
	"bunker": {"cat": "struct", "kind": "Укрепление", "name": "Бункер", "hp": 420.0, "r": 6.5, "vmax": 0.0, "model": "proc:bunker", "small": 0.0, "aim_h": 1.3,
		"desc": "", "slots": [{"w": "mg", "n": "Пулемёт", "a": 99999}]},
	"zu23": {"cat": "struct", "kind": "Зенитка", "name": "ЗУ-23-2", "hp": 140.0, "r": 3.2, "vmax": 0.0, "model": "proc:zu23", "small": 0.35, "aim_h": 1.25,
		"turret_rate": 1.4, "pitch_rate": 1.1, "pitch_max": 1.5, "muzzle": 2.4, "desc": "", "slots": [{"w": "zu23", "n": "2×23 мм", "a": 99999}]},
	"depot": {"cat": "struct", "kind": "Склад", "name": "Склад боеприпасов", "hp": 260.0, "r": 7.0, "vmax": 0.0, "model": "proc:depot", "small": 0.1,
		"desc": "", "slots": [{"w": "smoke", "n": "-", "a": 0}]},
}
const ORDER := ["su57", "mig29", "su27", "su25", "su24", "ah64", "mi24", "abrams", "pantsir", "soldier"]
const AIR := ["su57", "mig29", "su27", "su25", "su24", "ah64", "mi24"]
const GROUND := ["abrams", "pantsir"]
const INF := ["soldier"]
const CAT_RU := {"plane": "Самолёт", "heli": "Вертолёт", "tank": "Танк", "inf": "Пехота", "struct": "Укрепление"}
## Menu groups and the bars on the vehicle card: speed, armour, firepower, agility (0..1).
const GROUPS := [["Истребители", ["su57", "mig29", "su27"]], ["Штурмовики", ["su25", "su24"]], ["Вертолёты", ["ah64", "mi24"]],
	["Наземная", ["abrams", "pantsir"]], ["Пехота", ["soldier"]]]
const STATS := {"su57": [0.95, 0.35, 0.7, 1.0], "mig29": [0.9, 0.35, 0.6, 0.85], "su27": [0.97, 0.4, 0.75, 0.85],
	"su25": [0.7, 0.75, 0.95, 0.6], "su24": [1.0, 0.5, 1.0, 0.45], "ah64": [0.25, 0.55, 0.8, 0.7], "mi24": [0.27, 0.65, 0.75, 0.55],
	"abrams": [0.08, 1.0, 0.85, 0.3], "pantsir": [0.1, 0.7, 0.8, 0.35], "soldier": [0.02, 0.15, 0.3, 1.0]}


static func kind_of(t: String) -> String:
	return TYPES[t].get("kind", CAT_RU[TYPES[t]["cat"]])

const WEAP := {
	"gun": {"auto": true, "rate": 22.0, "dmg": 7.0, "spd": 1050.0, "spread": 0.005, "life": 1.6, "col": Color(1, 0.85, 0.4), "len": 0.022},
	"gun30": {"auto": true, "rate": 20.0, "dmg": 11.0, "spd": 870.0, "spread": 0.005, "life": 2.0, "splash": 3.0, "sdmg": 5.0, "col": Color(1, 0.75, 0.35), "len": 0.024},
	"gun23": {"auto": true, "rate": 30.0, "dmg": 6.5, "spd": 715.0, "spread": 0.006, "life": 2.0, "col": Color(1, 0.85, 0.4), "len": 0.022},
	"zu23": {"auto": true, "rate": 14.0, "dmg": 7.0, "spd": 970.0, "spread": 0.006, "life": 3.0, "splash": 3.0, "sdmg": 4.0, "col": Color(1, 0.6, 0.25), "len": 0.024},
	"gun360": {"auto": true, "rate": 10.0, "dmg": 9.0, "spd": 850.0, "spread": 0.006, "life": 2.2, "splash": 6.0, "sdmg": 7.0, "col": Color(1, 0.6, 0.25), "len": 0.025},
	"sidegun": {"auto": true, "rate": 16.0, "dmg": 7.0, "spd": 950.0, "spread": 0.008, "life": 1.8, "col": Color(1, 0.85, 0.4), "len": 0.022},
	"mg": {"auto": true, "rate": 12.0, "dmg": 3.5, "spd": 900.0, "spread": 0.006, "life": 1.8, "col": Color(1, 0.95, 0.6), "len": 0.02},
	"cannon": {"auto": false, "rate": 0.25, "dmg": 170.0, "spd": 1600.0, "spread": 0.0008, "life": 4.0, "splash": 9.0, "sdmg": 70.0, "col": Color(1, 0.9, 0.7), "len": 0.03},
	"rkt": {"auto": true, "rate": 4.0, "dmg": 45.0, "launch": 60.0, "burn": 1.1, "thrust": 480.0, "drag": 1.6e-4, "life": 6.0, "splash": 12.0, "sdmg": 40.0},
	"aam": {"auto": false, "rate": 1.2, "homing": true, "dmg": 110.0, "launch": 25.0, "burn": 4.0, "thrust": 170.0, "drag": 9e-5, "max_g": 38.0, "nav": 4.0,
		"gimbal": 1.05, "min_spd": 260.0, "life": 20.0, "prox": 14.0, "range": 6000.0, "cone": 0.38, "lock_t": 1.2},
	"atgm": {"auto": false, "rate": 1.0, "homing": true, "dmg": 125.0, "launch": 35.0, "burn": 2.6, "thrust": 170.0, "drag": 1.4e-4, "max_g": 16.0, "nav": 3.5,
		"gimbal": 0.8, "min_spd": 140.0, "life": 14.0, "prox": 9.0, "range": 4000.0, "cone": 0.42, "lock_t": 1.4},
	"r60": {"auto": false, "rate": 1.2, "homing": true, "air_only": true, "dmg": 85.0, "launch": 25.0, "burn": 3.0, "thrust": 230.0, "drag": 1.1e-4, "max_g": 40.0, "nav": 4.0,
		"gimbal": 1.2, "min_spd": 220.0, "life": 14.0, "prox": 10.0, "range": 3500.0, "cone": 0.5, "lock_t": 0.9},
	"r73": {"auto": false, "rate": 1.2, "homing": true, "air_only": true, "dmg": 100.0, "launch": 25.0, "burn": 3.5, "thrust": 240.0, "drag": 9e-5, "max_g": 42.0, "nav": 4.0,
		"gimbal": 1.3, "min_spd": 230.0, "life": 16.0, "prox": 12.0, "range": 5000.0, "cone": 0.6, "lock_t": 0.9},
	"r27": {"auto": false, "rate": 1.0, "homing": true, "air_only": true, "dmg": 125.0, "launch": 25.0, "burn": 5.0, "thrust": 180.0, "drag": 7e-5, "max_g": 32.0, "nav": 4.0,
		"gimbal": 1.0, "min_spd": 260.0, "life": 26.0, "prox": 16.0, "range": 9000.0, "cone": 0.3, "lock_t": 1.6},
	# air-to-ground: Kh-25 guided missile, Storm Shadow cruise missile, free-fall bombs aimed with the CCIP mark
	"kh25": {"auto": false, "rate": 1.0, "homing": true, "ground_only": true, "dmg": 420.0, "splash": 16.0, "sdmg": 160.0, "launch": 25.0, "burn": 4.0, "thrust": 160.0,
		"drag": 1.0e-4, "max_g": 14.0, "nav": 3.5, "gimbal": 0.9, "min_spd": 150.0, "life": 22.0, "prox": 7.0, "range": 8000.0, "cone": 0.22, "lock_t": 1.6},
	"storm": {"auto": false, "rate": 0.5, "homing": true, "ground_only": true, "cruise": true, "dmg": 900.0, "splash": 32.0, "sdmg": 450.0, "launch": 0.0, "burn": 999.0,
		"thrust": 0.0, "drag": 0.0, "max_g": 6.0, "nav": 3.0, "gimbal": 3.2, "min_spd": 0.0, "life": 120.0, "prox": 9.0, "range": 20000.0, "cone": 0.2, "lock_t": 2.0,
		"cruise_spd": 270.0, "cruise_alt": 45.0},
	"fab250": {"auto": false, "rate": 2.5, "bomb": true, "dmg": 500.0, "splash": 30.0, "sdmg": 260.0, "drag": 1.6e-5, "life": 60.0},
	"fab500": {"auto": false, "rate": 2.0, "bomb": true, "dmg": 900.0, "splash": 44.0, "sdmg": 380.0, "drag": 1.4e-5, "life": 60.0},
	"flare": {"auto": true, "rate": 12.0},
	"smoke": {"auto": false, "rate": 0.5},
	"aa30": {"auto": true, "rate": 25.0, "dmg": 9.0, "spd": 960.0, "spread": 0.004, "life": 3.2, "splash": 4.0, "sdmg": 6.0, "col": Color(1, 0.7, 0.3), "len": 0.024},
	# infantry: "small" weapons do little to armour; "mag" rounds per magazine, "reload" seconds
	"ak": {"auto": true, "rate": 10.0, "dmg": 34.0, "spd": 715.0, "spread": 0.006, "life": 1.4, "col": Color(1, 0.8, 0.45), "len": 0.012,
		"small": true, "mag": 30, "reload": 2.4},
	"shotgun": {"auto": false, "rate": 1.25, "dmg": 16.0, "pellets": 9, "spd": 420.0, "spread": 0.04, "life": 0.6, "col": Color(1, 0.75, 0.4), "len": 0.008,
		"small": true, "mag": 6, "reload": 3.2},
	"stinger": {"auto": false, "rate": 0.3, "homing": true, "air_only": true, "dmg": 130.0, "launch": 28.0, "burn": 2.8, "thrust": 380.0, "drag": 8e-5, "max_g": 26.0, "nav": 4.0,
		"gimbal": 1.0, "min_spd": 200.0, "life": 13.0, "prox": 10.0, "range": 4800.0, "cone": 0.3, "lock_t": 1.8, "mag": 1, "reload": 3.5},
	"sam": {"auto": false, "rate": 1.0, "homing": true, "air_only": true, "dmg": 140.0, "launch": 60.0, "burn": 2.4, "thrust": 420.0, "drag": 6e-5, "max_g": 35.0, "nav": 4.0,
		"gimbal": 1.2, "min_spd": 250.0, "life": 16.0, "prox": 12.0, "range": 9000.0, "cone": 0.5, "lock_t": 1.4},
}
const W_RU := {"gun": "пушка", "gun360": "пушка", "sidegun": "пушки", "mg": "пулемёт", "cannon": "120 мм", "rkt": "НАР",
	"aam": "ракета", "atgm": "ракета", "aa30": "30 мм", "sam": "ЗУР", "ak": "АК-47", "shotgun": "дробовик", "stinger": "Стингер",
	"headshot": "ХЕДШОТ", "crash": "крушение", "zone": "вне зоны", "gun30": "ГШ-30", "gun23": "ГШ-6-23", "zu23": "ЗУ-23", "r60": "Р-60",
	"r73": "Р-73", "r27": "Р-27", "kh25": "Х-25", "storm": "Storm Shadow", "fab250": "ФАБ-250", "fab500": "ФАБ-500", "blast": "детонация"}

## Bot skill. err: aim error, msl: seconds between missiles, flare: chance to flare, lock: lock time factor,
## turn: share of the player's turn rate, react: seconds before opening fire, gun: share of time spent firing,
## inf: infantry aim error (radians), dmg: share of normal damage bots deal.
const DIFF := [
	{"n": "Новичок", "err": 0.11, "msl": 60.0, "flare": 0.15, "lock": 3.0, "turn": 0.55, "react": 5.0, "gun": 0.15, "inf": 0.03, "dmg": 0.5},
	{"n": "Легко", "err": 0.085, "msl": 45.0, "flare": 0.25, "lock": 2.4, "turn": 0.62, "react": 4.0, "gun": 0.22, "inf": 0.022, "dmg": 0.7},
	{"n": "Норма", "err": 0.06, "msl": 32.0, "flare": 0.4, "lock": 1.9, "turn": 0.72, "react": 2.8, "gun": 0.32, "inf": 0.015, "dmg": 0.85},
	{"n": "Сложно", "err": 0.04, "msl": 22.0, "flare": 0.55, "lock": 1.5, "turn": 0.84, "react": 1.8, "gun": 0.45, "inf": 0.01, "dmg": 1.0},
	{"n": "Ас", "err": 0.025, "msl": 15.0, "flare": 0.7, "lock": 1.25, "turn": 0.92, "react": 1.0, "gun": 0.6, "inf": 0.006, "dmg": 1.0},
]

## Flight model. m kg, s m², thrust N (military / afterburner), cla per rad, a_st stall AoA rad,
## n G-limit, pr/rr/yr max body rates rad/s, tvc = thrust vectoring.
const AERO := {
	"su57": {"m": 25000.0, "s": 78.8, "mil": 176e3, "ab": 290e3, "cla": 3.6, "a_st": 0.42, "cl_max": 1.5, "cd0": 0.021, "k": 0.11, "n": 9.0, "pr": 1.4, "rr": 4.2, "yr": 0.35, "tvc": true},
	"su27": {"m": 23000.0, "s": 62.0, "mil": 150e3, "ab": 245e3, "cla": 3.6, "a_st": 0.42, "cl_max": 1.5, "cd0": 0.022, "k": 0.11, "n": 9.0, "pr": 1.35, "rr": 4.2, "yr": 0.32, "tvc": false},
	"su25": {"m": 15000.0, "s": 30.1, "mil": 82e3, "ab": 88e3, "cla": 3.4, "a_st": 0.38, "cl_max": 1.35, "cd0": 0.034, "k": 0.11, "n": 6.5, "pr": 1.05, "rr": 2.8, "yr": 0.3, "tvc": false},
	"su24": {"m": 30000.0, "s": 55.2, "mil": 150e3, "ab": 218e3, "cla": 3.4, "a_st": 0.36, "cl_max": 1.3, "cd0": 0.025, "k": 0.12, "n": 6.0, "pr": 0.9, "rr": 2.3, "yr": 0.25, "tvc": false},
	"mig29": {"m": 16500.0, "s": 38.0, "mil": 100e3, "ab": 163e3, "cla": 3.5, "a_st": 0.4, "cl_max": 1.4, "cd0": 0.022, "k": 0.12, "n": 9.0, "pr": 1.3, "rr": 4.6, "yr": 0.3, "tvc": false},
}

## Airshow post-stall manoeuvres: body rates [pitch, yaw, roll] (pitch up negative) as a function of time.
const MANEUVERS := {
	"cobra": {"n": "Кобра", "dur": 1.8},
	"kulbit": {"n": "Кульбит", "dur": 2.2},
	"flat": {"n": "Разворот", "dur": 1.6},
}


static func maneuver_rate(type: String, t: float, side: float) -> Vector3:
	match type:
		"cobra":
			return Vector3(-3.1 if t < 0.6 else 0.0 if t < 1.0 else 3.1 if t < 1.6 else 0.0, 0, 0)
		"kulbit":
			return Vector3(-TAU / 2.1 if t < 2.1 else 0.0, 0, 0)
		_:
			return Vector3(0, side * PI / 1.5 if t < 1.5 else 0.0, 0)
