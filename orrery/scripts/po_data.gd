extends RefCounted
## Goldmend :: static game data (bilingual).
## Every player-facing text has a Chinese field (`name`, `desc`, ...) and an
## English twin (`name_en`, `desc_en`, ...). Read them through po_i18n.gd.
## Numbers, formulas and balance targets are documented in docs/DESIGN.md.
## No `class_name` anywhere in this project: scripts reference each other via
## `preload()` constants, so nothing leaks into the global class namespace.

# --- Five Phases (五行), grounded in how porcelain is made --------------------------
#   金 Metal : gold repair and gilding          木 Wood : plant-ash (celadon) glazes
#   水 Water : cobalt blue and sky-blue glazes  火 Fire : the kiln, copper red
#   土 Earth : the clay body and earthenware
enum Element { METAL, WOOD, WATER, FIRE, EARTH }

const ELEMENT_NAMES := ["金", "木", "水", "火", "土"]
const ELEMENT_NAMES_EN := ["Metal", "Wood", "Water", "Fire", "Earth"]
const ELEMENT_COLORS := [
	Color(1.0, 0.8, 0.35),
	Color(0.4, 0.88, 0.5),
	Color(0.28, 0.62, 1.0),
	Color(1.0, 0.36, 0.2),
	Color(0.88, 0.6, 0.3),
]
const ELEMENT_CRAFT := [
	{"zh": "金缮与金彩", "en": "gold repair and gilding"},
	{"zh": "草木灰釉（青瓷）", "en": "plant-ash glazes (celadon)"},
	{"zh": "青花钴料与天青釉", "en": "cobalt blue and sky-blue glazes"},
	{"zh": "窑火与铜红", "en": "the kiln fire and copper red"},
	{"zh": "胎土与陶", "en": "the clay body and earthenware"},
]

## 相克 overcoming: 金克木 木克土 土克水 水克火 火克金
const KE := {Element.METAL: Element.WOOD, Element.WOOD: Element.EARTH, Element.EARTH: Element.WATER,
	Element.WATER: Element.FIRE, Element.FIRE: Element.METAL}
## 相生 generating: 木生火 火生土 土生金 金生水 水生木
const SHENG := {Element.WOOD: Element.FIRE, Element.FIRE: Element.EARTH, Element.EARTH: Element.METAL,
	Element.METAL: Element.WATER, Element.WATER: Element.WOOD}


## 1 = attacker overcomes defender, -1 = defender overcomes attacker, 0 = neutral.
static func affinity(attacker: int, defender: int) -> int:
	if KE.get(attacker, -1) == defender:
		return 1
	if KE.get(defender, -1) == attacker:
		return -1
	return 0


static func generates(a: int, b: int) -> bool:
	return SHENG.get(a, -1) == b


# --- Combat tuning (see docs/DESIGN.md) ------------------------------------------------
const ATB_PER_SPD := 0.07
const ADV_DAMAGE := 1.25            # 相克 damage
const ADV_CRACK := 1.5              # 相克 crack
const DISADV_DAMAGE := 0.85
const DISADV_CRACK := 0.7
const ATK_UP := 0.5
const DEF_UP := 0.6
const DEF_BREAK := 0.6
const DOT_PCT := 0.05
const SLOW := 0.3
const MIN_RESIST := 15.0
const ENERGY_START := 25.0
const ENERGY_PER_ACTION := 25.0
const ENERGY_ON_HIT := 8.0
const ENERGY_ON_KILL := 15.0
const BROKEN_DAMAGE_TAKEN := 1.3    # while a figure is 崩裂 (broken)
const BREAK_ATB := 35.0             # a break knocks the Attack Bar back this much
const CHAIN_DAMAGE_STEP := 0.15     # 相生 chain: +15% damage per link after the first
const CHAIN_CRACK_STEP := 0.25
const CHAIN_ENERGY := 10.0
const CHAIN_MAX := 5
const MONO_CHAIN := 1.3             # Monochrome trait: chain bonuses x1.3
const MEND_CRACK := 30.0            # healing skills also mend this much crack


# --- Break effects (窑变): what happens when the breaking blow is of each element -------
const BREAK_EFFECTS := [
	{"name": "金缮", "name_en": "Gilded", "desc": "击碎者一方获得最大生命12%的金釉护盾。", "desc_en": "The breaker's team gains a gold shield of 12% max HP."},
	{"name": "灰釉", "name_en": "Ash Glaze", "desc": "击碎者一方恢复8%最大生命。", "desc_en": "The breaker's team heals 8% max HP."},
	{"name": "冷缩", "name_en": "Chill", "desc": "目标【迟缓】2回合（速度-30%）。", "desc_en": "The target is Slowed for 2 turns (SPD -30%)."},
	{"name": "起泡", "name_en": "Blister", "desc": "目标附加2层【持续伤害】2回合。", "desc_en": "The target gets 2 stacks of Continuous Damage for 2 turns."},
	{"name": "塌陷", "name_en": "Collapse", "desc": "目标【防御破坏】2回合。", "desc_en": "The target's Defense is Broken for 2 turns."},
]


# --- Statuses -------------------------------------------------------------------------
const STATUS := {
	"atk_up": {"label": "攻↑", "label_en": "ATK↑", "name": "攻击强化", "name_en": "Attack Up", "buff": true, "color": Color(1.0, 0.55, 0.25)},
	"def_up": {"label": "防↑", "label_en": "DEF↑", "name": "防御强化", "name_en": "Defense Up", "buff": true, "color": Color(0.35, 0.75, 1.0)},
	"immunity": {"label": "免", "label_en": "IMM", "name": "免疫", "name_en": "Immunity", "buff": true, "color": Color(1.0, 0.92, 0.55)},
	"def_break": {"label": "破", "label_en": "BRK", "name": "防御破坏", "name_en": "Defense Break", "buff": false, "color": Color(0.95, 0.3, 0.3)},
	"dot": {"label": "蚀", "label_en": "DOT", "name": "持续伤害", "name_en": "Continuous Dmg", "buff": false, "color": Color(0.85, 0.35, 0.9)},
	"stun": {"label": "晕", "label_en": "STN", "name": "眩晕", "name_en": "Stun", "buff": false, "color": Color(1.0, 0.85, 0.2)},
	"freeze": {"label": "冰", "label_en": "FRZ", "name": "冰冻", "name_en": "Freeze", "buff": false, "color": Color(0.6, 0.92, 1.0)},
	"slow": {"label": "缓", "label_en": "SLW", "name": "迟缓", "name_en": "Slow", "buff": false, "color": Color(0.55, 0.7, 0.95)},
}


