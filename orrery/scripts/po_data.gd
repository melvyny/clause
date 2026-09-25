extends RefCounted
## Porcelain Orrery :: static game data.
## Elements, reactions, species, skills, statuses, rune sets and stat formula.
## No `class_name` anywhere in this prototype: scripts reference each other via
## `preload()` constants, so nothing leaks into the project's global namespace.

enum Element { FIRE, WATER, WIND, LIGHT, DARK }

const ELEMENT_NAMES := ["火", "水", "风", "光", "暗"]
const ELEMENT_NAMES_EN := ["Ember", "Tide", "Gale", "Radiant", "Umbral"]
const ELEMENT_COLORS := [
	Color(1.0, 0.36, 0.16),
	Color(0.2, 0.7, 1.0),
	Color(0.35, 1.0, 0.6),
	Color(1.0, 0.86, 0.36),
	Color(0.78, 0.35, 1.0),
]

## Fire -> Wind -> Water -> Fire.  Light and Dark are strong against each other.
const BEATS := {Element.FIRE: Element.WIND, Element.WIND: Element.WATER, Element.WATER: Element.FIRE}

# --- Combat tuning --------------------------------------------------------------
const ATB_PER_SPD := 0.07           # Attack Bar gained per tick = SPD * 7%
const ADV_CRIT_BONUS := 15.0
const ADV_DAMAGE_MULT := 1.30
const DISADV_DAMAGE_MULT := 0.85
const GLANCING_CHANCE := 0.30
const GLANCING_MULT := 0.70
const CRUSHING_CHANCE := 0.40
const CRUSHING_MULT := 1.20
const ATK_UP := 0.5
const DEF_UP := 0.7
const DEF_BREAK := 0.7
const DOT_PCT := 0.05
const MIN_RESIST := 15.0
const ENERGY_START := 25.0
const ENERGY_PER_ACTION := 25.0
const ENERGY_ON_HIT := 8.0
const ENERGY_ON_KILL := 15.0
const MARK_TURNS := 2


static func affinity(attacker: int, defender: int) -> int:
	if attacker >= Element.LIGHT and defender >= Element.LIGHT and attacker != defender:
		return 1
	if BEATS.get(attacker, -1) == defender:
		return 1
	if BEATS.get(defender, -1) == attacker:
		return -1
	return 0


# --- Element Fission (reactions) ---------------------------------------------------
# Every damaging skill leaves the caster's element Mark on the target. Hitting a
# marked target with a *different* element consumes the Mark and triggers a
# reaction. Team order and composition therefore matter far more than raw stats.
const REACTIONS := {
	"wildfire": {"name": "焰暴", "en": "Firestorm", "desc": "40% of the hit splashes onto every other enemy."},
	"steam": {"name": "蒸腾", "en": "Steam Burst", "desc": "Target's Attack Bar -40%."},
	"frost": {"name": "冰封", "en": "Frostbind", "desc": "Freezes the target for 1 turn (ignores Resistance)."},
	"annihilate": {"name": "湮灭", "en": "Annihilation", "desc": "Extra damage equal to 12% of target's max HP."},
	"radiance": {"name": "辉光", "en": "Radiance", "desc": "Heals the attacker's team by 10% of their max HP."},
	"corrode": {"name": "蚀裂", "en": "Corrosion", "desc": "Defense Break + Continuous Damage for 2 turns."},
}


## Returns the reaction id for mark `a` hit by element `b`, or "" for none.
static func reaction(a: int, b: int) -> String:
	if a == b or a < 0:
		return ""
	var pair := [mini(a, b), maxi(a, b)]
	if pair == [Element.FIRE, Element.WIND]:
		return "wildfire"
	if pair == [Element.FIRE, Element.WATER]:
		return "steam"
	if pair == [Element.WATER, Element.WIND]:
		return "frost"
	if pair == [Element.LIGHT, Element.DARK]:
		return "annihilate"
	if a == Element.LIGHT or b == Element.LIGHT:
		return "radiance"
	return "corrode"


