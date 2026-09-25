extends RefCounted
## Goldmend :: static game data (bilingual).
## Every player-facing text has a Chinese field (`name`, `desc`, ...) and an
## English twin (`name_en`, `desc_en`, ...). Read them through po_i18n.gd.
## No `class_name` anywhere in this project: scripts reference each other via
## `preload()` constants, so nothing leaks into the global class namespace.

enum Element { FIRE, WATER, WIND, LIGHT, DARK }

const ELEMENT_NAMES := ["火", "水", "风", "光", "暗"]
const ELEMENT_NAMES_EN := ["Fire", "Water", "Wind", "Light", "Dark"]
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
const ATB_PER_SPD := 0.07
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
const REACTIONS := {
	"wildfire": {"name": "焰暴", "name_en": "Firestorm",
		"desc": "本次伤害的40%溅射到其他所有敌人。", "desc_en": "40% of the hit splashes onto every other enemy."},
	"steam": {"name": "蒸腾", "name_en": "Steam Burst",
		"desc": "目标攻击条-40%。", "desc_en": "Target's Attack Bar -40%."},
	"frost": {"name": "冰封", "name_en": "Frostbind",
		"desc": "冰冻目标1回合（无视抵抗）。", "desc_en": "Freezes the target for 1 turn (ignores Resistance)."},
	"annihilate": {"name": "湮灭", "name_en": "Annihilation",
		"desc": "追加目标最大生命12%的伤害。", "desc_en": "Extra damage equal to 12% of the target's max HP."},
	"radiance": {"name": "辉光", "name_en": "Radiance",
		"desc": "攻击方全队恢复10%最大生命。", "desc_en": "Heals the attacker's team by 10% of max HP."},
	"corrode": {"name": "蚀裂", "name_en": "Corrosion",
		"desc": "防御破坏 + 持续伤害，2回合。", "desc_en": "Defense Break + Continuous Damage for 2 turns."},
}


## Reaction id for a Mark of element `a` hit by element `b`, or "" for none.
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
	"atk_up": {"label": "攻↑", "label_en": "ATK↑", "name": "攻击强化", "name_en": "Attack Up", "buff": true, "color": Color(1.0, 0.55, 0.25)},
	"def_up": {"label": "防↑", "label_en": "DEF↑", "name": "防御强化", "name_en": "Defense Up", "buff": true, "color": Color(0.35, 0.75, 1.0)},
	"immunity": {"label": "免", "label_en": "IMM", "name": "免疫", "name_en": "Immunity", "buff": true, "color": Color(1.0, 0.92, 0.55)},
	"def_break": {"label": "破", "label_en": "BRK", "name": "防御破坏", "name_en": "Defense Break", "buff": false, "color": Color(0.95, 0.3, 0.3)},
	"dot": {"label": "蚀", "label_en": "DOT", "name": "持续伤害", "name_en": "Continuous Dmg", "buff": false, "color": Color(0.85, 0.35, 0.9)},
	"stun": {"label": "晕", "label_en": "STN", "name": "眩晕", "name_en": "Stun", "buff": false, "color": Color(1.0, 0.85, 0.2)},
	"freeze": {"label": "冰", "label_en": "FRZ", "name": "冰冻", "name_en": "Freeze", "buff": false, "color": Color(0.6, 0.92, 1.0)},
}


