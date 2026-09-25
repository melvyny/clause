# 金缮 Goldmend · 战斗与成长设计 / Combat & Progression Design

> 目标：战斗规则本身就来自瓷器工艺，而不是"换了瓷器皮的魔灵召唤"。
> Goal: the rules themselves come from how porcelain is made, so it is not a monster battler with a porcelain skin.

本文件记录规则、公式、平衡目标、模拟结果、内容成本和扩展计划。改数值时先改 `orrery/scripts/po_data.gd`，再跑 `--gm-sim` 对照本文件的目标。
This file holds the rules, formulas, balance targets, simulation results, content cost and expansion plan. Change numbers in `orrery/scripts/po_data.gd`, then run `--gm-sim` and compare against the targets here.

---

## 1. 核心循环 · The combat loop in one sentence

**用相克的元素把敌人打出裂纹 → 在它放大招之前打到崩裂 → 用相生的出手顺序把伤害和裂纹叠上去 → 用治疗把自己的裂纹补上。**
**Overcome an enemy's element to crack it → break it before its telegraphed move lands → order your turns so each element feeds the next → mend your own cracks with healing.**

The ATB turn order (from Summoners War) is kept, with three systems on top. Each system answers "what should I do this turn?" with a real choice:

| 系统 System | 瓷器依据 Porcelain grounding | 玩家决策 Player decision |
|---|---|---|
| 五行相克 Overcoming | 金木水火土 = 金缮、草木灰釉、钴料/天青、窑火、胎土 · gilding, plant-ash glaze, cobalt, kiln fire, clay body | 打谁 · who to hit |
| 裂纹 / 崩裂 Crack & Break | 胎厚、开片、冷热骤变 · body thickness, crazing, thermal shock | 先打断谁 · who to break first |
| 相生连携 Chains | 一件瓷器要经过 土→金→水→木→火 多道工序 · a pot passes through many crafts in order | 出手顺序、拉条 · turn order and ATB |
| 敌人意图 Intents | 窑变前的征兆 · signs before a kiln transformation | 防守还是抢断 · defend or interrupt |
| 金缮 Mending | 碎了用金子补 · kintsugi | 冒险还是保守 · how much risk to take |

## 2. 五行 · Five Phases

| 元素 | 工艺 Craft | 器灵 Spirits | 崩裂窑变 Break effect |
|---|---|---|---|
| 金 Metal | 金缮与金彩 · gold repair, gilding | 孩儿枕、曜变盏 | 金缮：击碎方全队获得 12% 最大生命护盾 · team shield 12% |
| 木 Wood | 草木灰釉（青瓷） · plant-ash celadon glaze | 凤耳瓶 | 灰釉：击碎方全队恢复 8% · team heal 8% |
| 水 Water | 青花钴料、天青釉 · cobalt, sky-blue glaze | 汝窑莲碗、将军罐 | 冷缩：目标迟缓 2 回合（速度 -30%） · Slow 2 turns |
| 火 Fire | 窑火、铜红 · kiln fire, copper red | 鸡缸杯、虎枕 | 起泡：目标 2 层持续伤害 · 2× Continuous Damage |
| 土 Earth | 胎土、陶 · clay body, earthenware | 三彩马 | 塌陷：目标防御破坏 2 回合 · Defense Break 2 turns |

- **相克 Overcoming** 金克木 → 木克土 → 土克水 → 水克火 → 火克金: damage ×1.25, crack ×1.5. The reverse is damage ×0.85, crack ×0.7.
- **相生 Generating** 木生火 → 火生土 → 土生金 → 金生水 → 水生木: drives chains (§4).
- There is no "glancing" RNG. Advantage changes numbers you can see in the preview.

Why five instead of fire/water/wind/light/dark: the old triangle plus a pair only told you who to hit. The five-phase wheel gives two different relations (overcoming for targets, generating for turn order), and every element maps to a real craft.

## 3. 裂纹与崩裂 · Crack and Break

- Every damaging skill has a `crack` value: the total crack it puts on each target, split across its hits.
- Every figure has **toughness (胎厚)**: chicken cup 90, phoenix vase 80 (thin-bodied), General Jar 150 (thick-walled), boss 320.
- At full crack the figure **breaks (崩裂)**:
  1. Its Attack Bar is knocked back by 35%. An earlier build reset it to 0; enemies that broke fragile spirits right before they acted then denied them almost every turn.
  2. If it is an enemy with a telegraphed skill or ultimate, the move is **interrupted** and becomes a basic attack.
  3. It takes **+30% damage** until its next turn starts. At that point its crack resets to 0.
  4. The breaker's element fires a **kiln effect (窑变)** (table above).