# --- Vessel Spirits (器灵) -------------------------------------------------------------
# Every figure is a real, museum-famous piece of porcelain drawn as a cartoon.
# `origin` records where the real piece comes from so the roster can grow to
# other countries (Delft, Meissen, Imari, Iznik ...). `tags` feed the traits.
# `toughness` (胎厚) is how much crack a figure takes before it breaks.
# Skill fields:
#   target: "enemy" | "all_enemies" | "all_allies"; index 2 is the Ultimate (energy)
#   mult: ATK multiplier per hit (0 = no damage); hits: number of hits
#   crack: total crack the skill deals to each target (split across hits)
#   anim: "melee" | "projectile" | "cast" | "ultimate"
#   effects on each damaged target: debuff{status,turns,chance}, atb_reduce{amount,chance}
#   effects on the caster's side:   heal_allies{pct} (also mends crack), cleanse_allies,
#       buff_allies{status,turns}, atb_boost_allies{amount}, buff_self{status,turns},
#       shield_allies{pct}
const SPECIES := {
	"chickencup": {
		"name": "鸡缸杯", "name_en": "Chicken Cup", "element": Element.FIRE, "role": "输出", "role_en": "Striker",
		"tags": ["ming", "painted"], "toughness": 90,
		"origin": {"country": "中国", "country_en": "China", "era": "明·成化", "era_en": "Ming · Chenghua",
			"piece": "斗彩鸡缸杯", "piece_en": "Doucai 'Chicken Cup'"},
		"lore": "杯身上画的那只公鸡跳了出来，把整只杯子顶在身上。脾气火爆，天不亮就要打鸣。",
		"lore_en": "The rooster painted on the cup jumped out and wears the whole cup as armour. Hot-tempered; crows before dawn.",
		"base": {"hp": 4300, "atk": 840, "def": 400, "spd": 110, "crit_rate": 25, "crit_dmg": 70, "acc": 20, "res": 15},
		"leader": {"stat": "atk_pct", "value": 15},
		"passive": {"id": "molten_core", "name": "斗性", "name_en": "Fighting Spirit",
			"desc": "对带有【持续伤害】的敌人伤害+25%。", "desc_en": "+25% damage to enemies with Continuous Damage."},
		"skills": [
			{"name": "啄火", "name_en": "Fire Peck", "cd": 0, "target": "enemy", "mult": 3.6, "hits": 1, "crack": 25, "anim": "melee",
				"desc": "带火的一啄，50%几率附加【持续伤害】2回合。", "desc_en": "A burning peck. 50% chance to inflict Continuous Damage for 2 turns.",
				"effects": [{"type": "debuff", "status": "dot", "turns": 2, "chance": 50}]},
			{"name": "斗彩三连", "name_en": "Doucai Flurry", "cd": 3, "target": "enemy", "mult": 1.5, "hits": 3, "crack": 36, "anim": "projectile",
				"desc": "甩出三片彩釉翎羽，每击35%几率附加【持续伤害】。", "desc_en": "Flings three enamel feathers; each has a 35% chance of Continuous Damage.",
				"effects": [{"type": "debuff", "status": "dot", "turns": 2, "chance": 35}]},
			{"name": "金鸡报晓", "name_en": "Dawn Crow", "cd": 0, "target": "all_enemies", "mult": 3.0, "hits": 1, "crack": 30, "anim": "ultimate",
				"desc": "【奥义】一声啼鸣烧红天际，攻击全体敌人，60%几率【持续伤害】。",
				"desc_en": "ULTIMATE: A crow that sets the sky ablaze. Hits all enemies; 60% Continuous Damage.",
				"effects": [{"type": "debuff", "status": "dot", "turns": 2, "chance": 60}]},
		],
		"upgrades": [
			{"id": "cc_overglaze", "name": "釉上重彩", "name_en": "Overglaze Enamels", "desc": "啄火改为两次啄击（每击2.2倍）。", "desc_en": "Fire Peck strikes twice (2.2x each).",
				"mods": [{"skill": 0, "hits": 2, "mult": 2.2}]},
			{"id": "cc_copper", "name": "铜红", "name_en": "Copper Red", "desc": "啄火必定附加【持续伤害】。", "desc_en": "Fire Peck always inflicts Continuous Damage.",
				"mods": [{"skill": 0, "effect_chance": 100}]},
			{"id": "cc_panel", "name": "开光", "name_en": "Framed Panels", "desc": "斗彩三连冷却-1。", "desc_en": "Doucai Flurry cooldown -1.",
				"mods": [{"skill": 1, "cd": -1}]},
			{"id": "cc_imperial", "name": "成化御制", "name_en": "Imperial Mark", "desc": "金鸡报晓裂纹+40。", "desc_en": "Dawn Crow deals +40 crack.",
				"mods": [{"skill": 2, "crack": 40}]},
		],
	},
	"rulotus": {
		"name": "汝窑莲碗", "name_en": "Ru Lotus Bowl", "element": Element.WATER, "role": "辅助", "role_en": "Support",
		"tags": ["song", "mono"], "toughness": 100,
		"origin": {"country": "中国", "country_en": "China", "era": "北宋", "era_en": "Northern Song",
			"piece": "汝窑天青釉莲花式温碗", "piece_en": "Ru ware sky-blue lotus warming bowl"},
		"lore": "「雨过天青云破处」——它的釉色就是那片天。身上的冰裂纹一笑就会轻轻作响。",
		"lore_en": "\"The blue of the sky after rain\" - that is its glaze. Its ice-crackle chimes softly when it laughs.",
		"base": {"hp": 5400, "atk": 600, "def": 520, "spd": 104, "crit_rate": 15, "crit_dmg": 50, "acc": 25, "res": 25},
		"leader": {"stat": "hp_pct", "value": 18},
		"passive": {"id": "moon_dew", "name": "雨过天青", "name_en": "After the Rain",
			"desc": "回合开始时，为生命最低的队友恢复6%最大生命。", "desc_en": "At turn start, heals the lowest-HP ally for 6% max HP."},
		"skills": [
			{"name": "碗中涟漪", "name_en": "Ripple", "cd": 0, "target": "enemy", "mult": 3.2, "hits": 1, "crack": 25, "anim": "projectile",
				"desc": "泼出一道碗中之水，削减目标20%攻击条。", "desc_en": "Splashes water from its bowl and cuts the target's Attack Bar by 20%.",
				"effects": [{"type": "atb_reduce", "amount": 20, "chance": 100}]},
			{"name": "温碗", "name_en": "Warming Bowl", "cd": 3, "target": "all_allies", "mult": 0.0, "hits": 0, "crack": 0, "anim": "cast",
				"desc": "为全体队友恢复18%最大生命、修补裂纹，并清除所有减益。", "desc_en": "Heals all allies for 18% max HP, mends their cracks and removes all harmful effects.",
				"effects": [{"type": "heal_allies", "pct": 18}, {"type": "cleanse_allies"}]},
			{"name": "天青云破", "name_en": "Sky Breaks Blue", "cd": 0, "target": "all_allies", "mult": 0.0, "hits": 0, "crack": 0, "anim": "ultimate",
				"desc": "【奥义】全体队友恢复12%生命、攻击条+30%、获得【防御强化】2回合。",
				"desc_en": "ULTIMATE: All allies heal 12% HP, gain 30% Attack Bar and Defense Up for 2 turns.",
				"effects": [{"type": "heal_allies", "pct": 12}, {"type": "atb_boost_allies", "amount": 30},
					{"type": "buff_allies", "status": "def_up", "turns": 2}]},
		],
		"upgrades": [
			{"id": "ru_sky", "name": "雨过天青", "name_en": "Clearer Sky", "desc": "温碗治疗+10%。", "desc_en": "Warming Bowl heals 10% more.",
				"mods": [{"skill": 1, "heal_add": 10}]},
			{"id": "ru_crab", "name": "蟹爪纹", "name_en": "Crab-claw Crackle", "desc": "碗中涟漪裂纹+20。", "desc_en": "Ripple deals +20 crack.",
				"mods": [{"skill": 0, "crack": 20}]},
			{"id": "ru_fullglaze", "name": "满釉支烧", "name_en": "Fully Glazed", "desc": "温碗额外给全队10%护盾。", "desc_en": "Warming Bowl also shields every ally for 10%.",
				"mods": [{"skill": 1, "add_effect": {"type": "shield_allies", "pct": 10}}]},
			{"id": "ru_cloud", "name": "云破处", "name_en": "Where Clouds Part", "desc": "天青云破的拉条提高到45%。", "desc_en": "Sky Breaks Blue boosts Attack Bar by 45%.",
				"mods": [{"skill": 2, "atb_boost": 45}]},
		],
	},
	"sancaihorse": {
		"name": "三彩马", "name_en": "Sancai Steed", "element": Element.EARTH, "role": "控速", "role_en": "Tempo",
		"tags": ["tang", "painted"], "toughness": 95,
		"origin": {"country": "中国", "country_en": "China", "era": "唐", "era_en": "Tang",
			"piece": "三彩马", "piece_en": "Sancai glazed horse"},
		"lore": "从唐墓里跑出来的马。三色釉在它身上流淌，跑得越快，颜色越乱。",
		"lore_en": "A horse that galloped out of a Tang tomb. Its three glazes run as it runs; the faster it goes, the wilder the colours.",
		"base": {"hp": 4700, "atk": 680, "def": 470, "spd": 124, "crit_rate": 20, "crit_dmg": 55, "acc": 30, "res": 20},
		"leader": {"stat": "spd_pct", "value": 12},
		"passive": {"id": "tailwind", "name": "流釉", "name_en": "Running Glaze",
			"desc": "行动后有20%几率立即获得额外回合。", "desc_en": "20% chance to take an extra turn after acting."},
		"skills": [
			{"name": "踏釉", "name_en": "Glaze Stomp", "cd": 0, "target": "enemy", "mult": 1.8, "hits": 2, "crack": 30, "anim": "projectile",
				"desc": "两道三彩釉浪冲击敌人，削减目标15%攻击条。", "desc_en": "Two waves of tri-colour glaze; cuts the target's Attack Bar by 15%.",
				"effects": [{"type": "atb_reduce", "amount": 15, "chance": 100}]},
			{"name": "胡旋", "name_en": "Whirling Dance", "cd": 3, "target": "all_allies", "mult": 0.0, "hits": 0, "crack": 0, "anim": "cast",
				"desc": "跳起胡旋舞：全体队友攻击条+25%，获得【攻击强化】2回合。", "desc_en": "A whirling dance: all allies gain 25% Attack Bar and Attack Up for 2 turns.",
				"effects": [{"type": "atb_boost_allies", "amount": 25}, {"type": "buff_allies", "status": "atk_up", "turns": 2}]},
			{"name": "万马奔腾", "name_en": "Thundering Herd", "cd": 0, "target": "all_enemies", "mult": 2.6, "hits": 1, "crack": 30, "anim": "ultimate",
				"desc": "【奥义】釉色化作万马冲过全体敌人，削减35%攻击条。", "desc_en": "ULTIMATE: A herd of glaze tramples all enemies, cutting their Attack Bar by 35%.",
				"effects": [{"type": "atb_reduce", "amount": 35, "chance": 100}]},
		],
		"upgrades": [
			{"id": "sc_cobalt", "name": "蓝彩", "name_en": "Cobalt Accent", "desc": "踏釉削减攻击条提高到25%。", "desc_en": "Glaze Stomp cuts Attack Bar by 25%.",
				"mods": [{"skill": 0, "atb_reduce": 25}]},
			{"id": "sc_whirl", "name": "胡旋舞", "name_en": "Sogdian Whirl", "desc": "胡旋冷却-1。", "desc_en": "Whirling Dance cooldown -1.",
				"mods": [{"skill": 1, "cd": -1}]},
			{"id": "sc_applique", "name": "贴花", "name_en": "Appliqué", "desc": "踏釉裂纹+15。", "desc_en": "Glaze Stomp deals +15 crack.",
				"mods": [{"skill": 0, "crack": 15}]},
			{"id": "sc_herd", "name": "万马", "name_en": "The Herd", "desc": "万马奔腾同时让全体队友攻击条+15%。", "desc_en": "Thundering Herd also gives allies 15% Attack Bar.",
				"mods": [{"skill": 2, "add_effect": {"type": "atb_boost_allies", "amount": 15}}]},
		],
	},
	"childpillow": {
		"name": "孩儿枕", "name_en": "Child Pillow", "element": Element.METAL, "role": "治疗", "role_en": "Healer",
		"tags": ["song", "mono"], "toughness": 100,
		"origin": {"country": "中国", "country_en": "China", "era": "北宋", "era_en": "Northern Song",
			"piece": "定窑白釉孩儿枕", "piece_en": "Ding ware white-glazed child pillow"},
		"lore": "趴着睡了九百年的小孩，一醒来就想帮所有人盖好被子。",
		"lore_en": "A child who napped on his tummy for nine hundred years. Awake now, he wants to tuck everyone in.",
		"base": {"hp": 5000, "atk": 660, "def": 520, "spd": 106, "crit_rate": 15, "crit_dmg": 50, "acc": 20, "res": 35},
		"leader": {"stat": "res", "value": 25},
		"passive": {"id": "clear_glaze", "name": "象牙白", "name_en": "Ivory Calm",
			"desc": "回合开始时，清除自身1个减益效果。", "desc_en": "At turn start, removes one harmful effect from itself."},
		"skills": [
			{"name": "丢枕头", "name_en": "Pillow Toss", "cd": 0, "target": "enemy", "mult": 3.3, "hits": 1, "crack": 25, "anim": "projectile",
				"desc": "扔出一个绣球，50%几率【防御破坏】2回合。", "desc_en": "Throws an embroidered ball. 50% chance to Break Defense for 2 turns.",
				"effects": [{"type": "debuff", "status": "def_break", "turns": 2, "chance": 50}]},
			{"name": "哄睡", "name_en": "Lullaby", "cd": 4, "target": "all_allies", "mult": 0.0, "hits": 0, "crack": 0, "anim": "cast",
				"desc": "哼一首摇篮曲：全体队友恢复20%生命、修补裂纹，获得【免疫】1回合。", "desc_en": "A lullaby: all allies heal 20%, mend their cracks and gain Immunity for 1 turn.",
				"effects": [{"type": "heal_allies", "pct": 20}, {"type": "buff_allies", "status": "immunity", "turns": 1}]},
			{"name": "黄粱一梦", "name_en": "Dream of Millet", "cd": 0, "target": "all_enemies", "mult": 2.5, "hits": 1, "crack": 25, "anim": "ultimate",
				"desc": "【奥义】把梦境砸向全体敌人，随后清除全体队友减益并恢复12%生命。",
				"desc_en": "ULTIMATE: Drops a dream on all enemies, then cleanses all allies and heals them 12%.",
				"effects": [{"type": "cleanse_allies"}, {"type": "heal_allies", "pct": 12}]},
		],
		"upgrades": [
			{"id": "cp_rim", "name": "芒口镶金", "name_en": "Gilded Rim", "desc": "哄睡额外给全队10%护盾。", "desc_en": "Lullaby also shields every ally for 10%.",
				"mods": [{"skill": 1, "add_effect": {"type": "shield_allies", "pct": 10}}]},
			{"id": "cp_stamp", "name": "印花", "name_en": "Stamped Pattern", "desc": "丢枕头裂纹+20。", "desc_en": "Pillow Toss deals +20 crack.",
				"mods": [{"skill": 0, "crack": 20}]},
			{"id": "cp_dream", "name": "一梦千年", "name_en": "A Thousand-Year Nap", "desc": "黄粱一梦治疗提高到22%。", "desc_en": "Dream of Millet heals 22%.",
				"mods": [{"skill": 2, "heal_add": 10}]},
			{"id": "cp_carve", "name": "刻花", "name_en": "Carved Lotus", "desc": "哄睡冷却-1。", "desc_en": "Lullaby cooldown -1.",
				"mods": [{"skill": 1, "cd": -1}]},
		],
	},
	"tigerpillow": {
		"name": "虎枕", "name_en": "Tiger Pillow", "element": Element.FIRE, "role": "斗士", "role_en": "Bruiser",
		"tags": ["song", "painted"], "toughness": 120,
		"origin": {"country": "中国", "country_en": "China", "era": "宋金", "era_en": "Song-Jin",
			"piece": "磁州窑白地黑花虎形枕", "piece_en": "Cizhou ware tiger-shaped pillow"},
		"lore": "给人枕了几百年，终于轮到它发脾气了。背上还画着一幅山水。",
		"lore_en": "People slept on it for centuries. Now it's the tiger's turn to lose its temper. A landscape is still painted on its back.",
		"base": {"hp": 5600, "atk": 790, "def": 560, "spd": 98, "crit_rate": 20, "crit_dmg": 60, "acc": 20, "res": 20},
		"leader": {"stat": "def_pct", "value": 18},
		"passive": {"id": "stoked", "name": "起床气", "name_en": "Rude Awakening",
			"desc": "每次受到攻击，攻击条+10%。", "desc_en": "Gains 10% Attack Bar whenever it is hit."},
		"skills": [
			{"name": "虎扑", "name_en": "Pounce", "cd": 0, "target": "enemy", "mult": 3.5, "hits": 1, "crack": 35, "anim": "melee",
				"desc": "猛扑一击，35%几率【眩晕】1回合。", "desc_en": "A heavy pounce. 35% chance to Stun for 1 turn.",
				"effects": [{"type": "debuff", "status": "stun", "turns": 1, "chance": 35}]},
			{"name": "虎啸", "name_en": "Roar", "cd": 3, "target": "all_enemies", "mult": 2.2, "hits": 1, "crack": 25, "anim": "cast",
				"desc": "一声虎啸震慑全体，50%几率【防御破坏】2回合。", "desc_en": "A roar shakes all enemies. 50% chance to Break Defense.",
				"effects": [{"type": "debuff", "status": "def_break", "turns": 2, "chance": 50}]},
			{"name": "枕戈待旦", "name_en": "Sleep on the Spear", "cd": 0, "target": "enemy", "mult": 6.0, "hits": 1, "crack": 60, "anim": "ultimate",
				"desc": "【奥义】彻底醒了——重击单体，自身【攻击强化】2回合。", "desc_en": "ULTIMATE: Fully awake. A crushing blow; gains Attack Up for 2 turns.",
				"effects": [{"type": "buff_self", "status": "atk_up", "turns": 2}]},
		],
		"upgrades": [
			{"id": "tp_slip", "name": "白地黑花", "name_en": "Slip Painting", "desc": "虎扑裂纹+20。", "desc_en": "Pounce deals +20 crack.",
				"mods": [{"skill": 0, "crack": 20}]},
			{"id": "tp_grumpy", "name": "起床更气", "name_en": "Grumpier", "desc": "被攻击时攻击条+18%（原10%）。", "desc_en": "Gains 18% Attack Bar when hit (was 10%).",
				"mods": [{"passive_value": 18}]},
			{"id": "tp_roar", "name": "虎啸山林", "name_en": "Mountain Roar", "desc": "虎啸同时削减全体敌人20%攻击条。", "desc_en": "Roar also cuts every enemy's Attack Bar by 20%.",
				"mods": [{"skill": 1, "add_effect": {"type": "atb_reduce", "amount": 20, "chance": 100}}]},
			{"id": "tp_spear", "name": "枕戈", "name_en": "Spear Ready", "desc": "枕戈待旦必定【防御破坏】目标2回合。", "desc_en": "Sleep on the Spear always Breaks Defense for 2 turns.",
				"mods": [{"skill": 2, "add_effect": {"type": "debuff", "status": "def_break", "turns": 2, "chance": 100}}]},
		],
	},
	"generaljar": {
		"name": "将军罐", "name_en": "General Jar", "element": Element.WATER, "role": "坦克", "role_en": "Tank",
		"tags": ["qing", "painted"], "toughness": 150,
		"origin": {"country": "中国", "country_en": "China", "era": "清·康熙", "era_en": "Qing · Kangxi",
			"piece": "青花将军罐", "piece_en": "Blue-and-white 'general' jar"},
		"lore": "罐盖是头盔，罐身是铠甲。因为长得像将军而得名，于是它真的当上了将军。",
		"lore_en": "Its lid is a helmet and its body is armour. Named for looking like a general, it decided to become one.",
		"base": {"hp": 6600, "atk": 540, "def": 760, "spd": 94, "crit_rate": 15, "crit_dmg": 50, "acc": 15, "res": 35},
		"leader": {"stat": "def_pct", "value": 20},
		"passive": {"id": "fired_shell", "name": "盖紧", "name_en": "Lid On Tight",
			"desc": "生命高于50%时，受到的伤害-20%。", "desc_en": "Takes 20% less damage while above 50% HP."},
		"skills": [
			{"name": "盖击", "name_en": "Lid Slam", "cd": 0, "target": "enemy", "mult": 3.1, "hits": 1, "crack": 30, "anim": "melee",
				"desc": "用罐盖砸下，30%几率【冰冻】1回合。", "desc_en": "Slams with its lid. 30% chance to Freeze for 1 turn.",
				"effects": [{"type": "debuff", "status": "freeze", "turns": 1, "chance": 30}]},
			{"name": "青花阵", "name_en": "Cobalt Formation", "cd": 3, "target": "all_allies", "mult": 0.0, "hits": 0, "crack": 0, "anim": "cast",
				"desc": "全体队友【防御强化】2回合、【免疫】1回合。", "desc_en": "All allies gain Defense Up (2 turns) and Immunity (1 turn).",
				"effects": [{"type": "buff_allies", "status": "def_up", "turns": 2}, {"type": "buff_allies", "status": "immunity", "turns": 1}]},
			{"name": "海水江崖", "name_en": "Waves and Cliffs", "cd": 0, "target": "all_enemies", "mult": 2.4, "hits": 1, "crack": 35, "anim": "ultimate",
				"desc": "【奥义】罐身的海水纹涌出，震荡全体，削减30%攻击条，60%几率【冰冻】。",
				"desc_en": "ULTIMATE: The painted waves pour out: hits all, cuts Attack Bar by 30%, 60% Freeze.",
				"effects": [{"type": "atb_reduce", "amount": 30, "chance": 100}, {"type": "debuff", "status": "freeze", "turns": 1, "chance": 60}]},
		],
		"upgrades": [
			{"id": "gj_thick", "name": "加厚胎", "name_en": "Thick Body", "desc": "胎厚+40%。", "desc_en": "Toughness +40%.",
				"mods": [{"toughness_mult": 1.4}]},
			{"id": "gj_underglaze", "name": "釉下青花", "name_en": "Underglaze Blue", "desc": "青花阵额外给全队12%护盾。", "desc_en": "Cobalt Formation also shields every ally for 12%.",
				"mods": [{"skill": 1, "add_effect": {"type": "shield_allies", "pct": 12}}]},
			{"id": "gj_knob", "name": "宝珠钮", "name_en": "Pearl Knob", "desc": "盖击裂纹+25。", "desc_en": "Lid Slam deals +25 crack.",
				"mods": [{"skill": 0, "crack": 25}]},
			{"id": "gj_waves", "name": "海水涌", "name_en": "Rising Sea", "desc": "海水江崖改为两次冲击。", "desc_en": "Waves and Cliffs strikes twice.",
				"mods": [{"skill": 2, "hits": 2, "mult": 1.5}]},
		],
	},
	"phoenixvase": {
		"name": "凤耳瓶", "name_en": "Phoenix Vase", "element": Element.WOOD, "role": "刺客", "role_en": "Assassin",
		"tags": ["song", "mono"], "toughness": 80,
		"origin": {"country": "中国", "country_en": "China", "era": "南宋", "era_en": "Southern Song",
			"piece": "龙泉窑青釉凤耳瓶", "piece_en": "Longquan celadon phoenix-handled vase"},
		"lore": "瓶颈上的两只凤耳会自己转头。它们总在吵架，但出手时从不失手。",
		"lore_en": "The two phoenix handles on its neck turn their own heads. They always bicker, but they never miss.",
		"base": {"hp": 4100, "atk": 880, "def": 390, "spd": 116, "crit_rate": 30, "crit_dmg": 75, "acc": 15, "res": 15},
		"leader": {"stat": "crit_rate", "value": 12},
		"passive": {"id": "hairline", "name": "梅子青", "name_en": "Plum Green",
			"desc": "对生命低于50%的敌人伤害+40%。", "desc_en": "+40% damage to enemies below 50% HP."},
		"skills": [
			{"name": "凤啄", "name_en": "Phoenix Strike", "cd": 0, "target": "enemy", "mult": 3.6, "hits": 1, "crack": 25, "anim": "melee",
				"desc": "双凤啄击，50%几率【防御破坏】2回合。", "desc_en": "The twin phoenixes strike. 50% chance to Break Defense.",
				"effects": [{"type": "debuff", "status": "def_break", "turns": 2, "chance": 50}]},
			{"name": "双凤回旋", "name_en": "Twin Spiral", "cd": 3, "target": "enemy", "mult": 2.4, "hits": 2, "crack": 40, "anim": "melee",
				"desc": "回旋两击，削减目标25%攻击条。", "desc_en": "Spins twice and cuts the target's Attack Bar by 25%.",
				"effects": [{"type": "atb_reduce", "amount": 25, "chance": 100}]},
			{"name": "青梅一剪", "name_en": "Celadon Cut", "cd": 0, "target": "enemy", "mult": 6.6, "hits": 1, "crack": 50, "anim": "ultimate",
				"desc": "【奥义】凤凰俯冲，一击对单体造成巨额伤害。", "desc_en": "ULTIMATE: The phoenixes dive as one. Massive single-target damage.",
				"effects": []},
		],
		"upgrades": [
			{"id": "pv_plum", "name": "梅子青", "name_en": "Plum Green Glaze", "desc": "凤啄伤害+25%。", "desc_en": "Phoenix Strike deals 25% more damage.",
				"mods": [{"skill": 0, "mult_mul": 1.25}]},
			{"id": "pv_twin", "name": "双凤齐鸣", "name_en": "Twin Cry", "desc": "双凤回旋冷却-1。", "desc_en": "Twin Spiral cooldown -1.",
				"mods": [{"skill": 1, "cd": -1}]},
			{"id": "pv_thin", "name": "薄胎", "name_en": "Eggshell Body", "desc": "速度+12，胎厚-15%。", "desc_en": "SPD +12, toughness -15%.",
				"mods": [{"stat": "spd", "add": 12}, {"toughness_mult": 0.85}]},
			{"id": "pv_powder", "name": "粉青", "name_en": "Powder Blue", "desc": "青梅一剪裂纹+50。", "desc_en": "Celadon Cut deals +50 crack.",
				"mods": [{"skill": 2, "crack": 50}]},
		],
	},
	"yohenbowl": {
		"name": "曜变盏", "name_en": "Yohen Bowl", "element": Element.METAL, "role": "法师", "role_en": "Caster",
		"tags": ["song", "mono"], "toughness": 90,
		"origin": {"country": "中国", "country_en": "China", "era": "南宋", "era_en": "Southern Song",
			"piece": "建窑曜变天目盏", "piece_en": "Jian ware 'Yohen' tenmoku tea bowl"},
		"lore": "碗底装着一整片星空。据说世上只有三只，它是跑出来的第四只。",
		"lore_en": "It holds a whole starry sky in its bowl. They say only three exist. This is the fourth, and it got away.",
		"base": {"hp": 4200, "atk": 820, "def": 420, "spd": 112, "crit_rate": 25, "crit_dmg": 65, "acc": 35, "res": 20},
		"leader": {"stat": "acc", "value": 20},
		"passive": {"id": "oil_spot", "name": "星斑", "name_en": "Star Spots",
			"desc": "击杀敌人时，立即获得额外回合。", "desc_en": "Takes an extra turn after defeating an enemy."},
		"skills": [
			{"name": "星屑", "name_en": "Stardust", "cd": 0, "target": "enemy", "mult": 3.3, "hits": 1, "crack": 25, "anim": "projectile",
				"desc": "倒出一把星屑，60%几率【持续伤害】2回合。", "desc_en": "Pours out stardust. 60% chance to inflict Continuous Damage.",
				"effects": [{"type": "debuff", "status": "dot", "turns": 2, "chance": 60}]},
			{"name": "兔毫乱流", "name_en": "Hare's-Fur Surge", "cd": 3, "target": "all_enemies", "mult": 1.3, "hits": 2, "crack": 30, "anim": "cast",
				"desc": "暗流两次攻击全体敌人，50%几率【持续伤害】。", "desc_en": "A dark surge hits all enemies twice. 50% chance of Continuous Damage.",
				"effects": [{"type": "debuff", "status": "dot", "turns": 2, "chance": 50}]},
			{"name": "盏中宇宙", "name_en": "Cosmos in a Cup", "cd": 0, "target": "enemy", "mult": 5.6, "hits": 1, "crack": 45, "anim": "ultimate",
				"desc": "【奥义】把敌人倒进碗里的星空，80%几率【冰冻】，全体队友攻击条+20%。",
				"desc_en": "ULTIMATE: Pours an enemy into the starry bowl (80% Freeze); allies gain 20% Attack Bar.",
				"effects": [{"type": "debuff", "status": "freeze", "turns": 1, "chance": 80}, {"type": "atb_boost_allies", "amount": 20}]},
		],
		"upgrades": [
			{"id": "yb_oil", "name": "油滴", "name_en": "Oil Spot", "desc": "星屑必定附加【持续伤害】。", "desc_en": "Stardust always inflicts Continuous Damage.",
				"mods": [{"skill": 0, "effect_chance": 100}]},
			{"id": "yb_hare", "name": "兔毫", "name_en": "Hare's Fur", "desc": "兔毫乱流改为三次攻击。", "desc_en": "Hare's-Fur Surge strikes three times.",
				"mods": [{"skill": 1, "hits": 3}]},
			{"id": "yb_cosmos", "name": "盏中星河", "name_en": "Galaxy in a Cup", "desc": "盏中宇宙裂纹+60。", "desc_en": "Cosmos in a Cup deals +60 crack.",
				"mods": [{"skill": 2, "crack": 60}]},
			{"id": "yb_jian", "name": "建窑", "name_en": "Jian Kiln", "desc": "速度+10。", "desc_en": "SPD +10.",
				"mods": [{"stat": "spd", "add": 10}]},
		],
	},
}