# --- Species -------------------------------------------------------------------------
# Porcelain automata, each glazed in its element's colour and mended with gold.
# Skill fields:
#   target: "enemy" | "all_enemies" | "all_allies"; index 2 is the Ultimate (energy)
#   mult: ATK multiplier per hit (0 = no damage); hits: number of hits
#   anim: "melee" | "projectile" | "cast" | "ultimate"
#   effects on each damaged target: debuff{status,turns,chance}, atb_reduce{amount,chance}
#   effects on the caster's side:   heal_allies{pct}, cleanse_allies, buff_allies{status,turns},
#                                   atb_boost_allies{amount}, buff_self{status,turns}
const SPECIES := {
	"emberlynx": {
		"name": "焰釉猞猁", "name_en": "Ember Lynx", "element": Element.FIRE, "role": "输出", "role_en": "Striker",
		"base": {"hp": 4300, "atk": 840, "def": 400, "spd": 110, "crit_rate": 25, "crit_dmg": 70, "acc": 20, "res": 15},
		"leader": {"stat": "atk_pct", "value": 18},
		"passive": {"id": "molten_core", "name": "熔芯", "name_en": "Molten Core",
			"desc": "对带有【持续伤害】的敌人伤害+25%。", "desc_en": "+25% damage to enemies with Continuous Damage."},
		"skills": [
			{"name": "熔爪", "name_en": "Molten Claw", "cd": 0, "target": "enemy", "mult": 3.6, "hits": 1, "anim": "melee",
				"desc": "赤红釉爪撕裂敌人，50%几率附加【持续伤害】2回合。",
				"desc_en": "Rakes an enemy with red-hot claws. 50% chance to inflict Continuous Damage for 2 turns.",
				"effects": [{"type": "debuff", "status": "dot", "turns": 2, "chance": 50}]},
			{"name": "窑变三连", "name_en": "Kiln Triple", "cd": 3, "target": "enemy", "mult": 1.5, "hits": 3, "anim": "projectile",
				"desc": "射出三枚熔釉弹，每击35%几率附加【持续伤害】2回合。",
				"desc_en": "Fires three molten glaze bolts. Each has a 35% chance to inflict Continuous Damage.",
				"effects": [{"type": "debuff", "status": "dot", "turns": 2, "chance": 35}]},
			{"name": "千度烧成", "name_en": "Thousand-Degree Firing", "cd": 0, "target": "all_enemies", "mult": 3.1, "hits": 1, "anim": "ultimate",
				"desc": "【奥义】释放窑火灼烧全体敌人，60%几率附加【持续伤害】2回合。",
				"desc_en": "ULTIMATE: Unleashes kiln fire on all enemies. 60% chance to inflict Continuous Damage.",
				"effects": [{"type": "debuff", "status": "dot", "turns": 2, "chance": 60}]},
		],
	},
	"tidemoth": {
		"name": "潮光瓷蛾", "name_en": "Tide Moth", "element": Element.WATER, "role": "辅助", "role_en": "Support",
		"base": {"hp": 5400, "atk": 600, "def": 520, "spd": 104, "crit_rate": 15, "crit_dmg": 50, "acc": 25, "res": 25},
		"leader": {"stat": "hp_pct", "value": 20},
		"passive": {"id": "moon_dew", "name": "月露", "name_en": "Moon Dew",
			"desc": "回合开始时，为生命最低的队友恢复8%最大生命。", "desc_en": "At turn start, heals the lowest-HP ally for 8% max HP."},
		"skills": [
			{"name": "潮汐鳞粉", "name_en": "Tidal Dust", "cd": 0, "target": "enemy", "mult": 3.2, "hits": 1, "anim": "projectile",
				"desc": "抖落潮汐鳞粉冲击敌人，并削减其20%攻击条。", "desc_en": "Showers an enemy with tidal scales and cuts its Attack Bar by 20%.",
				"effects": [{"type": "atb_reduce", "amount": 20, "chance": 100}]},
			{"name": "青瓷甘霖", "name_en": "Celadon Rain", "cd": 3, "target": "all_allies", "mult": 0.0, "hits": 0, "anim": "cast",
				"desc": "为全体队友恢复22%最大生命，并清除所有减益。", "desc_en": "Heals all allies for 22% max HP and removes all harmful effects.",
				"effects": [{"type": "heal_allies", "pct": 22}, {"type": "cleanse_allies"}]},
			{"name": "满月潮涌", "name_en": "Full-Moon Tide", "cd": 0, "target": "all_allies", "mult": 0.0, "hits": 0, "anim": "ultimate",
				"desc": "【奥义】全体队友恢复15%生命、攻击条+30%、获得【防御强化】2回合。",
				"desc_en": "ULTIMATE: All allies heal 15% HP, gain 30% Attack Bar and Defense Up for 2 turns.",
				"effects": [{"type": "heal_allies", "pct": 15}, {"type": "atb_boost_allies", "amount": 30},
					{"type": "buff_allies", "status": "def_up", "turns": 2}]},
		],
	},
	"chimeram": {
		"name": "风铃角羊", "name_en": "Chime Ram", "element": Element.WIND, "role": "控速", "role_en": "Tempo",
		"base": {"hp": 4700, "atk": 680, "def": 470, "spd": 124, "crit_rate": 20, "crit_dmg": 55, "acc": 30, "res": 20},
		"leader": {"stat": "spd_pct", "value": 14},
		"passive": {"id": "tailwind", "name": "顺风", "name_en": "Tailwind",
			"desc": "行动后有20%几率立即获得额外回合。", "desc_en": "20% chance to take an extra turn after acting."},
		"skills": [
			{"name": "铃刃", "name_en": "Chime Blades", "cd": 0, "target": "enemy", "mult": 1.8, "hits": 2, "anim": "projectile",
				"desc": "两道音刃连斩，命中后削减目标15%攻击条。", "desc_en": "Two ringing blades strike and cut the target's Attack Bar by 15%.",
				"effects": [{"type": "atb_reduce", "amount": 15, "chance": 100}]},
			{"name": "清音加速", "name_en": "Clear Note", "cd": 3, "target": "all_allies", "mult": 0.0, "hits": 0, "anim": "cast",
				"desc": "全体队友攻击条+25%，并获得【攻击强化】2回合。", "desc_en": "All allies gain 25% Attack Bar and Attack Up for 2 turns.",
				"effects": [{"type": "atb_boost_allies", "amount": 25}, {"type": "buff_allies", "status": "atk_up", "turns": 2}]},
			{"name": "万铃风暴", "name_en": "Ten Thousand Bells", "cd": 0, "target": "all_enemies", "mult": 2.6, "hits": 1, "anim": "ultimate",
				"desc": "【奥义】万铃齐鸣卷起风暴攻击全体敌人，削减其35%攻击条。",
				"desc_en": "ULTIMATE: A storm of bells hits all enemies and cuts their Attack Bar by 35%.",
				"effects": [{"type": "atb_reduce", "amount": 35, "chance": 100}]},
		],
	},
	"lumenowl": {
		"name": "月白鸮", "name_en": "Lumen Owl", "element": Element.LIGHT, "role": "治疗", "role_en": "Healer",
		"base": {"hp": 5000, "atk": 660, "def": 520, "spd": 106, "crit_rate": 15, "crit_dmg": 50, "acc": 20, "res": 35},
		"leader": {"stat": "res", "value": 25},
		"passive": {"id": "clear_glaze", "name": "净釉", "name_en": "Clear Glaze",
			"desc": "回合开始时，清除自身1个减益效果。", "desc_en": "At turn start, removes one harmful effect from itself."},
		"skills": [
			{"name": "星芒羽", "name_en": "Starlight Quill", "cd": 0, "target": "enemy", "mult": 3.3, "hits": 1, "anim": "projectile",
				"desc": "射出星芒之羽，50%几率附加【防御破坏】2回合。", "desc_en": "Shoots a star-quill. 50% chance to Break Defense for 2 turns.",
				"effects": [{"type": "debuff", "status": "def_break", "turns": 2, "chance": 50}]},
			{"name": "暖光修补", "name_en": "Warm Mending", "cd": 4, "target": "all_allies", "mult": 0.0, "hits": 0, "anim": "cast",
				"desc": "以金缮之光修补全队：恢复25%最大生命，并赋予【免疫】1回合。",
				"desc_en": "Mends the team with golden light: heals 25% max HP and grants Immunity for 1 turn.",
				"effects": [{"type": "heal_allies", "pct": 25}, {"type": "buff_allies", "status": "immunity", "turns": 1}]},
			{"name": "黎明之瞳", "name_en": "Eye of Dawn", "cd": 0, "target": "all_enemies", "mult": 2.5, "hits": 1, "anim": "ultimate",
				"desc": "【奥义】攻击全体敌人，随后清除全体队友减益并恢复15%生命。",
				"desc_en": "ULTIMATE: Strikes all enemies, then cleanses all allies and heals them 15%.",
				"effects": [{"type": "cleanse_allies"}, {"type": "heal_allies", "pct": 15}]},
		],
	},
	"kilnbear": {
		"name": "窑心熊", "name_en": "Kiln Bear", "element": Element.FIRE, "role": "斗士", "role_en": "Bruiser",
		"base": {"hp": 5600, "atk": 750, "def": 560, "spd": 98, "crit_rate": 20, "crit_dmg": 60, "acc": 20, "res": 20},
		"leader": {"stat": "def_pct", "value": 20},
		"passive": {"id": "stoked", "name": "添柴", "name_en": "Stoked",
			"desc": "每次受到攻击，攻击条+10%。", "desc_en": "Gains 10% Attack Bar whenever it is hit."},
		"skills": [
			{"name": "陶锤", "name_en": "Clay Hammer", "cd": 0, "target": "enemy", "mult": 3.5, "hits": 1, "anim": "melee",
				"desc": "沉重一击，35%几率使目标【眩晕】1回合。", "desc_en": "A crushing blow. 35% chance to Stun for 1 turn.",
				"effects": [{"type": "debuff", "status": "stun", "turns": 1, "chance": 35}]},
			{"name": "窑口喷焰", "name_en": "Furnace Breath", "cd": 3, "target": "all_enemies", "mult": 2.2, "hits": 1, "anim": "cast",
				"desc": "打开胸口窑门喷焰攻击全体，50%几率【防御破坏】2回合。",
				"desc_en": "Opens the kiln in its chest to burn all enemies. 50% chance to Break Defense.",
				"effects": [{"type": "debuff", "status": "def_break", "turns": 2, "chance": 50}]},
			{"name": "炉心过载", "name_en": "Core Overload", "cd": 0, "target": "enemy", "mult": 6.0, "hits": 1, "anim": "ultimate",
				"desc": "【奥义】炉心过载猛击单体，自身获得【攻击强化】2回合。",
				"desc_en": "ULTIMATE: An overloaded blow on one enemy; gains Attack Up for 2 turns.",
				"effects": [{"type": "buff_self", "status": "atk_up", "turns": 2}]},
		],
	},
	"cobaltshell": {
		"name": "青花盾龟", "name_en": "Cobalt Shell", "element": Element.WATER, "role": "坦克", "role_en": "Tank",
		"base": {"hp": 6600, "atk": 540, "def": 760, "spd": 94, "crit_rate": 15, "crit_dmg": 50, "acc": 15, "res": 35},
		"leader": {"stat": "def_pct", "value": 22},
		"passive": {"id": "fired_shell", "name": "高温瓷甲", "name_en": "High-Fired Shell",
			"desc": "生命高于50%时，受到的伤害-20%。", "desc_en": "Takes 20% less damage while above 50% HP."},
		"skills": [
			{"name": "冷釉撞击", "name_en": "Cold Glaze Ram", "cd": 0, "target": "enemy", "mult": 3.1, "hits": 1, "anim": "melee",
				"desc": "用冰冷瓷甲撞击敌人，30%几率【冰冻】1回合。", "desc_en": "Rams with an icy shell. 30% chance to Freeze for 1 turn.",
				"effects": [{"type": "debuff", "status": "freeze", "turns": 1, "chance": 30}]},
			{"name": "青花壁垒", "name_en": "Blue-and-White Wall", "cd": 3, "target": "all_allies", "mult": 0.0, "hits": 0, "anim": "cast",
				"desc": "全体队友获得【防御强化】2回合与【免疫】1回合。", "desc_en": "All allies gain Defense Up (2 turns) and Immunity (1 turn).",
				"effects": [{"type": "buff_allies", "status": "def_up", "turns": 2}, {"type": "buff_allies", "status": "immunity", "turns": 1}]},
			{"name": "深海回响", "name_en": "Abyssal Echo", "cd": 0, "target": "all_enemies", "mult": 2.4, "hits": 1, "anim": "ultimate",
				"desc": "【奥义】震荡全体敌人，削减30%攻击条，60%几率【冰冻】1回合。",
				"desc_en": "ULTIMATE: Shakes all enemies, cuts Attack Bar by 30%, 60% chance to Freeze.",
				"effects": [{"type": "atb_reduce", "amount": 30, "chance": 100}, {"type": "debuff", "status": "freeze", "turns": 1, "chance": 60}]},
		],
	},
	"galemantis": {
		"name": "青瓷螳", "name_en": "Celadon Mantis", "element": Element.WIND, "role": "刺客", "role_en": "Assassin",
		"base": {"hp": 4100, "atk": 880, "def": 390, "spd": 116, "crit_rate": 30, "crit_dmg": 75, "acc": 15, "res": 15},
		"leader": {"stat": "crit_rate", "value": 15},
		"passive": {"id": "hairline", "name": "发丝裂纹", "name_en": "Hairline",
			"desc": "对生命低于50%的敌人伤害+40%。", "desc_en": "+40% damage to enemies below 50% HP."},
		"skills": [
			{"name": "薄胎刃", "name_en": "Eggshell Blade", "cd": 0, "target": "enemy", "mult": 3.6, "hits": 1, "anim": "melee",
				"desc": "薄如蛋壳的刃臂斩击，50%几率【防御破坏】2回合。", "desc_en": "An eggshell-thin blade. 50% chance to Break Defense for 2 turns.",
				"effects": [{"type": "debuff", "status": "def_break", "turns": 2, "chance": 50}]},
			{"name": "双镰旋", "name_en": "Twin Sickles", "cd": 3, "target": "enemy", "mult": 2.4, "hits": 2, "anim": "melee",
				"desc": "双镰旋斩两次，并削减目标25%攻击条。", "desc_en": "Spins twice and cuts the target's Attack Bar by 25%.",
				"effects": [{"type": "atb_reduce", "amount": 25, "chance": 100}]},
			{"name": "开片", "name_en": "Crackle Cut", "cd": 0, "target": "enemy", "mult": 6.6, "hits": 1, "anim": "ultimate",
				"desc": "【奥义】沿着裂纹一刀开片，对单体造成巨额伤害。", "desc_en": "ULTIMATE: One cut along the crackle. Massive single-target damage.",
				"effects": []},
		],
	},
	"tenmoku": {
		"name": "天目釉蛇", "name_en": "Tenmoku Serpent", "element": Element.DARK, "role": "法师", "role_en": "Caster",
		"base": {"hp": 4200, "atk": 820, "def": 420, "spd": 112, "crit_rate": 25, "crit_dmg": 65, "acc": 35, "res": 20},
		"leader": {"stat": "acc", "value": 25},
		"passive": {"id": "oil_spot", "name": "油滴斑", "name_en": "Oil Spot",
			"desc": "击杀敌人时，立即获得额外回合。", "desc_en": "Takes an extra turn after defeating an enemy."},
		"skills": [
			{"name": "墨釉弹", "name_en": "Ink Glaze Shot", "cd": 0, "target": "enemy", "mult": 3.3, "hits": 1, "anim": "projectile",
				"desc": "吐出漆黑釉弹，60%几率【持续伤害】2回合。", "desc_en": "Spits black glaze. 60% chance to inflict Continuous Damage.",
				"effects": [{"type": "debuff", "status": "dot", "turns": 2, "chance": 60}]},
			{"name": "兔毫乱流", "name_en": "Hare's-Fur Surge", "cd": 3, "target": "all_enemies", "mult": 1.3, "hits": 2, "anim": "cast",
				"desc": "暗流两次攻击全体敌人，50%几率【持续伤害】2回合。", "desc_en": "A dark surge hits all enemies twice. 50% chance of Continuous Damage.",
				"effects": [{"type": "debuff", "status": "dot", "turns": 2, "chance": 50}]},
			{"name": "曜变", "name_en": "Yohen", "cd": 0, "target": "enemy", "mult": 5.6, "hits": 1, "anim": "ultimate",
				"desc": "【奥义】曜变之光吞噬单体，80%几率【冰冻】1回合，全体队友攻击条+20%。",
				"desc_en": "ULTIMATE: Devours one enemy in iridescent light (80% Freeze); allies gain 20% Attack Bar.",
				"effects": [{"type": "debuff", "status": "freeze", "turns": 1, "chance": 80}, {"type": "atb_boost_allies", "amount": 20}]},
		],
	},
}

