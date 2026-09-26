# Drop-in creature models

把 `.glb` / `.gltf` 文件按角色 id 命名后放在这里，它就会**自动替换**这个角色的程序化模型。例如 `emberlynx.glb`。
模型会自动缩放、落地并转向，然后重新上一层瓷釉和金缮着色，所以颜色、光泽和裂纹会跟其他角色保持一致。

| 文件名 | 角色 | 建议找的造型 |
|---|---|---|
| `emberlynx.glb` | 焰釉猞猁（火） | 猫、狐、狼 |
| `tidemoth.glb` | 潮光瓷蛾（水） | 飞虫、蝴蝶、水母 |
| `chimeram.glb` | 风铃角羊（风） | 羊、鹿、带角的四足兽 |
| `lumenowl.glb` | 月白鸮（光） | 鸟、猫头鹰 |
| `kilnbear.glb` | 窑心熊（火） | 熊、魔像、大块头 |
| `cobaltshell.glb` | 青花盾龟（水） | 龟、螃蟹、带壳生物 |
| `galemantis.glb` | 青瓷螳（风） | 螳螂、昆虫、刺客型 |
| `tenmoku.glb` | 天目釉蛇（暗） | 蛇、龙、幽灵 |

动画按名字里的关键词自动匹配，不区分大小写：
- 待机：`idle`
- 攻击：`attack` / `bite` / `punch` / `headbutt` / `slash` / `weapon` / `claw`
- 施法：`spell` / `cast` / `roar` / `dance` / `yes` / `jump`，没有的话用攻击动画代替
- 受击：`hitreact` / `hitrecieve` / `hit` / `damage`
- 死亡：`death` / `die`，播完后再碎成瓷片

**推荐素材（CC0，可商用、不用署名）**：Quaternius 的 *Ultimate Monsters* 或 *Animated Monster Pack*（quaternius.com / poly.pizza）。这些包里的怪物自带 Idle、Bite_Front、HitRecieve、Death 等动画，直接改名放进来就能用。
如果你想先在 Blender 里改造型（加角、改比例等），导出时选 glTF 2.0（.glb），并勾选 Animation。