const SPECIES_ORDER := ["chickencup", "rulotus", "sancaihorse", "childpillow", "tigerpillow", "generaljar", "phoenixvase", "yohenbowl"]

## Starting trios offered at the beginning of a run.
const STARTERS := [
	{"name": "木火相生", "name_en": "Wood Feeds Fire", "team": ["phoenixvase", "chickencup", "rulotus"],
		"desc": "水生木、木生火：凤耳瓶→鸡缸杯连成相生。", "desc_en": "Water feeds Wood feeds Fire: chain the Phoenix into the Rooster."},
	{"name": "守夜人", "name_en": "Night Watch", "team": ["generaljar", "childpillow", "tigerpillow"],
		"desc": "将军守门，孩儿枕金缮，老虎醒来再打。", "desc_en": "The General holds, the Child mends, the Tiger wakes up swinging."},
	{"name": "土生金", "name_en": "Earth Makes Metal", "team": ["sancaihorse", "yohenbowl", "rulotus"],
		"desc": "三彩马拉条，土生金、金生水，一路连下去。", "desc_en": "The Steed speeds everyone up: Earth, Metal, Water in a row."},
]


# --- Traits (羁绊) -----------------------------------------------------------------------
# Counted over the fielded team. Dynasty traits with a single member today are
# kept in data so the roster can grow (more Tang / Ming / Qing spirits later).
const TRAITS := {
	"song": {"name": "宋韵", "name_en": "Song Grace", "tiers": [2, 4],
		"desc": ["全队胎厚+25%", "全队受到的伤害-12%"], "desc_en": ["Team toughness +25%", "Team takes 12% less damage"]},
	"painted": {"name": "彩绘", "name_en": "Painted", "tiers": [2, 3],
		"desc": ["全队裂纹+20%", "全队裂纹+40%，击碎敌人时击碎者灵力+20"], "desc_en": ["Team crack +20%", "Team crack +40%; breaking an enemy gives the breaker 20 energy"]},
	"mono": {"name": "单色釉", "name_en": "Monochrome", "tiers": [2, 3],
		"desc": ["相生加成×1.3", "相生加成×1.3，每次相生为行动者恢复6%生命"], "desc_en": ["Chain bonus x1.3", "Chain bonus x1.3; each chain link heals the actor 6%"]},
	"wuxing": {"name": "五行", "name_en": "Five Phases", "tiers": [3, 4],
		"desc": ["3种元素：开局攻击条+15%", "4种元素：开局攻击条+30%"], "desc_en": ["3 elements: start with 15% Attack Bar", "4 elements: start with 30% Attack Bar"]},
	"tang": {"name": "盛唐", "name_en": "High Tang", "tiers": [2], "desc": ["全队速度+8"], "desc_en": ["Team SPD +8"]},
	"ming": {"name": "大明", "name_en": "Great Ming", "tiers": [2], "desc": ["全队暴击率+12%"], "desc_en": ["Team crit rate +12%"]},
	"qing": {"name": "康乾", "name_en": "Kangxi-Qianlong", "tiers": [2], "desc": ["全队最大生命+12%"], "desc_en": ["Team max HP +12%"]},
}
const TRAIT_ORDER := ["song", "painted", "mono", "wuxing", "tang", "ming", "qing"]