# --- Statuses -------------------------------------------------------------------
const STATUS := {
	"atk_up": {"label": "攻↑", "name": "Attack Up", "buff": true, "color": Color(1.0, 0.55, 0.25), "desc": "Attack +50%"},
	"def_up": {"label": "防↑", "name": "Defense Up", "buff": true, "color": Color(0.35, 0.75, 1.0), "desc": "Defense +70%"},
	"immunity": {"label": "免", "name": "Immunity", "buff": true, "color": Color(1.0, 0.92, 0.55), "desc": "Immune to harmful effects"},
	"def_break": {"label": "破", "name": "Defense Break", "buff": false, "color": Color(0.95, 0.3, 0.3), "desc": "Defense -70%"},
	"dot": {"label": "蚀", "name": "Continuous Damage", "buff": false, "color": Color(0.85, 0.35, 0.9), "desc": "Takes 5% max HP each turn"},
	"stun": {"label": "晕", "name": "Stun", "buff": false, "color": Color(1.0, 0.85, 0.2), "desc": "Skips the next turn"},
	"freeze": {"label": "冰", "name": "Freeze", "buff": false, "color": Color(0.6, 0.92, 1.0), "desc": "Skips the next turn"},
}


# --- Species -------------------------------------------------------------------------
# Porcelain automata: each is glazed in its element's colour and mended with gold.
# Skill fields:
#   target: "enemy" | "all_enemies" | "all_allies"; skill index 2 is the Ultimate (100 energy)
#   mult: ATK multiplier per hit (0 = no damage); hits: number of hits
#   anim: "melee" | "projectile" | "cast" | "ultimate"
#   effects on each damaged target: debuff{status,turns,chance}, atb_reduce{amount,chance}
#   effects on the caster's side:   heal_allies{pct}, cleanse_allies, buff_allies{status,turns},
#                                   atb_boost_allies{amount}, buff_self{status,turns}
# passive ids are resolved in po_battle.gd.  leader: {stat, value} applied to the whole team.
const SPECIES := {
	"emberlynx": {
		"name": "焰釉猞猁", "en": "Ember Lynx", "element": Element.FIRE, "role": "输出",
		"base": {"hp": 4300, "atk": 840, "def": 400, "spd": 110, "crit_rate": 25, "crit_dmg": 70, "acc": 20, "res": 15},
		"leader": {"stat": "atk_pct", "value": 18},
		"passive": {"id": "molten_core", "name": "熔芯", "desc": "对带有【持续伤害】的敌人造成的伤害+25%。"},
		"skills": [
			{"name": "熔爪", "cd": 0, "target": "enemy", "mult": 3.6, "hits": 1, "anim": "melee",
				"desc": "赤红釉爪撕裂敌人，50%几率附加【持续伤害】2回合。",
				"effects": [{"type": "debuff", "status": "dot", "turns": 2, "chance": 50}]},
			{"name": "窑变三连", "cd": 3, "target": "enemy", "mult": 1.5, "hits": 3, "anim": "projectile",
				"desc": "射出三枚熔釉弹，每击35%几率附加【持续伤害】2回合。",
				"effects": [{"type": "debuff", "status": "dot", "turns": 2, "chance": 35}]},
			{"name": "千度烧成", "cd": 0, "target": "all_enemies", "mult": 3.1, "hits": 1, "anim": "ultimate",
				"desc": "【奥义】释放窑火，灼烧全体敌人，60%几率附加【持续伤害】2回合。",
				"effects": [{"type": "debuff", "status": "dot", "turns": 2, "chance": 60}]},
		],
	},
	"tidemoth": {
		"name": "潮光瓷蛾", "en": "Tide Moth", "element": Element.WATER, "role": "辅助",
		"base": {"hp": 5400, "atk": 600, "def": 520, "spd": 104, "crit_rate": 15, "crit_dmg": 50, "acc": 25, "res": 25},
		"leader": {"stat": "hp_pct", "value": 20},
		"passive": {"id": "moon_dew", "name": "月露", "desc": "回合开始时，为生命最低的队友恢复8%最大生命。"},
		"skills": [
			{"name": "潮汐鳞粉", "cd": 0, "target": "enemy", "mult": 3.2, "hits": 1, "anim": "projectile",
				"desc": "抖落潮汐鳞粉冲击敌人，并削减其20%攻击条。",
				"effects": [{"type": "atb_reduce", "amount": 20, "chance": 100}]},
			{"name": "青瓷甘霖", "cd": 3, "target": "all_allies", "mult": 0.0, "hits": 0, "anim": "cast",
				"desc": "为全体队友恢复22%最大生命，并清除所有减益效果。",
				"effects": [{"type": "heal_allies", "pct": 22}, {"type": "cleanse_allies"}]},
			{"name": "满月潮涌", "cd": 0, "target": "all_allies", "mult": 0.0, "hits": 0, "anim": "ultimate",
				"desc": "【奥义】引满月之潮：全体队友恢复15%生命、攻击条+30%、获得【防御强化】2回合。",
				"effects": [{"type": "heal_allies", "pct": 15}, {"type": "atb_boost_allies", "amount": 30},
					{"type": "buff_allies", "status": "def_up", "turns": 2}]},
		],
	},
	"chimeram": {
		"name": "风铃角羊", "en": "Chime Ram", "element": Element.WIND, "role": "控速",
		"base": {"hp": 4700, "atk": 680, "def": 470, "spd": 124, "crit_rate": 20, "crit_dmg": 55, "acc": 30, "res": 20},
		"leader": {"stat": "spd_pct", "value": 14},
		"passive": {"id": "tailwind", "name": "顺风", "desc": "行动后有20%几率立即获得额外回合。"},
		"skills": [
			{"name": "铃刃", "cd": 0, "target": "enemy", "mult": 1.8, "hits": 2, "anim": "projectile",
				"desc": "角上风铃化作两道音刃，命中后削减目标15%攻击条。",
				"effects": [{"type": "atb_reduce", "amount": 15, "chance": 100}]},
			{"name": "清音加速", "cd": 3, "target": "all_allies", "mult": 0.0, "hits": 0, "anim": "cast",
				"desc": "清越铃音：全体队友攻击条+25%，并获得【攻击强化】2回合。",
				"effects": [{"type": "atb_boost_allies", "amount": 25}, {"type": "buff_allies", "status": "atk_up", "turns": 2}]},
			{"name": "万铃风暴", "cd": 0, "target": "all_enemies", "mult": 2.6, "hits": 1, "anim": "ultimate",
				"desc": "【奥义】万铃齐鸣卷起风暴攻击全体敌人，削减其35%攻击条。",
				"effects": [{"type": "atb_reduce", "amount": 35, "chance": 100}]},
		],
	},
	"lumenowl": {
		"name": "月白鸮", "en": "Lumen Owl", "element": Element.LIGHT, "role": "治疗",
		"base": {"hp": 5000, "atk": 660, "def": 520, "spd": 106, "crit_rate": 15, "crit_dmg": 50, "acc": 20, "res": 35},
		"leader": {"stat": "res", "value": 25},
		"passive": {"id": "clear_glaze", "name": "净釉", "desc": "回合开始时，清除自身1个减益效果。"},
		"skills": [
			{"name": "星芒羽", "cd": 0, "target": "enemy", "mult": 3.3, "hits": 1, "anim": "projectile",
				"desc": "射出星芒之羽，50%几率附加【防御破坏】2回合。",
				"effects": [{"type": "debuff", "status": "def_break", "turns": 2, "chance": 50}]},
			{"name": "暖光修补", "cd": 4, "target": "all_allies", "mult": 0.0, "hits": 0, "anim": "cast",
				"desc": "以金缮之光修补全队：恢复25%最大生命，并赋予【免疫】1回合。",
				"effects": [{"type": "heal_allies", "pct": 25}, {"type": "buff_allies", "status": "immunity", "turns": 1}]},
			{"name": "黎明之瞳", "cd": 0, "target": "all_enemies", "mult": 2.5, "hits": 1, "anim": "ultimate",
				"desc": "【奥义】睁开黎明之瞳攻击全体敌人，随后清除全体队友减益并恢复15%生命。",
				"effects": [{"type": "cleanse_allies"}, {"type": "heal_allies", "pct": 15}]},
		],
	},
	"kilnbear": {
		"name": "窑心熊", "en": "Kiln Bear", "element": Element.FIRE, "role": "斗士",
		"base": {"hp": 5600, "atk": 750, "def": 560, "spd": 98, "crit_rate": 20, "crit_dmg": 60, "acc": 20, "res": 20},
		"leader": {"stat": "def_pct", "value": 20},
		"passive": {"id": "stoked", "name": "添柴", "desc": "每次受到攻击，攻击条+10%。"},
		"skills": [
			{"name": "陶锤", "cd": 0, "target": "enemy", "mult": 3.5, "hits": 1, "anim": "melee",
				"desc": "沉重一击，35%几率使目标【眩晕】1回合。",
				"effects": [{"type": "debuff", "status": "stun", "turns": 1, "chance": 35}]},
			{"name": "窑口喷焰", "cd": 3, "target": "all_enemies", "mult": 2.2, "hits": 1, "anim": "cast",
				"desc": "打开胸口的窑门喷焰，攻击全体敌人，50%几率附加【防御破坏】2回合。",
				"effects": [{"type": "debuff", "status": "def_break", "turns": 2, "chance": 50}]},
			{"name": "炉心过载", "cd": 0, "target": "enemy", "mult": 6.0, "hits": 1, "anim": "ultimate",
				"desc": "【奥义】炉心过载猛击单体，自身获得【攻击强化】2回合。",
				"effects": [{"type": "buff_self", "status": "atk_up", "turns": 2}]},
		],
	},
	"cobaltshell": {
		"name": "青花盾龟", "en": "Cobalt Shell", "element": Element.WATER, "role": "坦克",
		"base": {"hp": 6600, "atk": 540, "def": 760, "spd": 94, "crit_rate": 15, "crit_dmg": 50, "acc": 15, "res": 35},
		"leader": {"stat": "def_pct", "value": 22},
		"passive": {"id": "fired_shell", "name": "高温瓷甲", "desc": "生命高于50%时，受到的伤害-20%。"},
		"skills": [
			{"name": "冷釉撞击", "cd": 0, "target": "enemy", "mult": 3.1, "hits": 1, "anim": "melee",
				"desc": "用冰冷瓷甲撞击敌人，30%几率【冰冻】1回合。",
				"effects": [{"type": "debuff", "status": "freeze", "turns": 1, "chance": 30}]},
			{"name": "青花壁垒", "cd": 3, "target": "all_allies", "mult": 0.0, "hits": 0, "anim": "cast",
				"desc": "全体队友获得【防御强化】2回合与【免疫】1回合。",
				"effects": [{"type": "buff_allies", "status": "def_up", "turns": 2}, {"type": "buff_allies", "status": "immunity", "turns": 1}]},
			{"name": "深海回响", "cd": 0, "target": "all_enemies", "mult": 2.4, "hits": 1, "anim": "ultimate",
				"desc": "【奥义】深海回响震荡全体敌人，削减30%攻击条，60%几率【冰冻】1回合。",
				"effects": [{"type": "atb_reduce", "amount": 30, "chance": 100}, {"type": "debuff", "status": "freeze", "turns": 1, "chance": 60}]},
		],
	},
	"galemantis": {
		"name": "青瓷螳", "en": "Celadon Mantis", "element": Element.WIND, "role": "刺客",
		"base": {"hp": 4100, "atk": 880, "def": 390, "spd": 116, "crit_rate": 30, "crit_dmg": 75, "acc": 15, "res": 15},
		"leader": {"stat": "crit_rate", "value": 15},
		"passive": {"id": "hairline", "name": "发丝裂纹", "desc": "对生命低于50%的敌人伤害+40%。"},
		"skills": [
			{"name": "薄胎刃", "cd": 0, "target": "enemy", "mult": 3.6, "hits": 1, "anim": "melee",
				"desc": "薄如蛋壳的刃臂斩击，50%几率附加【防御破坏】2回合。",
				"effects": [{"type": "debuff", "status": "def_break", "turns": 2, "chance": 50}]},
			{"name": "双镰旋", "cd": 3, "target": "enemy", "mult": 2.4, "hits": 2, "anim": "melee",
				"desc": "双镰旋斩两次，并削减目标25%攻击条。",
				"effects": [{"type": "atb_reduce", "amount": 25, "chance": 100}]},
			{"name": "开片", "cd": 0, "target": "enemy", "mult": 6.6, "hits": 1, "anim": "ultimate",
				"desc": "【奥义】沿着裂纹一刀开片，对单体造成巨额伤害。",
				"effects": []},
		],
	},
	"tenmoku": {
		"name": "天目釉蛇", "en": "Tenmoku Serpent", "element": Element.DARK, "role": "法师",
		"base": {"hp": 4200, "atk": 820, "def": 420, "spd": 112, "crit_rate": 25, "crit_dmg": 65, "acc": 35, "res": 20},
		"leader": {"stat": "acc", "value": 25},
		"passive": {"id": "oil_spot", "name": "油滴斑", "desc": "击杀敌人时，立即获得额外回合。"},
		"skills": [
			{"name": "墨釉弹", "cd": 0, "target": "enemy", "mult": 3.3, "hits": 1, "anim": "projectile",
				"desc": "吐出漆黑釉弹，60%几率附加【持续伤害】2回合。",
				"effects": [{"type": "debuff", "status": "dot", "turns": 2, "chance": 60}]},
			{"name": "兔毫乱流", "cd": 3, "target": "all_enemies", "mult": 1.3, "hits": 2, "anim": "cast",
				"desc": "兔毫纹暗流两次攻击全体敌人，50%几率附加【持续伤害】2回合。",
				"effects": [{"type": "debuff", "status": "dot", "turns": 2, "chance": 50}]},
			{"name": "曜变", "cd": 0, "target": "enemy", "mult": 5.6, "hits": 1, "anim": "ultimate",
				"desc": "【奥义】曜变之光吞噬单体，80%几率【冰冻】1回合，全体队友攻击条+20%。",
				"effects": [{"type": "debuff", "status": "freeze", "turns": 1, "chance": 80}, {"type": "atb_boost_allies", "amount": 20}]},
		],
	},
}