const SPECIES_ORDER := ["emberlynx", "tidemoth", "chimeram", "lumenowl", "kilnbear", "cobaltshell", "galemantis", "tenmoku"]

## Starting trios offered at the beginning of a run.
const STARTERS := [
	{"name": "焰与潮", "name_en": "Ember & Tide", "team": ["emberlynx", "tidemoth", "chimeram"],
		"desc": "火+风焰暴，水来续航。", "desc_en": "Fire + Wind Firestorms, Water to sustain."},
	{"name": "金缮守护", "name_en": "Golden Guard", "team": ["cobaltshell", "lumenowl", "kilnbear"],
		"desc": "硬朗耐打，慢慢磨。", "desc_en": "Sturdy and patient. Outlast them."},
	{"name": "暗刃疾风", "name_en": "Shadow Gale", "team": ["galemantis", "tenmoku", "chimeram"],
		"desc": "高速斩杀，击杀连动。", "desc_en": "Fast executions that chain off kills."},
]


# --- Boss ----------------------------------------------------------------------------
const BOSS := {
	"name": "无缮之王", "name_en": "The Unmended", "element": Element.DARK, "role": "首领", "role_en": "Boss",
	"base": {"hp": 5200, "atk": 760, "def": 520, "spd": 100, "crit_rate": 20, "crit_dmg": 60, "acc": 35, "res": 40},
	"leader": {},
	"passive": {"id": "unmended", "name": "拒绝修补", "name_en": "Refuses the Gold",
		"desc": "场上每有单位碎裂，攻击条+25%并恢复6%生命。生命低于50%时狂怒，攻击+30%。",
		"desc_en": "Whenever anything shatters, gains 25% Attack Bar and heals 6%. Enrages below 50% HP (+30% ATK)."},
	"skills": [
		{"name": "裂口", "name_en": "Jagged Maw", "cd": 0, "target": "enemy", "mult": 3.8, "hits": 1, "anim": "melee",
			"desc": "用碎裂的瓶口撕咬，60%几率【防御破坏】2回合。", "desc_en": "Bites with its broken rim. 60% chance to Break Defense.",
			"effects": [{"type": "debuff", "status": "def_break", "turns": 2, "chance": 60}]},
		{"name": "碎瓷风暴", "name_en": "Shard Storm", "cd": 3, "target": "all_enemies", "mult": 1.4, "hits": 2, "anim": "cast",
			"desc": "甩出身上的碎瓷两次攻击全体，50%几率【持续伤害】。", "desc_en": "Hurls its shards at everyone twice. 50% Continuous Damage.",
			"effects": [{"type": "debuff", "status": "dot", "turns": 2, "chance": 50}]},
		{"name": "万片归墟", "name_en": "Ten Thousand Fragments", "cd": 0, "target": "all_enemies", "mult": 3.0, "hits": 1, "anim": "ultimate",
			"desc": "【奥义】所有碎片同时坠落，攻击全体并削减40%攻击条。", "desc_en": "ULTIMATE: Every fragment falls at once. Hits all and cuts Attack Bar by 40%.",
			"effects": [{"type": "atb_reduce", "amount": 40, "chance": 100}]},
	],
}