## Active trait tiers for a list of species ids: {trait_id: tier_index (0-based)}.
static func active_traits(species_ids: Array) -> Dictionary:
	var counts := {}
	var elements := {}
	for sid in species_ids:
		var sp: Dictionary = species_info(sid)
		elements[sp.element] = true
		for tg in sp.get("tags", []):
			counts[tg] = int(counts.get(tg, 0)) + 1
	counts["wuxing"] = elements.size()
	var out := {}
	for t in TRAITS:
		var tiers: Array = TRAITS[t].tiers
		var tier := -1
		for i in tiers.size():
			if int(counts.get(t, 0)) >= int(tiers[i]):
				tier = i
		if tier >= 0:
			out[t] = tier
	return out


static func trait_counts(species_ids: Array) -> Dictionary:
	var counts := {}
	var elements := {}
	for sid in species_ids:
		var sp: Dictionary = species_info(sid)
		elements[sp.element] = true
		for tg in sp.get("tags", []):
			counts[tg] = int(counts.get(tg, 0)) + 1
	counts["wuxing"] = elements.size()
	return counts


# --- Boss ----------------------------------------------------------------------------
const BOSS := {
	"name": "无缮之王", "name_en": "The Unmended", "element": Element.EARTH, "role": "首领", "role_en": "Boss",
	"tags": [], "toughness": 420,
	"origin": {"country": "？", "country_en": "?", "era": "不详", "era_en": "Unknown", "piece": "一只从未被修补的大罐", "piece_en": "A great jar that was never mended"},
	"lore": "所有拒绝被金子补好的碎片，聚成了它。", "lore_en": "Every shard that refused the gold gathered into this.",
	"base": {"hp": 5200, "atk": 960, "def": 540, "spd": 110, "crit_rate": 20, "crit_dmg": 60, "acc": 35, "res": 40},
	"leader": {},
	"passive": {"id": "unmended", "name": "拒绝修补", "name_en": "Refuses the Gold",
		"desc": "场上每有单位碎裂，攻击条+25%并恢复6%生命。生命低于50%时狂怒，攻击+30%。",
		"desc_en": "Whenever anything shatters, gains 25% Attack Bar and heals 6%. Enrages below 50% HP (+30% ATK)."},
	"skills": [
		{"name": "裂口", "name_en": "Jagged Maw", "cd": 0, "target": "enemy", "mult": 3.8, "hits": 1, "crack": 35, "anim": "melee",
			"desc": "用碎裂的瓶口撕咬，60%几率【防御破坏】2回合。", "desc_en": "Bites with its broken rim. 60% chance to Break Defense.",
			"effects": [{"type": "debuff", "status": "def_break", "turns": 2, "chance": 60}]},
		{"name": "碎瓷风暴", "name_en": "Shard Storm", "cd": 3, "target": "all_enemies", "mult": 1.4, "hits": 2, "crack": 30, "anim": "cast",
			"desc": "甩出身上的碎瓷两次攻击全体，50%几率【持续伤害】。", "desc_en": "Hurls its shards at everyone twice. 50% Continuous Damage.",
			"effects": [{"type": "debuff", "status": "dot", "turns": 2, "chance": 50}]},
		{"name": "万片归墟", "name_en": "Ten Thousand Fragments", "cd": 0, "target": "all_enemies", "mult": 3.0, "hits": 1, "crack": 45, "anim": "ultimate",
			"desc": "【奥义】所有碎片同时坠落，攻击全体并削减40%攻击条。", "desc_en": "ULTIMATE: Every fragment falls at once. Hits all and cuts Attack Bar by 40%.",
			"effects": [{"type": "atb_reduce", "amount": 40, "chance": 100}]},
	],
	"upgrades": [],
}


