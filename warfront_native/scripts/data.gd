extends RefCounted
## Vehicle and weapon tables, same numbers as the browser version of the game.

const G := 9.8
const ZONE := 4700.0             # battle zone radius, m
const ZONE_KILL := 5600.0

const TYPES := {
	"su57": {"cat": "plane", "name": "Су-57", "hp": 100.0, "r": 10.0, "vmax": 330.0, "maneuver": true, "model": "su57",
		"desc": "Истребитель 5-го поколения. 8 ракет с автонаводкой, пушка, флаеры, сверхманёвренность (кобра, кульбит, разворот).",
		"slots": [{"w": "gun", "n": "Пушка", "a": 250}, {"w": "aam", "n": "Ракеты", "a": 8}, {"w": "flare", "n": "Флаеры", "a": 240}]},
	"mig29": {"cat": "plane", "name": "МиГ-29", "hp": 100.0, "r": 10.0, "vmax": 310.0, "maneuver": false, "model": "mig29",
		"desc": "Фронтовой истребитель. 8 ракет с автонаводкой, пушка, флаеры.",
		"slots": [{"w": "gun", "n": "Пушка", "a": 250}, {"w": "aam", "n": "Ракеты", "a": 8}, {"w": "flare", "n": "Флаеры", "a": 240}]},
	"ah64": {"cat": "heli", "name": "AH-64 Апач", "hp": 140.0, "r": 8.0, "vmax": 82.0, "model": "apache",
		"desc": "Ударный вертолёт. Пушка 360° с разрывными снарядами, 5 ракет с автонаводкой, 10 НАР, флаеры.",
		"slots": [{"w": "gun360", "n": "Пушка 360°", "a": 1200}, {"w": "atgm", "n": "Ракеты", "a": 5}, {"w": "rkt", "n": "НАР", "a": 10}, {"w": "flare", "n": "Флаеры", "a": 160}]},
	"mi24": {"cat": "heli", "name": "Ми-24", "hp": 160.0, "r": 9.0, "vmax": 86.0, "model": "mi24",
		"desc": "Летающий танк. Пушки по бокам, 4 ракеты с автонаводкой, 10 НАР, флаеры.",
		"slots": [{"w": "sidegun", "n": "Пушки", "a": 1000}, {"w": "atgm", "n": "Ракеты", "a": 4}, {"w": "rkt", "n": "НАР", "a": 10}, {"w": "flare", "n": "Флаеры", "a": 160}]},
	"abrams": {"cat": "tank", "name": "M1 Абрамс", "hp": 300.0, "r": 5.5, "vmax": 19.0, "model": "abrams",
		"desc": "Основной танк. 120-мм пушка, пулемёт, дымовая завеса (в дыму ракеты не наводятся).",
		"slots": [{"w": "cannon", "n": "120 мм", "a": 40}, {"w": "mg", "n": "Пулемёт", "a": 1500}, {"w": "smoke", "n": "Дым", "a": 4}]},
	"pantsir": {"cat": "tank", "kind": "ЗРПК", "name": "Панцирь-С1", "hp": 180.0, "r": 5.5, "vmax": 23.0, "model": "pantsir",
		"turn": 0.9, "turret_rate": 1.6, "pitch_rate": 1.1, "pitch_max": 1.45, "muzzle": 2.5, "aim_h": 3.6,
		"desc": "Зенитный ракетно-пушечный комплекс на колёсах. 12 зенитных ракет с автонаводкой (только по воздушным целям) и спаренные 30-мм пушки во вращающейся башне.",
		"slots": [{"w": "aa30", "n": "30-мм пушки", "a": 1400}, {"w": "sam", "n": "Ракеты ЗУР", "a": 12}, {"w": "smoke", "n": "Дым", "a": 2}]},
}
const ORDER := ["su57", "mig29", "ah64", "mi24", "abrams", "pantsir"]
const AIR := ["su57", "mig29", "ah64", "mi24"]
const GROUND := ["abrams", "pantsir"]
const CAT_RU := {"plane": "Самолёт", "heli": "Вертолёт", "tank": "Танк"}


static func kind_of(t: String) -> String:
	return TYPES[t].get("kind", CAT_RU[TYPES[t]["cat"]])