static func species_info(sid: String) -> Dictionary:
	return BOSS if sid == "boss" else SPECIES[sid]


# --- Scars (earned when a shattered creature is mended) ---------------------------------
const SCARS := {
	"res_0": {"name": "耐火纹", "name_en": "Fireproof Seam", "desc": "受到火属性伤害-30%", "desc_en": "-30% damage from Fire"},
	"res_1": {"name": "耐水纹", "name_en": "Waterproof Seam", "desc": "受到水属性伤害-30%", "desc_en": "-30% damage from Water"},
	"res_2": {"name": "耐风纹", "name_en": "Windproof Seam", "desc": "受到风属性伤害-30%", "desc_en": "-30% damage from Wind"},
	"res_3": {"name": "耐光纹", "name_en": "Lightproof Seam", "desc": "受到光属性伤害-30%", "desc_en": "-30% damage from Light"},
	"res_4": {"name": "耐暗纹", "name_en": "Darkproof Seam", "desc": "受到暗属性伤害-30%", "desc_en": "-30% damage from Dark"},
	"crit_proof": {"name": "韧胎", "name_en": "Tough Body", "desc": "不会受到暴击", "desc_en": "Cannot be critically hit"},
	"dot_proof": {"name": "封釉", "name_en": "Sealed Glaze", "desc": "免疫持续伤害", "desc_en": "Immune to Continuous Damage"},
	"cc_proof": {"name": "定心", "name_en": "Steady Core", "desc": "免疫眩晕与冰冻", "desc_en": "Immune to Stun and Freeze"},
}
const MEND_BONUS := 0.12      # +12% HP/ATK/DEF per gold seam
const MAX_MENDS := 3          # the 4th shatter turns a creature to dust