static func species_info(sid: String) -> Dictionary:
	return BOSS if sid == "boss" else SPECIES[sid]


static func upgrade_info(sid: String, uid: String) -> Dictionary:
	for u in species_info(sid).get("upgrades", []):
		if u.id == uid:
			return u
	return {}


## A species' skills with upgrade mods applied (deep copies; data stays untouched).
static func build_skills(sid: String, upgrades: Array) -> Array:
	var skills: Array = species_info(sid).skills.duplicate(true)
	for uid in upgrades:
		var up := upgrade_info(sid, uid)
		for m in up.get("mods", []):
			if not m.has("skill"):
				continue
			var sk: Dictionary = skills[int(m.skill)]
			if m.has("hits"):
				sk.hits = int(m.hits)
			if m.has("mult"):
				sk.mult = float(m.mult)
			if m.has("mult_mul"):
				sk.mult = float(sk.mult) * float(m.mult_mul)
			if m.has("cd"):
				sk.cd = maxi(1, int(sk.cd) + int(m.cd))
			if m.has("crack"):
				sk.crack = int(sk.crack) + int(m.crack)
			if m.has("effect_chance"):
				for e in sk.effects:
					if e.type == "debuff":
						e.chance = int(m.effect_chance)
			if m.has("heal_add"):
				for e in sk.effects:
					if e.type == "heal_allies":
						e.pct = int(e.pct) + int(m.heal_add)
			if m.has("atb_boost"):
				for e in sk.effects:
					if e.type == "atb_boost_allies":
						e.amount = int(m.atb_boost)
			if m.has("atb_reduce"):
				for e in sk.effects:
					if e.type == "atb_reduce":
						e.amount = int(m.atb_reduce)
			if m.has("add_effect"):
				sk.effects.append(m.add_effect.duplicate(true))
	return skills