const SPECIES_ORDER := ["emberlynx", "tidemoth", "chimeram", "lumenowl", "kilnbear", "cobaltshell", "galemantis", "tenmoku"]
const DEFAULT_TEAM := ["emberlynx", "tidemoth", "chimeram", "lumenowl"]


static func full_name(species_id: String) -> String:
	var s: Dictionary = SPECIES[species_id]
	return "%s·%s" % [ELEMENT_NAMES[s.element], s.name]


# --- Runes ------------------------------------------------------------------------
const RUNE_SETS := {
	"fatal": {"name": "猛攻", "pieces": 4, "stat": "atk_pct", "value": 35, "color": Color(1.0, 0.45, 0.35)},
	"energy": {"name": "活力", "pieces": 2, "stat": "hp_pct", "value": 15, "color": Color(0.45, 0.95, 0.5)},
	"swift": {"name": "迅速", "pieces": 4, "stat": "spd_pct", "value": 25, "color": Color(0.5, 0.85, 1.0)},
	"guard": {"name": "守护", "pieces": 2, "stat": "def_pct", "value": 15, "color": Color(0.7, 0.7, 1.0)},
	"blade": {"name": "刃", "pieces": 2, "stat": "crit_rate", "value": 12, "color": Color(1.0, 0.8, 0.3)},
}
const RUNE_SET_ORDER := ["fatal", "energy", "swift", "guard", "blade"]