## Scar earned from how the creature broke.
static func scar_for(cause: Dictionary) -> String:
	if cause.get("dot", false):
		return "dot_proof"
	if cause.get("cc", false):
		return "cc_proof"
	if cause.get("crit", false):
		return "crit_proof"
	return "res_%d" % int(cause.get("element", 0))


# --- Glaze shards (run relics) -----------------------------------------------------------
const RELICS := {
	"steam_engine": {"name": "蒸汽回路", "name_en": "Steam Engine", "rarity": 1,
		"desc": "【蒸腾】裂变同时触发【焰暴】溅射。", "desc_en": "Steam Burst also triggers a Firestorm splash."},
	"chain_kiln": {"name": "连锁窑变", "name_en": "Chain Firing", "rarity": 1,
		"desc": "每次触发元素裂变，施法者灵力+25。", "desc_en": "Every reaction gives the attacker +25 energy."},
	"shard_edge": {"name": "碎瓷锋", "name_en": "Shard Edge", "rarity": 1,
		"desc": "我方有单位碎裂时，其余队友攻击条+30%并获得【攻击强化】2回合。",
		"desc_en": "When an ally shatters, the others gain 30% Attack Bar and Attack Up for 2 turns."},
	"golden_heart": {"name": "金缮之心", "name_en": "Golden Heart", "rarity": 2,
		"desc": "我方单位每有一道金缝，伤害+10%。", "desc_en": "Allies deal +10% damage per gold seam."},
	"first_glaze": {"name": "先手釉", "name_en": "First Glaze", "rarity": 0,
		"desc": "战斗开始时，我方攻击条+40%。", "desc_en": "Allies start each battle with 40% Attack Bar."},
	"resonance": {"name": "裂纹共鸣", "name_en": "Crack Resonance", "rarity": 0,
		"desc": "攻击带印记的敌人，伤害+20%。", "desc_en": "+20% damage against marked enemies."},
	"double_seal": {"name": "双印", "name_en": "Double Seal", "rarity": 2,
		"desc": "触发裂变后，目标立刻被打上攻击者的印记，可以连锁裂变。",
		"desc_en": "After a reaction, the target keeps the attacker's Mark, allowing chain reactions."},
	"ember_glaze": {"name": "窑火余烬", "name_en": "Kiln Embers", "rarity": 0,
		"desc": "【持续伤害】每回合8%（原5%）。", "desc_en": "Continuous Damage deals 8% per turn (was 5%)."},
	"thick_body": {"name": "厚胎", "name_en": "Thick Body", "rarity": 0,
		"desc": "我方最大生命+20%。", "desc_en": "Allies have +20% max HP."},
	"gold_dust": {"name": "金粉瓶", "name_en": "Gold Dust Vial", "rarity": 1,
		"desc": "每场战斗第一个碎裂的队友，立即以30%生命重组。",
		"desc_en": "The first ally to shatter each battle reassembles at 30% HP."},
	"blue_guard": {"name": "青花护", "name_en": "Cobalt Ward", "rarity": 0,
		"desc": "战斗开始时，我方获得【防御强化】2回合。", "desc_en": "Allies start each battle with Defense Up (2 turns)."},
	"quick_fire": {"name": "急火", "name_en": "Quick Fire", "rarity": 1,
		"desc": "奥义只需70灵力。", "desc_en": "Ultimates need only 70 energy."},
	"ice_crackle": {"name": "冰裂纹", "name_en": "Ice Crackle", "rarity": 1,
		"desc": "被冰冻的敌人受到的伤害+50%。", "desc_en": "Frozen enemies take +50% damage."},
	"greedy_gold": {"name": "贪金", "name_en": "Greedy Gold", "rarity": 0,
		"desc": "战斗获得的金子+40%。", "desc_en": "+40% gold from battles."},
	"crit_glaze": {"name": "釉光", "name_en": "Glaze Gleam", "rarity": 0,
		"desc": "我方暴击率+15%。", "desc_en": "Allies gain +15% crit rate."},
}
const RARITY_COLORS := [Color(0.55, 0.8, 1.0), Color(0.85, 0.55, 1.0), Color(1.0, 0.72, 0.25)]