# --- Scars (earned when a shattered creature is mended) ---------------------------------
const SCARS := {
	"res_0": {"name": "耐金纹", "name_en": "Metalproof Seam", "desc": "受到金属性伤害-30%", "desc_en": "-30% damage from Metal"},
	"res_1": {"name": "耐木纹", "name_en": "Woodproof Seam", "desc": "受到木属性伤害-30%", "desc_en": "-30% damage from Wood"},
	"res_2": {"name": "耐水纹", "name_en": "Waterproof Seam", "desc": "受到水属性伤害-30%", "desc_en": "-30% damage from Water"},
	"res_3": {"name": "耐火纹", "name_en": "Fireproof Seam", "desc": "受到火属性伤害-30%", "desc_en": "-30% damage from Fire"},
	"res_4": {"name": "耐土纹", "name_en": "Earthproof Seam", "desc": "受到土属性伤害-30%", "desc_en": "-30% damage from Earth"},
	"crit_proof": {"name": "韧胎", "name_en": "Tough Body", "desc": "不会受到暴击", "desc_en": "Cannot be critically hit"},
	"dot_proof": {"name": "封釉", "name_en": "Sealed Glaze", "desc": "免疫持续伤害", "desc_en": "Immune to Continuous Damage"},
	"cc_proof": {"name": "定心", "name_en": "Steady Core", "desc": "免疫眩晕与冰冻", "desc_en": "Immune to Stun and Freeze"},
}
const MEND_BONUS := 0.12      # +12% HP/ATK/DEF per gold seam
const MAX_MENDS := 3          # the 4th shatter turns a creature to dust


