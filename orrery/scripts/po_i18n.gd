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
	const ZH := ["火", "水", "风", "光", "暗"]
	const EN := ["Fire", "Water", "Wind", "Light", "Dark"]
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
	"legend": ["裂变表", "Reactions"],
	"console": ["控制台 F1", "Console F1"],
	"map_hint": ["点击发光的节点前进。走过的路会被金缮成金线。", "Click a glowing node to travel. Your path is mended in gold."],
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
	"battle_hint": ["点击目标释放 · [1][2][3] 切换技能 · [空格] 自动选目标 · 绿▲克制 红▼被克",
		"Click a target · [1][2][3] switch skill · [Space] auto-target · green ▲ advantage, red ▼ disadvantage"],
	"ultimate_ready": ["★奥义", "★ULT"],
	"mark": ["%s印", "%s mark"],
	"boss_tag": ["  ★首领", "  ★BOSS"],
	"preview_dmg": ["预计伤害 [b]%d[/b] · 暴击 [b]%d[/b]（暴击率 %d%%）", "Expected [b]%d[/b] · crit [b]%d[/b] (%d%% crit)"],
	"aff_down": ["[color=#ff6a5a]▼被克制（30%偏斜）[/color]", "[color=#ff6a5a]▼Disadvantage (30% glancing)[/color]"],
	"aff_none": ["[color=#e8d27a]◆无克制[/color]", "[color=#e8d27a]◆Neutral[/color]"],
	"aff_up": ["[color=#6dff8a]▲克制 +30%伤害[/color]", "[color=#6dff8a]▲Advantage +30% damage[/color]"],
	"can_kill": ["  [color=#ff5050][b]可击杀[/b][/color]", "  [color=#ff5050][b]LETHAL[/b][/color]"],
	"will_react": ["\n[color=#ffcc55]将触发元素裂变【%s】[/color]：%s", "\n[color=#ffcc55]Triggers reaction: %s[/color] — %s"],
	"land_chance": ["\n%s 实际命中率 ≈ %d%%%s", "\n%s lands ≈ %d%%%s"],
	"target_immune": ["（目标免疫）", " (target immune)"],
	"fission_title": ["元素裂变 Element Fission", "Element Fission 元素裂变"],
	"fission_intro": ["伤害技能会给目标留下施法者的[b]元素印记[/b]；用[b]不同元素[/b]命中带印记的目标，会消耗印记触发裂变：",
		"Damaging skills leave the caster's [b]element Mark[/b]. Hitting a marked target with a [b]different element[/b] consumes the Mark and triggers:"],
	"fission_other": ["火/水/风", "Fire/Water/Wind"],
	"affinity_line": ["\n克制：%s→%s→%s→%s，%s⇄%s", "\nAdvantage: %s→%s→%s→%s, %s⇄%s"],
	"floor_banner": ["第 %d 层", "Floor %d"],
	"elite_banner": ["精英之战", "Elite Battle"],
	"boss_banner": ["无缮之王", "The Unmended"],
	"fission_banner": ["元素裂变 · %s", "Element Fission · %s"],
	"extra_turn": ["额外回合!", "Extra turn!"],
	"crit": ["暴击!", "CRIT!"],
	"glancing": ["偏斜", "Glancing"],
	"crushing": ["碾压!", "Crushing!"],
	"advantage": ["克制▲", "Advantage▲"],
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
	"log_react": ["[color=#ffcc55]★ 元素裂变【%s】[/color] %s+%s → %s", "[color=#ffcc55]★ Reaction: %s[/color] %s+%s → %s"],
	"log_leader": ["[color=#e6b35f]队长技[/color] %s：全队%s", "[color=#e6b35f]Leader[/color] %s: team %s"],
	"log_tip": ["[color=#8fb8ff]提示[/color]：用不同元素攻击带[b]印记[/b]的敌人触发[b]元素裂变[/b]", "[color=#8fb8ff]Tip[/color]: hit a [b]marked[/b] enemy with a different element to trigger [b]Element Fission[/b]"],
	# rewards & nodes
	"continue": ["继续", "Continue"],
	"skip": ["跳过", "Skip"],
	"reward_title": ["战斗胜利", "Victory"],
	"reward_gold": ["获得 %d 金", "+%d gold"],
	"reward_level": ["存活的瓷偶升 1 级，并恢复20%生命", "Survivors gain 1 level and recover 20% HP"],
	"reward_shattered": ["[color=#ff9090]%s 碎裂了——去金缮坊把它补起来。[/color]", "[color=#ff9090]%s shattered. Take it to a Mending Hall.[/color]"],
	"reward_dust": ["[color=#ff5050]%s 第四次碎裂，化为瓷尘，永远离开了。[/color]", "[color=#ff5050]%s broke a fourth time and turned to dust. It is gone.[/color]"],
	"pick_relic": ["选择一块釉片", "Choose a glaze shard"],
	"kiln_title": ["窑炉 · 招募", "Kiln · Recruit"],
	"kiln_text": ["窑火正旺。选一只刚出窑的瓷偶加入队伍（最多4只，满了就替换一只）。", "The kiln is roaring. Pick a freshly fired figure to join (max 4; replace one if full)."],
	"kiln_replace": ["队伍已满：选择要替换的瓷偶", "Team is full: choose a figure to replace"],
	"mend_title": ["金缮坊", "Mending Hall"],
	"mend_text": ["把碎掉的瓷偶用金子补起来。每修一次多一道金缝：生命、攻击、防御 +12%，并按碎裂的原因获得一个伤痕特性。修满 3 次后再碎，就会化为瓷尘。",
		"Mend shattered figures with gold. Each repair adds a seam: +12% HP/ATK/DEF, plus a scar trait based on how it broke. After 3 seams, the next break turns it to dust."],
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
	"run_summary": ["抵达第 %d 层 · %d 场战斗 · %d 次元素裂变 · %d 道金缝", "Reached floor %d · %d battles · %d reactions · %d gold seams"],
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