# --- Stats ------------------------------------------------------------------------------
static func stat_text(stat: String, value: float) -> String:
	var zh := {"hp_pct": "生命", "atk_pct": "攻击", "def_pct": "防御", "spd_pct": "速度", "crit_rate": "暴击率", "res": "效果抵抗", "acc": "效果命中"}
	var en := {"hp_pct": "HP", "atk_pct": "ATK", "def_pct": "DEF", "spd_pct": "SPD", "crit_rate": "Crit Rate", "res": "Resistance", "acc": "Accuracy"}
	var names: Dictionary = en if preload("po_i18n.gd").en() else zh
	return "%s +%d%%" % [names.get(stat, stat), int(value)]



static func level_mult(level: int) -> float:
	return 1.0 + 0.045 * float(level - 1)


static func enemy_level(row: int, elite: bool) -> int:
	return 1 + row + (1 if elite else 0)


static func compute_stats(species_id: String, level: int, mends: int = 0, hp_mult: float = 1.0, leader: Dictionary = {}) -> Dictionary:
	var base: Dictionary = species_info(species_id).base
	var lm := level_mult(level) * (1.0 + MEND_BONUS * mends)
	var pct := {"hp": 0.0, "atk": 0.0, "def": 0.0, "spd": 0.0}
	var flat := {"crit_rate": 0.0, "acc": 0.0, "res": 0.0}
	if not leader.is_empty():
		var st: String = leader.stat
		if st.ends_with("_pct"):
			pct[st.trim_suffix("_pct")] += float(leader.value)
		elif flat.has(st):
			flat[st] += float(leader.value)
	var out := {}
	for k in ["hp", "atk", "def"]:
		out[k] = roundf(float(base[k]) * lm * (1.0 + pct[k] / 100.0))
	out.hp = roundf(out.hp * hp_mult)
	out["spd"] = roundf(float(base.spd) * (1.0 + pct.spd / 100.0))
	out["crit_rate"] = minf(100.0, float(base.crit_rate) + flat.crit_rate)
	out["crit_dmg"] = float(base.crit_dmg)
	out["acc"] = float(base.acc) + flat.acc
	out["res"] = minf(100.0, float(base.res) + flat.res)
	return out