static func scar_for(cause: Dictionary) -> String:
	if cause.get("dot", false):
		return "dot_proof"
	if cause.get("cc", false):
		return "cc_proof"
	if cause.get("crit", false):
		return "crit_proof"
	return "res_%d" % clampi(int(cause.get("element", 0)), 0, 4)


# --- Glaze shards (run relics) -----------------------------------------------------------
const RELICS := {
	"thermal_shock": {"name": "冷热骤变", "name_en": "Thermal Shock", "rarity": 1,
		"desc": "击碎敌人时，额外造成其最大生命15%的伤害。", "desc_en": "Breaking an enemy also deals 15% of its max HP."},
	"linked_kilns": {"name": "连窑", "name_en": "Linked Kilns", "rarity": 1,
		"desc": "每段相生连携，行动者额外获得15灵力。", "desc_en": "Each chain link gives the actor 15 extra energy."},
	"shard_edge": {"name": "碎瓷锋", "name_en": "Shard Edge", "rarity": 1,
		"desc": "我方有单位碎裂时，其余队友攻击条+30%并获得【攻击强化】2回合。",
		"desc_en": "When an ally shatters, the others gain 30% Attack Bar and Attack Up for 2 turns."},
	"golden_heart": {"name": "金缮之心", "name_en": "Golden Heart", "rarity": 2,
		"desc": "我方单位每有一道金缝，伤害+10%。", "desc_en": "Allies deal +10% damage per gold seam."},
	"first_glaze": {"name": "先手釉", "name_en": "First Glaze", "rarity": 0,
		"desc": "战斗开始时，我方攻击条+40%。", "desc_en": "Allies start each battle with 40% Attack Bar."},
	"listen_crack": {"name": "听裂", "name_en": "Listening for Cracks", "rarity": 0,
		"desc": "对裂纹过半的敌人伤害+20%。", "desc_en": "+20% damage to enemies more than half cracked."},
	"five_phases": {"name": "五行轮转", "name_en": "Turning Phases", "rarity": 2,
		"desc": "相生每多一段，伤害加成额外+10%。", "desc_en": "Each chain link adds another +10% damage."},
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
		"desc": "崩裂的敌人受到的伤害+50%（原+30%）。", "desc_en": "Broken enemies take +50% damage (was +30%)."},
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