## Possible main stats per slot (index 0..5 == slot 1..6).
const SLOT_MAIN_STATS := [
	["atk"],
	["spd", "atk_pct", "hp_pct", "def_pct"],
	["def"],
	["crit_rate", "crit_dmg", "hp_pct", "atk_pct"],
	["hp"],
	["atk_pct", "def_pct", "hp_pct", "acc", "res"],
]
const MAIN_STAT_VALUES := {
	"atk": [45, 80, 125], "def": [45, 80, 125], "hp": [650, 1150, 1800], "spd": [9, 15, 24],
	"atk_pct": [14, 24, 36], "def_pct": [14, 24, 36], "hp_pct": [14, 24, 36],
	"crit_rate": [10, 17, 26], "crit_dmg": [16, 28, 44], "acc": [12, 20, 32], "res": [12, 20, 32],
}
const GRADE_NAMES := ["稀有", "英雄", "传说"]
const GRADE_COLORS := [Color(0.35, 0.65, 1.0), Color(0.8, 0.4, 1.0), Color(1.0, 0.62, 0.15)]
const STAT_NAMES := {
	"hp": "生命", "atk": "攻击", "def": "防御", "spd": "速度", "crit_rate": "暴击率", "crit_dmg": "暴击伤害",
	"acc": "效果命中", "res": "效果抵抗", "hp_pct": "生命", "atk_pct": "攻击", "def_pct": "防御", "spd_pct": "速度",
}