# --- Map & events ------------------------------------------------------------------------
const NODE_TYPES := {
	"start": {"glyph": "启", "glyph_en": "S", "name": "启程", "name_en": "Start", "color": Color(0.95, 0.9, 0.8)},
	"battle": {"glyph": "战", "glyph_en": "F", "name": "战斗", "name_en": "Battle", "color": Color(0.85, 0.3, 0.25)},
	"elite": {"glyph": "精", "glyph_en": "E", "name": "精英", "name_en": "Elite", "color": Color(0.75, 0.2, 0.55)},
	"kiln": {"glyph": "窑", "glyph_en": "K", "name": "窑炉·招募", "name_en": "Kiln · Recruit", "color": Color(1.0, 0.55, 0.2)},
	"mend": {"glyph": "缮", "glyph_en": "M", "name": "金缮坊", "name_en": "Mending Hall", "color": Color(1.0, 0.78, 0.3)},
	"shop": {"glyph": "市", "glyph_en": "$", "name": "釉片商店", "name_en": "Glaze Shop", "color": Color(0.3, 0.7, 0.9)},
	"event": {"glyph": "奇", "glyph_en": "?", "name": "奇遇", "name_en": "Encounter", "color": Color(0.5, 0.85, 0.6)},
	"boss": {"glyph": "王", "glyph_en": "B", "name": "无缮之王", "name_en": "The Unmended", "color": Color(0.1, 0.05, 0.1)},
}