const WEAP := {
	"gun": {"auto": true, "rate": 22.0, "dmg": 7.0, "spd": 1050.0, "spread": 0.005, "life": 1.6, "col": Color(1, 0.85, 0.4), "len": 0.022},
	"gun360": {"auto": true, "rate": 10.0, "dmg": 9.0, "spd": 850.0, "spread": 0.006, "life": 2.2, "splash": 6.0, "sdmg": 7.0, "col": Color(1, 0.6, 0.25), "len": 0.025},
	"sidegun": {"auto": true, "rate": 16.0, "dmg": 7.0, "spd": 950.0, "spread": 0.008, "life": 1.8, "col": Color(1, 0.85, 0.4), "len": 0.022},
	"mg": {"auto": true, "rate": 12.0, "dmg": 3.5, "spd": 900.0, "spread": 0.006, "life": 1.8, "col": Color(1, 0.95, 0.6), "len": 0.02},
	"cannon": {"auto": false, "rate": 0.25, "dmg": 170.0, "spd": 1600.0, "spread": 0.0008, "life": 4.0, "splash": 9.0, "sdmg": 70.0, "col": Color(1, 0.9, 0.7), "len": 0.03},
	"rkt": {"auto": true, "rate": 4.0, "dmg": 45.0, "launch": 60.0, "burn": 1.1, "thrust": 480.0, "drag": 1.6e-4, "life": 6.0, "splash": 12.0, "sdmg": 40.0},
	"aam": {"auto": false, "rate": 1.2, "homing": true, "dmg": 110.0, "launch": 25.0, "burn": 4.0, "thrust": 170.0, "drag": 9e-5, "max_g": 38.0, "nav": 4.0,
		"gimbal": 1.05, "min_spd": 260.0, "life": 20.0, "prox": 14.0, "range": 6000.0, "cone": 0.38, "lock_t": 1.2},
	"atgm": {"auto": false, "rate": 1.0, "homing": true, "dmg": 125.0, "launch": 35.0, "burn": 2.6, "thrust": 170.0, "drag": 1.4e-4, "max_g": 16.0, "nav": 3.5,
		"gimbal": 0.8, "min_spd": 140.0, "life": 14.0, "prox": 9.0, "range": 4000.0, "cone": 0.42, "lock_t": 1.4},
	"flare": {"auto": true, "rate": 12.0},
	"smoke": {"auto": false, "rate": 0.5},
	"aa30": {"auto": true, "rate": 25.0, "dmg": 9.0, "spd": 960.0, "spread": 0.004, "life": 3.2, "splash": 4.0, "sdmg": 6.0, "col": Color(1, 0.7, 0.3), "len": 0.024},
	"sam": {"auto": false, "rate": 1.0, "homing": true, "air_only": true, "dmg": 140.0, "launch": 60.0, "burn": 2.4, "thrust": 420.0, "drag": 6e-5, "max_g": 35.0, "nav": 4.0,
		"gimbal": 1.2, "min_spd": 250.0, "life": 16.0, "prox": 12.0, "range": 9000.0, "cone": 0.5, "lock_t": 1.4},
}
const W_RU := {"gun": "пушка", "gun360": "пушка", "sidegun": "пушки", "mg": "пулемёт", "cannon": "120 мм", "rkt": "НАР",
	"aam": "ракета", "atgm": "ракета", "aa30": "30 мм", "sam": "ЗУР", "crash": "крушение", "zone": "вне зоны"}

## Bot skill. err: aim error, msl: seconds between missiles, flare: chance to flare, lock: lock time factor,
## turn: share of the player's turn rate, react: seconds before opening fire, gun: share of time spent firing.
const DIFF := [
	{"n": "Легко", "err": 0.07, "msl": 40.0, "flare": 0.25, "lock": 2.2, "turn": 0.65, "react": 3.5, "gun": 0.25},
	{"n": "Норма", "err": 0.045, "msl": 26.0, "flare": 0.45, "lock": 1.7, "turn": 0.78, "react": 2.2, "gun": 0.4},
	{"n": "Сложно", "err": 0.025, "msl": 16.0, "flare": 0.7, "lock": 1.3, "turn": 0.9, "react": 1.2, "gun": 0.6},
]

## Flight model. m kg, s m², thrust N (military / afterburner), cla per rad, a_st stall AoA rad,
## n G-limit, pr/rr/yr max body rates rad/s, tvc = thrust vectoring.
const AERO := {
	"su57": {"m": 25000.0, "s": 78.8, "mil": 176e3, "ab": 290e3, "cla": 3.6, "a_st": 0.42, "cl_max": 1.5, "cd0": 0.021, "k": 0.11, "n": 9.0, "pr": 1.4, "rr": 4.2, "yr": 0.35, "tvc": true},
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