static func stat_text(stat: String, value: float) -> String:
	var pct := stat.ends_with("_pct") or stat in ["crit_rate", "crit_dmg", "acc", "res"]
	return "%s +%d%s" % [STAT_NAMES.get(stat, stat), int(value), "%" if pct else ""]


static func rune_text(rune: Dictionary) -> String:
	var s: Dictionary = RUNE_SETS[rune.set]
	return "[%s] %d号位 %s  %s" % [s.name, int(rune.slot) + 1, GRADE_NAMES[int(rune.grade)], stat_text(rune.stat, rune.value)]


static func level_mult(level: int) -> float:
	return 1.0 + 0.035 * float(level - 1)


## Final stats from species base, level, equipped runes (+ set bonuses) and an
## optional leader skill {stat, value}.
static func compute_stats(species_id: String, level: int, runes: Array, leader: Dictionary = {}) -> Dictionary:
	var base: Dictionary = SPECIES[species_id].base
	var flat := {"hp": 0.0, "atk": 0.0, "def": 0.0, "spd": 0.0, "crit_rate": 0.0, "crit_dmg": 0.0, "acc": 0.0, "res": 0.0}
	var pct := {"hp": 0.0, "atk": 0.0, "def": 0.0, "spd": 0.0}
	var counts := {}
	for r in runes:
		if r == null or (r is Dictionary and r.is_empty()):
			continue
		_add_stat(flat, pct, r.stat, float(r.value))
		counts[r.set] = int(counts.get(r.set, 0)) + 1
	var active_sets: Array = []
	for set_id in counts:
		var info: Dictionary = RUNE_SETS[set_id]
		var times := floori(float(counts[set_id]) / float(info.pieces))
		for i in times:
			_add_stat(flat, pct, info.stat, float(info.value))
			active_sets.append(set_id)
	if not leader.is_empty():
		_add_stat(flat, pct, leader.stat, float(leader.value))
	var lm := level_mult(level)
	var out := {}
	for k in ["hp", "atk", "def"]:
		out[k] = roundf(float(base[k]) * lm * (1.0 + pct[k] / 100.0) + flat[k])
	out["spd"] = roundf(float(base.spd) * (1.0 + pct.spd / 100.0) + flat.spd)
	out["crit_rate"] = minf(100.0, float(base.crit_rate) + flat.crit_rate)
	out["crit_dmg"] = float(base.crit_dmg) + flat.crit_dmg
	out["acc"] = float(base.acc) + flat.acc
	out["res"] = minf(100.0, float(base.res) + flat.res)
	out["sets"] = active_sets
	return out


static func _add_stat(flat: Dictionary, pct: Dictionary, stat: String, value: float) -> void:
	if stat.ends_with("_pct"):
		var k := stat.trim_suffix("_pct")
		pct[k] = float(pct[k]) + value
	else:
		flat[stat] = float(flat[stat]) + value


static func make_rune(rng: RandomNumberGenerator, slot: int = -1, grade: int = 0, set_id: String = "") -> Dictionary:
	if slot < 0:
		slot = rng.randi_range(0, 5)
	if set_id == "":
		set_id = RUNE_SET_ORDER[rng.randi_range(0, RUNE_SET_ORDER.size() - 1)]
	var options: Array = SLOT_MAIN_STATS[slot]
	var stat: String = options[rng.randi_range(0, options.size() - 1)]
	return {"set": set_id, "slot": slot, "grade": grade, "stat": stat, "value": MAIN_STAT_VALUES[stat][grade]}


static func exp_to_next(level: int) -> int:
	return 80 + level * 30
