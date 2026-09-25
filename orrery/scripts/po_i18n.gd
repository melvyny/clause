extends RefCounted
## Goldmend :: bilingual text (中文 / English).
## - UI strings live in the `UI` table below: s("key") or s("key", [args]).
## - Data dictionaries carry `field` (zh) and `field_en`; read them with f(dict, "field").
## The chosen language is stored in user://goldmend_settings.cfg.

const SETTINGS_PATH := "user://goldmend_settings.cfg"
const LANGS := ["zh", "en"]

static var lang := "zh"


static func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		var l: String = cfg.get_value("general", "lang", "zh")
		if l in LANGS:
			lang = l


static func set_lang(l: String) -> void:
	lang = l
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("general", "lang", l)
	cfg.save(SETTINGS_PATH)


static func toggle() -> void:
	set_lang("en" if lang == "zh" else "zh")


static func en() -> bool:
	return lang == "en"


## Localised field of a data dictionary (falls back to Chinese).
static func f(d: Dictionary, field: String) -> String:
	if lang == "en" and d.has(field + "_en"):
		return str(d[field + "_en"])
	return str(d.get(field, ""))


static func element(e: int) -> String:
	const ZH := ["金", "木", "水", "火", "土"]
	const EN := ["Metal", "Wood", "Water", "Fire", "Earth"]
	return EN[e] if lang == "en" else ZH[e]


static func s(key: String, args: Array = []) -> String:
	var row: Array = UI.get(key, [key, key])
	var t: String = row[1] if lang == "en" else row[0]
	return t % args if args.size() > 0 else t