const EVENTS := [
	{"id": "stranger", "title": "碎在路边的陌生瓷偶", "title_en": "A Stranger in Pieces",
		"text": "一只陌生的瓷偶碎在星轨边上，碎片还在微微发光。它的眼睛看着你。",
		"text_en": "An unfamiliar figure lies shattered by the path. Its pieces still glow faintly. Its eyes follow you.",
		"options": [
			{"text": "花 35 金修好它，让它加入", "text_en": "Spend 35 gold to mend it and let it join", "act": "recruit_paid"},
			{"text": "把碎片卖给路过的商人（+30 金）", "text_en": "Sell the shards to a passing trader (+30 gold)", "act": "sell"},
			{"text": "默默离开", "text_en": "Leave quietly", "act": "leave"}]},
	{"id": "altar", "title": "窑神的祭坛", "title_en": "Altar of the Kiln God",
		"text": "一座熄灭的窑炉，炉口刻着：「以身饲火，火必还之。」",
		"text_en": "A cold kiln. Carved above the mouth: \"Feed the fire yourself, and the fire repays you.\"",
		"options": [
			{"text": "全队失去25%当前生命，换一块随机釉片", "text_en": "Whole team loses 25% current HP; gain a random glaze shard", "act": "altar"},
			{"text": "献上 40 金，全队恢复满生命", "text_en": "Offer 40 gold; the whole team heals to full", "act": "altar_heal"},
			{"text": "离开", "text_en": "Leave", "act": "leave"}]},
	{"id": "stars", "title": "倒悬的星图", "title_en": "The Upside-Down Star Chart",
		"text": "盘面上的青花云纹缓缓流动，拼出一句话：「裂痕是光进来的地方。」",
		"text_en": "The cobalt clouds on the plate drift into words: \"The crack is where the light gets in.\"",
		"options": [
			{"text": "凝视裂痕（金缝最多的瓷偶升 2 级）", "text_en": "Gaze into the crack (the most-mended figure gains 2 levels)", "act": "gaze"},
			{"text": "收集散落的金粉（+45 金）", "text_en": "Gather the spilled gold dust (+45 gold)", "act": "gold"}]},
]