## Final stats. `upgrades` may add SPD / toughness; `traits` is active_traits() of the team.
static func compute_stats(species_id: String, level: int, mends: int = 0, hp_mult: float = 1.0, leader: Dictionary = {},
		upgrades: Array = [], traits: Dictionary = {}) -> Dictionary:
	var sp: Dictionary = species_info(species_id)
	var base: Dictionary = sp.base
	var lm := level_mult(level) * (1.0 + MEND_BONUS * mends)
	var pct := {"hp": 0.0, "atk": 0.0, "def": 0.0, "spd": 0.0}
	var flat := {"crit_rate": 0.0, "acc": 0.0, "res": 0.0, "spd": 0.0}
	var tough_mult := 1.0
	if not leader.is_empty():
		var st: String = leader.stat
		if st.ends_with("_pct"):
			pct[st.trim_suffix("_pct")] += float(leader.value)
		elif flat.has(st):
			flat[st] += float(leader.value)
	for uid in upgrades:
		for m in upgrade_info(species_id, uid).get("mods", []):
			if m.has("stat"):
				flat[m.stat] = float(flat.get(m.stat, 0.0)) + float(m.add)
			if m.has("toughness_mult"):
				tough_mult *= float(m.toughness_mult)
	if traits.has("song"):
		tough_mult *= 1.25
	if traits.has("tang"):
		flat.spd += 8.0
	if traits.has("ming"):
		flat.crit_rate += 12.0
	if traits.has("qing"):
		pct.hp += 12.0
	var out := {}
	for k in ["hp", "atk", "def"]:
		out[k] = roundf(float(base[k]) * lm * (1.0 + pct[k] / 100.0))
	out.hp = roundf(out.hp * hp_mult)
	out["spd"] = roundf(float(base.spd) * (1.0 + pct.spd / 100.0) + flat.spd)
	out["crit_rate"] = minf(100.0, float(base.crit_rate) + flat.crit_rate)
	out["crit_dmg"] = float(base.crit_dmg)
	out["acc"] = float(base.acc) + flat.acc
	out["res"] = minf(100.0, float(base.res) + flat.res)
	out["toughness"] = roundf(float(sp.get("toughness", 100)) * tough_mult)
	return out


static func passive_value(species_id: String, upgrades: Array, default_value: float) -> float:
	var v := default_value
	for uid in upgrades:
		for m in upgrade_info(species_id, uid).get("mods", []):
			if m.has("passive_value"):
				v = float(m.passive_value)
	return v


# --- Map & events ------------------------------------------------------------------------
const NODE_TYPES := {
	"start": {"glyph": "启", "glyph_en": "S", "name": "启程", "name_en": "Start", "color": Color(0.95, 0.9, 0.8)},
	"battle": {"glyph": "战", "glyph_en": "F", "name": "战斗", "name_en": "Battle", "color": Color(0.85, 0.3, 0.25)},
	"elite": {"glyph": "精", "glyph_en": "E", "name": "精英", "name_en": "Elite", "color": Color(0.75, 0.2, 0.55)},
	"kiln": {"glyph": "窑", "glyph_en": "K", "name": "窑炉", "name_en": "Kiln", "color": Color(1.0, 0.55, 0.2)},
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