const UI := {
	# title / meta
	"title": ["金 缮", "GOLDMEND"],
	"subtitle": ["碎了，就用金子补起来。", "When it breaks, mend it with gold."],
	"title_small": ["金缮 GOLDMEND", "GOLDMEND 金缮"],
	"start_run": ["开始旅程", "Begin the Journey"],
	"lang_btn": ["English", "中文"],
	"codex": ["器灵图鉴", "Codex"],
	"codex_title": ["器灵图鉴 · 每一只都是真实存在的文物", "Vessel Spirits · every one is a real museum piece"],
	"codex_hint": ["点击一只器灵，查看它的原型文物与故事。", "Click a spirit to see the real piece it comes from and its story."],
	"back": ["返回", "Back"],
	"quit": ["退出", "Quit"],
	"story": ["星空是一只巨大的青花瓷盘。它碎过一次，被人用金子补好，金线就是星轨。\n如今，没被补好的碎片聚成了「无缮之王」。\n你是缮星师。带上你的瓷偶，沿着裂痕走到盘心。",
		"The night sky is a great blue-and-white plate. It broke once, and someone mended it with gold; the gold seams became the star paths.\nNow the pieces that were never mended have gathered into The Unmended.\nYou are a Mender. Take your porcelain figures and follow the cracks to the heart of the plate."],
	"choose_starter": ["选择你的起始瓷偶", "Choose your starting figures"],
	# top bar
	"gold": ["金 %d", "Gold %d"],
	"floor": ["第 %d / %d 层", "Floor %d / %d"],
	"relics": ["釉片", "Glaze Shards"],
	"no_relics": ["（还没有釉片）", "(no glaze shards yet)"],
	"auto": ["自动", "Auto"],
	"auto_on": ["自动 ON", "Auto ON"],
	"speed": ["速度 x%d", "Speed x%d"],
	"legend": ["规则：五行 · 裂纹 · 相生 · 意图", "Rules: Five Phases · crack · chains · intents"],
	"log": ["战斗记录", "Combat log"],
	"statuses": ["状态效果", "Status effects"],
	"controls": ["操作", "Controls"],
	"cd_turns": ["冷却 %d 回合", "Cooldown %d"],
	"console": ["控制台 F1", "Console F1"],
	"map_hint": ["选择一个发光的节点前进", "Choose a glowing node"],
	"not_reachable": ["（现在还到不了）", "(not reachable yet)"],
	"node_battle": ["普通战斗，胜利后获得金子和一块釉片。", "A fight. Win gold and a glaze shard."],
	"node_elite": ["更强的敌人，奖励更好的釉片。", "Tougher foes, better shards."],
	"node_kiln": ["招募一只新的器灵。", "Recruit a new spirit."],
	"node_mend": ["用金子修补碎裂的器灵，或全队休整。", "Mend shattered spirits with gold, or rest."],
	"node_shop": ["用金子购买釉片。", "Buy glaze shards with gold."],
	"node_event": ["未知的奇遇。", "Something unexpected."],
	"node_boss": ["无缮之王在盘心等你。", "The Unmended waits at the heart of the plate."],
	"node_start": ["旅程的起点。", "Where the journey began."],
	"seams": ["金缝 %d/%d", "Seams %d/%d"],
	"shattered": ["已碎裂", "Shattered"],
	"lv": ["Lv%d", "Lv%d"],
	# battle hud
	"turn_order": ["行动预测 ▸", "Turn order ▸"],
	"basic": ["普攻", "Basic"],
	"ready_cd": ["就绪 · 冷却%d", "Ready · CD %d"],
	"on_cd": ["冷却 %d 回合", "Cooldown %d"],
	"ult_energy": ["奥义 · 灵力 %d/%d", "Ultimate · %d/%d"],
	"passive": ["被动", "Passive"],
	"target_enemy": ["单体敌人", "Single enemy"],
	"target_all_enemies": ["全体敌人", "All enemies"],
	"target_all_allies": ["全体队友", "All allies"],
	"battle_hint": ["点击目标释放 · [1][2][3] 切换技能（群体技能再按一次释放） · [空格] 自动选目标 · 头顶箭头：绿▲相克 黄◆无克制 红▼被克 · 悬停任何图标或角色查看说明",
		"Click a target · [1][2][3] switch skill (press an area skill again to cast) · [Space] auto-target · arrows: green ▲ you overcome it, yellow ◆ neutral, red ▼ it overcomes you · hover any icon or unit for details"],
	"ultimate_ready": ["★奥义", "★ULT"],
	"boss_tag": ["  ★首领", "  ★BOSS"],
	"preview_dmg": ["预计伤害 [b]%d[/b] · 暴击 [b]%d[/b]（暴击率 %d%%）", "Expected [b]%d[/b] · crit [b]%d[/b] (%d%% crit)"],
	"aff_down": ["[color=#ff6a5a]▼被克（伤害-15%，裂纹-30%）[/color]", "[color=#ff6a5a]▼Overcome (-15% damage, -30% crack)[/color]"],
	"aff_none": ["[color=#e8d27a]◆无克制[/color]", "[color=#e8d27a]◆Neutral[/color]"],
	"aff_up": ["[color=#6dff8a]▲相克（伤害+25%，裂纹+50%）[/color]", "[color=#6dff8a]▲Overcomes (+25% damage, +50% crack)[/color]"],
	"can_kill": ["  [color=#ff5050][b]可击杀[/b][/color]", "  [color=#ff5050][b]LETHAL[/b][/color]"],
	"preview_crack": ["裂纹 [b]+%d[/b]（%d / %d）", "Crack [b]+%d[/b] (%d / %d)"],
	"preview_broken": ["[color=#ff9070]目标已崩裂：受到伤害+30%[/color]", "[color=#ff9070]Target is broken: takes +30% damage[/color]"],
	"preview_chain": ["[color=#ffd060]相生 ×%d：伤害+%d%%[/color]", "[color=#ffd060]Chain ×%d: +%d%% damage[/color]"],
	"will_break": ["\n[color=#ffcc55][b]将崩裂 · %s[/b][/color] %s", "\n[color=#ffcc55][b]Will BREAK · %s[/b][/color] %s"],
	"will_interrupt": ["\n[color=#ffe08a]并打断它的蓄力招式[/color]", "\n[color=#ffe08a]…and interrupt its telegraphed move[/color]"],
	"land_chance": ["\n%s 实际命中率 ≈ %d%%%s", "\n%s lands ≈ %d%%%s"],
	"target_immune": ["（目标免疫）", " (target immune)"],
	"rules_wuxing_title": ["五行 · 每种元素都是一门瓷器工艺", "Five Phases · each element is a porcelain craft"],
	"rules_ke": ["[b]相克[/b]（伤害+25%%，裂纹+50%%）：%s克%s，%s克%s，%s克… 一圈五个", "[b]Overcoming[/b] (+25%% damage, +50%% crack): %s > %s > %s > %s > %s > back to the start"],
	"rules_sheng": ["[b]相生[/b]（连携）：%s生%s生%s生%s生%s生… 一圈五个", "[b]Generating[/b] (chains): %s feeds %s feeds %s feeds %s feeds %s, and round again"],
	"rules_crack_title": ["裂纹与崩裂", "Crack and Break"],
	"rules_crack": ["每次攻击都会在目标身上留下[b]裂纹[/b]（名字下方的白条）。裂纹达到[b]胎厚[/b]时目标[b]崩裂[/b]：攻击条清零、蓄力招式被打断、受到伤害+30%%直到它下次行动。治疗技能会先用金子[b]修补裂纹[/b]。崩裂还会按[b]击碎者的元素[/b]触发窑变：",
		"Every attack leaves [b]crack[/b] (the white bar under a name). When crack reaches the target's [b]toughness[/b] it [b]breaks[/b]: its Attack Bar empties, its telegraphed move is interrupted, and it takes +30%% damage until it acts again. Healing skills [b]mend crack[/b] first. A break also fires a kiln effect set by the [b]breaker's element[/b]:"],
	"rules_chain_title": ["相生连携", "Generating Chains"],
	"rules_chain": ["如果同一方[b]上一个行动的队友[/b]的元素生你的元素（比如木→火），你这次行动就是一段[b]相生[/b]：每段伤害+15%%、裂纹+25%%、灵力+10，最多5段。顶部行动预测里带金环的头像就是会连上的行动——用拉条和减速去排出顺序。",
		"If the [b]previous ally to act[/b] on your side has an element that feeds yours (Wood → Fire), your action is a [b]chain link[/b]: +15%% damage, +25%% crack and +10 energy per link, up to 5. Gold-ringed portraits in the turn forecast will chain; use Attack Bar boosts and slows to line them up."],
	"rules_intent_title": ["敌人意图", "Enemy Intents"],
	"rules_intent": ["敌人头顶显示它[b]下一步要做什么、打谁[/b]。大图标是技能或奥义：在它行动前把它打到崩裂，就能打断成普通攻击。",
		"Above each enemy is [b]what it will do next and to whom[/b]. A large icon is a skill or ultimate: break the enemy before it acts to downgrade it to a basic attack."],
	"tip_crack": ["裂纹 %d / %d", "Crack %d / %d"],
	"tip_broken": ["[color=#ff9070][b]崩裂[/b]：受到伤害+30%%[/color]", "[color=#ff9070][b]BROKEN[/b]: takes +30%% damage[/color]"],
	"tip_intent": ["[color=#ff9a8a]意图[/color]：%s → %s", "[color=#ff9a8a]Intent[/color]: %s → %s"],
	"traits": ["羁绊", "Traits"],
	"floor_banner": ["第 %d 层", "Floor %d"],
	"elite_banner": ["精英之战", "Elite Battle"],
	"boss_banner": ["无缮之王", "The Unmended"],
	"chain_pop": ["相生 ×%d", "Chain ×%d"],
	"broken": ["崩裂", "BREAK"],
	"interrupted": ["打断!", "Interrupted!"],
	"shield_pop": ["护盾 +%d", "Shield +%d"],
	"extra_turn": ["额外回合!", "Extra turn!"],
	"crit": ["暴击!", "CRIT!"],
	"advantage": ["相克▲", "Overcome▲"],
	"resist": ["抵抗!", "Resisted!"],
	"immune": ["免疫", "Immune"],
	"cleansed": ["净化", "Cleansed"],
	"atb_up": ["攻击条+%d%%", "ATB +%d%%"],
	"atb_down": ["攻击条-%d%%", "ATB -%d%%"],
	"frozen_skip": ["冰冻中", "Frozen"],
	"stunned_skip": ["眩晕中", "Stunned"],
	"reassemble": ["金粉重组!", "Reassembled!"],
	"victory": ["胜 利", "VICTORY"],
	"defeat": ["败 北", "DEFEAT"],
	"log_uses": ["%s 使用 [b]%s[/b]", "%s uses [b]%s[/b]"],
	"log_shatter": ["[color=#ff8080]%s 碎裂了[/color]", "[color=#ff8080]%s shattered[/color]"],
	"log_skip": ["%s 无法行动，跳过回合", "%s can't act and loses the turn"],
	"log_extra": ["%s 获得[b]额外回合[/b]", "%s takes an [b]extra turn[/b]"],
	"log_chain": ["[color=#ffd060]相生[/color] %s生%s：%s 连携×%d（伤害+%d%%）", "[color=#ffd060]Chain[/color] %s feeds %s: %s link ×%d (+%d%% damage)"],
	"log_break": ["[color=#ffcc55]★ %s 崩裂 · %s[/color] %s", "[color=#ffcc55]★ %s BREAKS · %s[/color] %s"],
	"log_leader": ["[color=#e6b35f]队长技[/color] %s：全队%s", "[color=#e6b35f]Leader[/color] %s: team %s"],
	"log_tip": ["[color=#8fb8ff]提示[/color]：用相克的元素把敌人打到[b]崩裂[/b]，可以打断它的蓄力招式", "[color=#8fb8ff]Tip[/color]: overcome an enemy's element to [b]break[/b] it and interrupt its telegraphed move"],
	# rewards & nodes
	"continue": ["继续", "Continue"],
	"skip": ["跳过", "Skip"],
	"reward_title": ["战斗胜利", "Victory"],
	"reward_gold": ["获得 %d 金", "+%d gold"],
	"reward_level": ["存活的瓷偶升 1 级，并恢复20%生命", "Survivors gain 1 level and recover 20% HP"],
	"reward_shattered": ["[color=#ff9090]%s 碎裂了——去金缮坊把它补起来。[/color]", "[color=#ff9090]%s shattered. Take it to a Mending Hall.[/color]"],
	"reward_dust": ["[color=#ff5050]%s 第四次碎裂，化为瓷尘，永远离开了。[/color]", "[color=#ff5050]%s broke a fourth time and turned to dust. It is gone.[/color]"],
	"pick_relic": ["选择一块釉片", "Choose a glaze shard"],
	"pick_reward": ["选择一项：器艺（强化一只器灵）或釉片（改写规则）", "Choose one: a craft technique (upgrade a spirit) or a glaze shard (bend the rules)"],
	"kiln_refire": ["或者回炉重烧：给一只器灵学会新的器艺", "Or refire one of yours: teach a spirit a new craft technique"],
	"upgrades_title": ["器艺（每只4种，在战斗奖励、窑炉、商店获得）", "Craft techniques (4 each; from rewards, kilns and shops)"],
	"toughness": ["胎厚 %d", "Toughness %d"],
	"kiln_title": ["窑炉 · 招募", "Kiln · Recruit"],
	"kiln_text": ["窑火正旺。选一只刚出窑的瓷偶加入队伍（最多4只，满了就替换一只）。", "The kiln is roaring. Pick a freshly fired figure to join (max 4; replace one if full)."],
	"kiln_replace": ["队伍已满：选择要替换的瓷偶", "Team is full: choose a figure to replace"],
	"mend_title": ["金缮坊", "Mending Hall"],
	"mend_text": ["把碎掉的瓷偶用金子补起来。每修一次多一道金缝：生命、攻击、防御 +12%，并按碎裂的原因获得一个伤痕特性。修满 3 次后再碎，就会化为瓷尘。",
		"Mend shattered figures with gold. Each repair adds a seam: +12% HP/ATK/DEF, plus a scar trait based on how it broke. After 3 seams, the next break turns it to dust."],
	"mend_short": ["修补 = 金缝 +1，变强并获得伤痕特性（悬停查看详情）", "Mend = +1 gold seam, stronger, plus a scar trait (hover for details)"],
	"mend_btn": ["金缮修补（%d 金）", "Mend (%d gold)"],
	"rest_btn": ["全队休整：恢复40%生命（免费）", "Rest: all heal 40% (free)"],
	"leave": ["离开", "Leave"],
	"mended_banner": ["金缮完成", "Mended"],
	"new_scar": ["获得伤痕：%s — %s", "New scar: %s — %s"],
	"shop_title": ["釉片商店", "Glaze Shop"],
	"shop_text": ["货架上摆着会改写规则的釉片。", "Shelves of glaze shards that bend the rules."],
	"buy": ["购买 %d 金", "Buy %d gold"],
	"sold": ["已售出", "Sold"],
	"heal_potion": ["修复釉浆：全队恢复50%%（%d 金）", "Repair slip: all heal 50%% (%d gold)"],
	"not_enough": ["金子不够", "Not enough gold"],
	"run_won_title": ["星盘已补全", "The Plate Is Whole"],
	"run_won_text": ["无缮之王碎成了千万片。你把它们一片一片捡起来，用金子补好。\n它终于成了星空的一部分。", "The Unmended breaks into ten thousand pieces. You gather them one by one and mend them with gold.\nAt last it becomes part of the sky."],
	"run_lost_title": ["旅程中断", "The Journey Ends"],
	"run_lost_text": ["你的瓷偶全都碎了。但碎片还在——下一次，也许能走得更远。", "All your figures have broken. But the pieces remain. Next time, perhaps further."],
	"run_summary": ["抵达第 %d 层 · %d 场战斗 · %d 次崩裂 · %d 段相生 · %d 道金缝", "Reached floor %d · %d battles · %d breaks · %d chain links · %d gold seams"],
	"new_run": ["再来一局", "New Run"],
	"your_team": ["你的队伍", "Your team"],
	"joined": ["%s 加入了队伍！", "%s joined the team!"],
	"no_fighters": ["没有能战斗的瓷偶了", "No figures left to fight"],
	# console
	"c_title": ["▣ 开发者控制台 (F1 / ~)", "▣ DEV CONSOLE (F1 / ~)"],
	"c_win": ["瞬间获胜", "Win battle instantly"],
	"c_kill": ["击杀全部敌人", "Kill all enemies"],
	"c_nocd": ["无限冷却 + 满灵力", "Infinite cooldowns + energy"],
	"c_maxatb": ["我方满攻击条", "Max ATB always (allies)"],
	"c_auto": ["自动战斗 AI", "AI auto-battle"],
	"c_speed": ["%dx 倍速", "%dx speed"],
	"c_heal": ["我方全体回满", "Heal team"],
	"c_gold": ["+100 金", "+100 gold"],
	"c_relic": ["获得随机釉片", "Random glaze shard"],
	"c_mend": ["修好所有碎裂瓷偶", "Mend all shattered"],
	"c_lang": ["切换语言 中文/English", "Toggle language 中文/English"],
}
