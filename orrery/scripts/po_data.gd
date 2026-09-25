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


# --- Vessel Spirits (器灵) -------------------------------------------------------------
# Every figure is a real, museum-famous piece of porcelain that has come alive,
# drawn as a cartoon. `origin` records where the real piece comes from so the
# roster can grow to other countries (Delft, Meissen, Imari, Iznik ...).
# Skill fields:
#   target: "enemy" | "all_enemies" | "all_allies"; index 2 is the Ultimate (energy)
#   mult: ATK multiplier per hit (0 = no damage); hits: number of hits
#   anim: "melee" | "projectile" | "cast" | "ultimate"
#   effects on each damaged target: debuff{status,turns,chance}, atb_reduce{amount,chance}
#   effects on the caster's side:   heal_allies{pct}, cleanse_allies, buff_allies{status,turns},
#                                   atb_boost_allies{amount}, buff_self{status,turns}
const SPECIES := {
	"chickencup": {
		"name": "鸡缸杯", "name_en": "Chicken Cup", "element": Element.FIRE, "role": "输出", "role_en": "Striker",
		"origin": {"country": "中国", "country_en": "China", "era": "明·成化", "era_en": "Ming · Chenghua",
			"piece": "斗彩鸡缸杯", "piece_en": "Doucai 'Chicken Cup'"},
		"lore": "杯身上画的那只公鸡跳了出来，把整只杯子顶在身上。脾气火爆，天不亮就要打鸣。",
		"lore_en": "The rooster painted on the cup jumped out and wears the whole cup as armour. Hot-tempered; crows before dawn.",
		"base": {"hp": 4300, "atk": 840, "def": 400, "spd": 110, "crit_rate": 25, "crit_dmg": 70, "acc": 20, "res": 15},
		"leader": {"stat": "atk_pct", "value": 18},
		"passive": {"id": "molten_core", "name": "斗性", "name_en": "Fighting Spirit",
			"desc": "对带有【持续伤害】的敌人伤害+25%。", "desc_en": "+25% damage to enemies with Continuous Damage."},
		"skills": [
			{"name": "啄火", "name_en": "Fire Peck", "cd": 0, "target": "enemy", "mult": 3.6, "hits": 1, "anim": "melee",
				"desc": "带火的一啄，50%几率附加【持续伤害】2回合。", "desc_en": "A burning peck. 50% chance to inflict Continuous Damage for 2 turns.",
				"effects": [{"type": "debuff", "status": "dot", "turns": 2, "chance": 50}]},
			{"name": "斗彩三连", "name_en": "Doucai Flurry", "cd": 3, "target": "enemy", "mult": 1.5, "hits": 3, "anim": "projectile",
				"desc": "甩出三片彩釉翎羽，每击35%几率附加【持续伤害】。", "desc_en": "Flings three enamel feathers; each has a 35% chance of Continuous Damage.",
				"effects": [{"type": "debuff", "status": "dot", "turns": 2, "chance": 35}]},
			{"name": "金鸡报晓", "name_en": "Dawn Crow", "cd": 0, "target": "all_enemies", "mult": 3.1, "hits": 1, "anim": "ultimate",
				"desc": "【奥义】一声啼鸣烧红天际，攻击全体敌人，60%几率【持续伤害】。",
				"desc_en": "ULTIMATE: A crow that sets the sky ablaze. Hits all enemies; 60% Continuous Damage.",
				"effects": [{"type": "debuff", "status": "dot", "turns": 2, "chance": 60}]},
		],
	},
	"rulotus": {
		"name": "汝窑莲碗", "name_en": "Ru Lotus Bowl", "element": Element.WATER, "role": "辅助", "role_en": "Support",
		"origin": {"country": "中国", "country_en": "China", "era": "北宋", "era_en": "Northern Song",
			"piece": "汝窑天青釉莲花式温碗", "piece_en": "Ru ware sky-blue lotus warming bowl"},
		"lore": "「雨过天青云破处」——它的釉色就是那片天。身上的冰裂纹一笑就会轻轻作响。",
		"lore_en": "\"The blue of the sky after rain\" - that is its glaze. Its ice-crackle chimes softly when it laughs.",
		"base": {"hp": 5400, "atk": 600, "def": 520, "spd": 104, "crit_rate": 15, "crit_dmg": 50, "acc": 25, "res": 25},
		"leader": {"stat": "hp_pct", "value": 20},
		"passive": {"id": "moon_dew", "name": "雨过天青", "name_en": "After the Rain",
			"desc": "回合开始时，为生命最低的队友恢复8%最大生命。", "desc_en": "At turn start, heals the lowest-HP ally for 8% max HP."},
		"skills": [
			{"name": "碗中涟漪", "name_en": "Ripple", "cd": 0, "target": "enemy", "mult": 3.2, "hits": 1, "anim": "projectile",
				"desc": "泼出一道碗中之水，削减目标20%攻击条。", "desc_en": "Splashes water from its bowl and cuts the target's Attack Bar by 20%.",
				"effects": [{"type": "atb_reduce", "amount": 20, "chance": 100}]},
			{"name": "温碗", "name_en": "Warming Bowl", "cd": 3, "target": "all_allies", "mult": 0.0, "hits": 0, "anim": "cast",
				"desc": "为全体队友恢复22%最大生命，并清除所有减益。", "desc_en": "Heals all allies for 22% max HP and removes all harmful effects.",
				"effects": [{"type": "heal_allies", "pct": 22}, {"type": "cleanse_allies"}]},
			{"name": "天青云破", "name_en": "Sky Breaks Blue", "cd": 0, "target": "all_allies", "mult": 0.0, "hits": 0, "anim": "ultimate",
				"desc": "【奥义】全体队友恢复15%生命、攻击条+30%、获得【防御强化】2回合。",
				"desc_en": "ULTIMATE: All allies heal 15% HP, gain 30% Attack Bar and Defense Up for 2 turns.",
				"effects": [{"type": "heal_allies", "pct": 15}, {"type": "atb_boost_allies", "amount": 30},
					{"type": "buff_allies", "status": "def_up", "turns": 2}]},
		],
	},
	"sancaihorse": {
		"name": "三彩马", "name_en": "Sancai Steed", "element": Element.WIND, "role": "控速", "role_en": "Tempo",
		"origin": {"country": "中国", "country_en": "China", "era": "唐", "era_en": "Tang",
			"piece": "三彩马", "piece_en": "Sancai glazed horse"},
		"lore": "从唐墓里跑出来的马。三色釉在它身上流淌，跑得越快，颜色越乱。",
		"lore_en": "A horse that galloped out of a Tang tomb. Its three glazes run as it runs; the faster it goes, the wilder the colours.",
		"base": {"hp": 4700, "atk": 680, "def": 470, "spd": 124, "crit_rate": 20, "crit_dmg": 55, "acc": 30, "res": 20},
		"leader": {"stat": "spd_pct", "value": 14},
		"passive": {"id": "tailwind", "name": "流釉", "name_en": "Running Glaze",
			"desc": "行动后有20%几率立即获得额外回合。", "desc_en": "20% chance to take an extra turn after acting."},
		"skills": [
			{"name": "踏釉", "name_en": "Glaze Stomp", "cd": 0, "target": "enemy", "mult": 1.8, "hits": 2, "anim": "projectile",
				"desc": "两道三彩釉浪冲击敌人，削减目标15%攻击条。", "desc_en": "Two waves of tri-colour glaze; cuts the target's Attack Bar by 15%.",
				"effects": [{"type": "atb_reduce", "amount": 15, "chance": 100}]},
			{"name": "胡旋", "name_en": "Whirling Dance", "cd": 3, "target": "all_allies", "mult": 0.0, "hits": 0, "anim": "cast",
				"desc": "跳起胡旋舞：全体队友攻击条+25%，获得【攻击强化】2回合。", "desc_en": "A whirling dance: all allies gain 25% Attack Bar and Attack Up for 2 turns.",
				"effects": [{"type": "atb_boost_allies", "amount": 25}, {"type": "buff_allies", "status": "atk_up", "turns": 2}]},
			{"name": "万马奔腾", "name_en": "Thundering Herd", "cd": 0, "target": "all_enemies", "mult": 2.6, "hits": 1, "anim": "ultimate",
				"desc": "【奥义】釉色化作万马冲过全体敌人，削减35%攻击条。", "desc_en": "ULTIMATE: A herd of glaze tramples all enemies, cutting their Attack Bar by 35%.",
				"effects": [{"type": "atb_reduce", "amount": 35, "chance": 100}]},
		],
	},
	"childpillow": {
		"name": "孩儿枕", "name_en": "Child Pillow", "element": Element.LIGHT, "role": "治疗", "role_en": "Healer",
		"origin": {"country": "中国", "country_en": "China", "era": "北宋", "era_en": "Northern Song",
			"piece": "定窑白釉孩儿枕", "piece_en": "Ding ware white-glazed child pillow"},
		"lore": "趴着睡了九百年的小孩，一醒来就想帮所有人盖好被子。",
		"lore_en": "A child who napped on his tummy for nine hundred years. Awake now, he wants to tuck everyone in.",
		"base": {"hp": 5000, "atk": 660, "def": 520, "spd": 106, "crit_rate": 15, "crit_dmg": 50, "acc": 20, "res": 35},
		"leader": {"stat": "res", "value": 25},
		"passive": {"id": "clear_glaze", "name": "象牙白", "name_en": "Ivory Calm",
			"desc": "回合开始时，清除自身1个减益效果。", "desc_en": "At turn start, removes one harmful effect from itself."},
		"skills": [
			{"name": "丢枕头", "name_en": "Pillow Toss", "cd": 0, "target": "enemy", "mult": 3.3, "hits": 1, "anim": "projectile",
				"desc": "扔出一个软枕，50%几率【防御破坏】2回合。", "desc_en": "Throws a pillow. 50% chance to Break Defense for 2 turns.",
				"effects": [{"type": "debuff", "status": "def_break", "turns": 2, "chance": 50}]},
			{"name": "哄睡", "name_en": "Lullaby", "cd": 4, "target": "all_allies", "mult": 0.0, "hits": 0, "anim": "cast",
				"desc": "哼一首摇篮曲：全体队友恢复25%生命，获得【免疫】1回合。", "desc_en": "Hums a lullaby: all allies heal 25% and gain Immunity for 1 turn.",
				"effects": [{"type": "heal_allies", "pct": 25}, {"type": "buff_allies", "status": "immunity", "turns": 1}]},
			{"name": "黄粱一梦", "name_en": "Dream of Millet", "cd": 0, "target": "all_enemies", "mult": 2.5, "hits": 1, "anim": "ultimate",
				"desc": "【奥义】把梦境砸向全体敌人，随后清除全体队友减益并恢复15%生命。",
				"desc_en": "ULTIMATE: Drops a dream on all enemies, then cleanses all allies and heals them 15%.",
				"effects": [{"type": "cleanse_allies"}, {"type": "heal_allies", "pct": 15}]},
		],
	},
	"tigerpillow": {
		"name": "虎枕", "name_en": "Tiger Pillow", "element": Element.FIRE, "role": "斗士", "role_en": "Bruiser",
		"origin": {"country": "中国", "country_en": "China", "era": "宋金", "era_en": "Song-Jin",
			"piece": "磁州窑白地黑花虎形枕", "piece_en": "Cizhou ware tiger-shaped pillow"},
		"lore": "给人枕了几百年，终于轮到它发脾气了。背上还画着一幅山水。",
		"lore_en": "People slept on it for centuries. Now it's the tiger's turn to lose its temper. A landscape is still painted on its back.",
		"base": {"hp": 5600, "atk": 750, "def": 560, "spd": 98, "crit_rate": 20, "crit_dmg": 60, "acc": 20, "res": 20},
		"leader": {"stat": "def_pct", "value": 20},
		"passive": {"id": "stoked", "name": "起床气", "name_en": "Rude Awakening",
			"desc": "每次受到攻击，攻击条+10%。", "desc_en": "Gains 10% Attack Bar whenever it is hit."},
		"skills": [
			{"name": "虎扑", "name_en": "Pounce", "cd": 0, "target": "enemy", "mult": 3.5, "hits": 1, "anim": "melee",
				"desc": "猛扑一击，35%几率【眩晕】1回合。", "desc_en": "A heavy pounce. 35% chance to Stun for 1 turn.",
				"effects": [{"type": "debuff", "status": "stun", "turns": 1, "chance": 35}]},
			{"name": "虎啸", "name_en": "Roar", "cd": 3, "target": "all_enemies", "mult": 2.2, "hits": 1, "anim": "cast",
				"desc": "一声虎啸震慑全体，50%几率【防御破坏】2回合。", "desc_en": "A roar shakes all enemies. 50% chance to Break Defense.",
				"effects": [{"type": "debuff", "status": "def_break", "turns": 2, "chance": 50}]},
			{"name": "枕戈待旦", "name_en": "Sleep on the Spear", "cd": 0, "target": "enemy", "mult": 6.0, "hits": 1, "anim": "ultimate",
				"desc": "【奥义】彻底醒了——重击单体，自身【攻击强化】2回合。", "desc_en": "ULTIMATE: Fully awake. A crushing blow; gains Attack Up for 2 turns.",
				"effects": [{"type": "buff_self", "status": "atk_up", "turns": 2}]},
		],
	},
	"generaljar": {
		"name": "将军罐", "name_en": "General Jar", "element": Element.WATER, "role": "坦克", "role_en": "Tank",
		"origin": {"country": "中国", "country_en": "China", "era": "清·康熙", "era_en": "Qing · Kangxi",
			"piece": "青花将军罐", "piece_en": "Blue-and-white 'general' jar"},
		"lore": "罐盖是头盔，罐身是铠甲。因为长得像将军而得名，于是它真的当上了将军。",
		"lore_en": "Its lid is a helmet and its body is armour. Named for looking like a general, it decided to become one.",
		"base": {"hp": 6600, "atk": 540, "def": 760, "spd": 94, "crit_rate": 15, "crit_dmg": 50, "acc": 15, "res": 35},
		"leader": {"stat": "def_pct", "value": 22},
		"passive": {"id": "fired_shell", "name": "盖紧", "name_en": "Lid On Tight",
			"desc": "生命高于50%时，受到的伤害-20%。", "desc_en": "Takes 20% less damage while above 50% HP."},
		"skills": [
			{"name": "盖击", "name_en": "Lid Slam", "cd": 0, "target": "enemy", "mult": 3.1, "hits": 1, "anim": "melee",
				"desc": "用罐盖砸下，30%几率【冰冻】1回合。", "desc_en": "Slams with its lid. 30% chance to Freeze for 1 turn.",
				"effects": [{"type": "debuff", "status": "freeze", "turns": 1, "chance": 30}]},
			{"name": "青花阵", "name_en": "Cobalt Formation", "cd": 3, "target": "all_allies", "mult": 0.0, "hits": 0, "anim": "cast",
				"desc": "全体队友【防御强化】2回合、【免疫】1回合。", "desc_en": "All allies gain Defense Up (2 turns) and Immunity (1 turn).",
				"effects": [{"type": "buff_allies", "status": "def_up", "turns": 2}, {"type": "buff_allies", "status": "immunity", "turns": 1}]},
			{"name": "海水江崖", "name_en": "Waves and Cliffs", "cd": 0, "target": "all_enemies", "mult": 2.4, "hits": 1, "anim": "ultimate",
				"desc": "【奥义】罐身的海水纹涌出，震荡全体，削减30%攻击条，60%几率【冰冻】。",
				"desc_en": "ULTIMATE: The painted waves pour out: hits all, cuts Attack Bar by 30%, 60% Freeze.",
				"effects": [{"type": "atb_reduce", "amount": 30, "chance": 100}, {"type": "debuff", "status": "freeze", "turns": 1, "chance": 60}]},
		],
	},
	"phoenixvase": {
		"name": "凤耳瓶", "name_en": "Phoenix Vase", "element": Element.WIND, "role": "刺客", "role_en": "Assassin",
		"origin": {"country": "中国", "country_en": "China", "era": "南宋", "era_en": "Southern Song",
			"piece": "龙泉窑青釉凤耳瓶", "piece_en": "Longquan celadon phoenix-handled vase"},
		"lore": "瓶颈上的两只凤耳会自己转头。它们总在吵架，但出手时从不失手。",
		"lore_en": "The two phoenix handles on its neck turn their own heads. They always bicker, but they never miss.",
		"base": {"hp": 4100, "atk": 880, "def": 390, "spd": 116, "crit_rate": 30, "crit_dmg": 75, "acc": 15, "res": 15},
		"leader": {"stat": "crit_rate", "value": 15},
		"passive": {"id": "hairline", "name": "梅子青", "name_en": "Plum Green",
			"desc": "对生命低于50%的敌人伤害+40%。", "desc_en": "+40% damage to enemies below 50% HP."},
		"skills": [
			{"name": "凤啄", "name_en": "Phoenix Strike", "cd": 0, "target": "enemy", "mult": 3.6, "hits": 1, "anim": "melee",
				"desc": "双凤啄击，50%几率【防御破坏】2回合。", "desc_en": "The twin phoenixes strike. 50% chance to Break Defense.",
				"effects": [{"type": "debuff", "status": "def_break", "turns": 2, "chance": 50}]},
			{"name": "双凤回旋", "name_en": "Twin Spiral", "cd": 3, "target": "enemy", "mult": 2.4, "hits": 2, "anim": "melee",
				"desc": "回旋两击，削减目标25%攻击条。", "desc_en": "Spins twice and cuts the target's Attack Bar by 25%.",
				"effects": [{"type": "atb_reduce", "amount": 25, "chance": 100}]},
			{"name": "青梅一剪", "name_en": "Celadon Cut", "cd": 0, "target": "enemy", "mult": 6.6, "hits": 1, "anim": "ultimate",
				"desc": "【奥义】凤凰俯冲，一击对单体造成巨额伤害。", "desc_en": "ULTIMATE: The phoenixes dive as one. Massive single-target damage.",
				"effects": []},
		],
	},
	"yohenbowl": {
		"name": "曜变盏", "name_en": "Yohen Bowl", "element": Element.DARK, "role": "法师", "role_en": "Caster",
		"origin": {"country": "中国", "country_en": "China", "era": "南宋", "era_en": "Southern Song",
			"piece": "建窑曜变天目盏", "piece_en": "Jian ware 'Yohen' tenmoku tea bowl"},
		"lore": "碗底装着一整片星空。据说世上只有三只，它是跑出来的第四只。",
		"lore_en": "It holds a whole starry sky in its bowl. They say only three exist. This is the fourth, and it got away.",
		"base": {"hp": 4200, "atk": 820, "def": 420, "spd": 112, "crit_rate": 25, "crit_dmg": 65, "acc": 35, "res": 20},
		"leader": {"stat": "acc", "value": 25},
		"passive": {"id": "oil_spot", "name": "星斑", "name_en": "Star Spots",
			"desc": "击杀敌人时，立即获得额外回合。", "desc_en": "Takes an extra turn after defeating an enemy."},
		"skills": [
			{"name": "星屑", "name_en": "Stardust", "cd": 0, "target": "enemy", "mult": 3.3, "hits": 1, "anim": "projectile",
				"desc": "倒出一把星屑，60%几率【持续伤害】2回合。", "desc_en": "Pours out stardust. 60% chance to inflict Continuous Damage.",
				"effects": [{"type": "debuff", "status": "dot", "turns": 2, "chance": 60}]},
			{"name": "兔毫乱流", "name_en": "Hare's-Fur Surge", "cd": 3, "target": "all_enemies", "mult": 1.3, "hits": 2, "anim": "cast",
				"desc": "暗流两次攻击全体敌人，50%几率【持续伤害】。", "desc_en": "A dark surge hits all enemies twice. 50% chance of Continuous Damage.",
				"effects": [{"type": "debuff", "status": "dot", "turns": 2, "chance": 50}]},
			{"name": "盏中宇宙", "name_en": "Cosmos in a Cup", "cd": 0, "target": "enemy", "mult": 5.6, "hits": 1, "anim": "ultimate",
				"desc": "【奥义】把敌人倒进碗里的星空，80%几率【冰冻】，全体队友攻击条+20%。",
				"desc_en": "ULTIMATE: Pours an enemy into the starry bowl (80% Freeze); allies gain 20% Attack Bar.",
				"effects": [{"type": "debuff", "status": "freeze", "turns": 1, "chance": 80}, {"type": "atb_boost_allies", "amount": 20}]},
		],
	},
}