- **Healing skills mend crack** (-30 per heal effect), so a healer protects the team from breaks as well as from damage.
- The glaze shader shows it: the kintsugi seams glow brighter as crack builds and burn fully gold while broken.

Crack formula per hit:

```
crack = skill.crack / hits
      × (1.5 overcoming | 0.7 overcome | 1.0)
      × (1 + 0.25 × chain × (1.3 if Monochrome))
      × (1.2 / 1.4 with Painted 2 / 3)
```

## 4. 相生连携 · Generating chains

- When a unit acts, look at the **previous action on its own side** (enemy turns in between don't matter).
- If that ally's element generates this one (for example Wood acted, now Fire acts), this action is a chain link and `chain = previous chain + 1`, up to 5. Otherwise the chain resets to 0.
- Each link gives **+15% damage, +25% crack and +10 energy**.
- A stunned or frozen turn breaks your side's chain.
- The turn-order forecast gives upcoming chain links a gold ring and link number, so players plan around it. They line chains up with Attack Bar boosts (三彩马、汝窑), slows (水 breaks) and speed upgrades.
- Enemies follow the same rules. A readable symmetric rule is better than hidden enemy bonuses.

## 5. 敌人意图 · Enemy intents

- Right after acting (and at battle start), each enemy decides its next move and shows it above its nameplate: a skill-kind icon plus the target's portrait for single-target moves.
- Large icon = skill or ultimate. Breaking that enemy before it acts downgrades the move to a basic attack. This is the main reason to spend a skill on a specific target.
- The player AI (auto-battle) values lethal hits, then breaks that interrupt, then breaks, then advantage.

## 6. 羁绊 · Traits (team composition)

Counted over the fielded team (up to 4). Tags come from each piece's real history:

| 羁绊 | 来源 | 档位 Tiers |
|---|---|---|
| 宋韵 Song Grace | 宋代名窑 · Song-dynasty wares (汝、定、龙泉、建、磁州) | 2: toughness +25% · 4: damage taken -12% |
| 彩绘 Painted | 釉上/釉下彩绘 · painted decoration (斗彩、青花、三彩、白地黑花) | 2: crack +20% · 3: crack +40%, breaking gives 20 energy |
| 单色釉 Monochrome | 一色釉 · single-colour glazes (汝、定、龙泉、建) | 2: chain bonus ×1.3 · 3: each link also heals 6% |
| 五行 Five Phases | 队伍里不同元素数 · distinct elements | 3: start with 15% ATB · 4: start with 30% ATB |
| 盛唐 / 大明 / 康乾 Tang / Ming / Qing | 朝代 · dynasty | 2: SPD +8 / crit +12% / HP +12% |

The dynasty traits have only one spirit each today. They are in the data so adding a second Tang/Ming/Qing piece switches them on with no code change.

Design intent: Song + Monochrome rewards a durable chain team. Painted rewards a break team. Five Phases rewards variety, and it conflicts with stacking one dynasty, which forces trade-offs when recruiting at a kiln.

## 7. 成长 · Progression inside a run

| 来源 Source | 内容 What | 频率 Frequency |
|---|---|---|
| 战斗胜利 Win | 存活者 +1 级（每级 +4.5% 基础属性）、恢复 20% · +1 level (+4.5% base stats), heal 20% | every fight |
| 战斗奖励 Reward | 3 选 1：普通战 2 器艺 + 1 釉片；精英 1 器艺 + 2 稀有釉片 · pick 1 of 3 | every fight |
| 窑炉 Kiln | 招募 1 只，或"回炉"学 1 个器艺 · recruit, or refire for an upgrade | ~1 per run |
| 商店 Shop | 3 釉片 + 1 器艺（55 金）+ 修复釉浆 · 3 shards, 1 upgrade, repair slip | ~1–2 per run |
| 金缮坊 Mending | 碎裂者修补：+12% 生命/攻/防 + 按碎因得伤痕 · mend: +12% and a scar | ~1–2 per run |

**器艺 Craft techniques**: 4 per spirit, each named after a real technique on that piece (开光、铜红、蟹爪纹、满釉支烧、芒口镶金、薄胎、兔毫、油滴……). Each one changes a skill's shape (hits, crack, cooldown, an added shield or ATB effect), not just a flat +5%. With about 6 fights per run, a player owns roughly 6–8 of the 16 available across a 4-spirit team, so no two runs build the same team.

**Scars and seams** (kept from before): shattering is a permanent risk, and mending turns that risk into a stronger, more individual figure.

## 8. 伤害与时长 · Damage and battle length

Damage per hit:

```
dmg = ATK × mult × 1000 / (1140 + 3.5 × DEF)
    × element (1.25 / 1.0 / 0.85) × chain (1 + 0.15·n) × broken (1.3)
    × passives × scars × traits × relics × crit (1 + CD) × U(0.95, 1.05)
```

A level-1 striker basic (mult 3.6) against a support takes about 22% of that target's HP. A basic is about 1/4.5 of a target, a skill about 1/3, an ultimate about 1/2 to 2/3.

**Targets at 1× speed with auto-battle** (the `est_sec` column of the simulator, player thinking time not included):

| 战斗 Fight | 我方行动数 Ally actions | 时长 Duration | 胜率（AI）Win rate (AI) |
|---|---|---|---|
| 普通 Normal | 10–16 | 45–90 s | 90–100% |
| 精英 Elite | 14–20 | 70–120 s | 70–90% |
| 首领 Boss | 20–30 | 2–3 min | 50–75% |

A full run is about 6 normal/elite fights, 1 boss and 5 non-combat nodes, which comes to about 20–25 minutes for a human player.

## 9. 模拟结果 · Simulation results

`godot --headless --path . -- --gm-sim=12` plays 12 fast battles for each starter × floor cell, with the AI on both sides.

Party model for floor *r*:
- level 4 + 0.8(r−1);
- about one upgrade per earlier fight;
- a glaze shard every two fights;
- a fourth spirit from floor 4;
- full HP.

The model is kinder than a real run (no HP carry-over), so aim slightly high.

SIM_RESULTS

## 10. 内容成本 · Content cost (to plan the roster)

Per new spirit, with the current pipeline:

| 部分 Part | 工作量 Effort |
|---|---|
| 程序化模型 Procedural model (`po_monster_builder.gd`) | 0.5–1 day |
| 专属动作 3 招 Signature moves (`po_anims.gd`) | 0.5 day |
| 数据：3 技能 + 被动 + 4 器艺 + 标签 + 胎厚 Data | 2–3 h |
| 图标剪影 Portrait glyph (`po_icons.gd`) | 30 min |
| 平衡：跑模拟、调 1–2 轮 Balance pass | 1–2 h |
| 考据与双语文案 Research & bilingual text | 2 h |
| **合计 Total** | **≈ 1.5–2 days** |

Other content:
- relic ≈ 1 h;
- event ≈ 2 h;
- trait ≈ 1 h if it reuses existing hooks.

A 1.0 target of **24 spirits / 40 relics / 15 events / 3 acts with 3 bosses** is about 50–60 working days of content on top of the systems.

## 11. 扩展 · Expansion

**More spirits (planned tags):**
- Tang: 长沙窑执壶 (Wood), 唐三彩骆驼 (Earth). Together with the Sancai Steed these switch on 盛唐.
- Ming: 永乐青花压手杯 (Water), 宣德祭红 (Fire).
- Qing: 珐琅彩 (Metal), 粉彩 (Fire).

**Other countries map onto the same five phases, so no rule changes are needed:**

| 窑口 Ware | 国家 Country | 元素 | 新羁绊 New trait |
|---|---|---|---|
| 伊万里 Imari | 日本 Japan | 金 Metal（金彩 gilding） | 海上丝路 Maritime Silk Road |
| 乐烧 Raku | 日本 Japan | 火 Fire（出窑急冷 pulled hot） | 茶道 Tea Way |
| 代尔夫特蓝陶 Delft | 荷兰 Netherlands | 水 Water（仿青花 cobalt） | 仿青花 Blue Imitators |
| 迈森 Meissen | 德国 Germany | 土 Earth（欧洲第一件硬质瓷胎 first European hard-paste） | 白金 White Gold |
| 伊兹尼克 Iznik | 土耳其 Türkiye | 木 Wood（花卉石英陶 floral quartz-frit） | 海上丝路 Maritime Silk Road |
| 韦奇伍德碧玉细炻器 Jasperware | 英国 UK | 土 Earth | 白金 White Gold |

**Later systems** (these hooks already exist):
- **Meta progression between runs**: new starting trios and new spirits in the kiln pool. Data-only, through `STARTERS` and `SPECIES_ORDER`.
- **Acts 2–3**: new maps and bosses. `enemy_specs` already scales level, toughness and enemy upgrades by floor.
- **Ascension levels**: `enemy_level` / toughness / hp_mult multipliers.

Rule of thumb for any new content: every new skill must have a crack value; every new spirit needs 2 tags; every new relic should change a decision (turn order, break, mend), not just add +x%.