const SPECIES_ORDER := ["chickencup", "rulotus", "sancaihorse", "childpillow", "tigerpillow", "generaljar", "phoenixvase", "yohenbowl"]

## Starting trios offered at the beginning of a run.
const STARTERS := [
	{"name": "鸡鸣天青", "name_en": "Dawn & Sky", "team": ["chickencup", "rulotus", "sancaihorse"],
		"desc": "火+风焰暴，天青续航。", "desc_en": "Fire + Wind Firestorms, Ru blue to sustain."},
	{"name": "守夜人", "name_en": "Night Watch", "team": ["generaljar", "childpillow", "tigerpillow"],
		"desc": "将军守门，孩儿枕奶，老虎醒来再打。", "desc_en": "The General holds, the Child heals, the Tiger wakes up swinging."},
	{"name": "星与凤", "name_en": "Stars & Phoenix", "team": ["phoenixvase", "yohenbowl", "sancaihorse"],
		"desc": "高速斩杀，击杀连动。", "desc_en": "Fast executions that chain off kills."},
]


# --- Boss ----------------------------------------------------------------------------
const BOSS := {
	"name": "无缮之王", "name_en": "The Unmended", "element": Element.DARK, "role": "首领", "role_en": "Boss",
	"origin": {"country": "？", "country_en": "?", "era": "不详", "era_en": "Unknown", "piece": "一只从未被修补的大罐", "piece_en": "A great jar that was never mended"},
	"lore": "所有拒绝被金子补好的碎片，聚成了它。", "lore_en": "Every shard that refused the gold gathered into this.",
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
