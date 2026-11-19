# 美术交回 duel-map-d01（2026-11-20）

分支 `art/maps`，交回提交为包含本文件的 tip 提交（基线 `7406ddf` / art-pass-01，源码基线 `d24b4e6`）。
新增独立 1v1 竞技场 **D/01「FOLD / 折廊」**：`duel_world.gd`（`class_name DuelWorld extends TrialWorld`）、
无头验证 `duel_check.gd`、评审工具 `duel_preview.gd`。**靶场 `world.gd` 与全部玩法锚点零改动**，
三项回归与基线逐字一致。逻辑侧在 `main` 按功能合并；接入方式见第 4 节。

## 1. 设计意图

26.6×34.6 m 封闭竞技场，**180° 旋转对称**（每个实体连同其绕原点旋转 180° 的孪生体一起放置，
`_sym` / `_sym_sign` / `_ramp` 保证），双方地形完全公平。每人出生 facing 中路：左手急停走廊、右手高台走道。
三条路线性格分明，垂直递进按角色跳跃数据校核（站跳 1.418 m、收脚跳 1.647 m、蹲高 1.3716 m、箱宽 0.8128 m）：

- **中路**：0.70 m 中央跳台（四面可站跳上台）+ 对角掩体（顶 1.95 m：地面收脚跳够不到，必须先上台；
  台上蹲眼 1.87 m 藏住、站眼 2.33 m 露出）。前后错位屏风墙（2.2 m）挡住出生对枪视线并把中路弯成 S 形；
  1.2 m head-glitch 箱四枚（蹲眼 1.17 m 藏、站眼 1.63 m 露）。
- **左路·急停走廊**：三道 2.2 m 交错挡板（橙色角标标记 peek 边），通道净宽 3.2 m；
  墙侧半幅设**蹲姿涵洞**（底 1.50 m：蹲 1.37 m 过、站 1.83 m 挡），涵洞旁即 1.6 m 门洞通中路——
  "蹲过涵洞继续走廊" 与 "门洞转中" 二选一。
- **右路·高台走道**：19.3° 坡道（可走上去，无需跳）接 1.05 m 台面；雉堞胸墙顶 2.35 m
  （台上蹲眼 2.24 m 藏、站眼 2.70 m 打），射击缺口 1.2 m 宽两处；**1.8 m 跳跃缺口**横跨台面；
  端头开放可跳落中路。走道端头到对方出生点有一条 26 m 跨图视线——**有意保留**，作为走高线的奖励，
  对方出生点两侧有 1.2 m 掩体箱可躲。
- 垂直链上限：胸墙顶 2.35 + 站跳 1.418 = 3.77 m < 围墙 4.5 m，无出图路径；
  屏风墙/挡板/隔墙顶（2.2/3.0 m）均不可站跳直达。

## 2. 坐标表（米，Y 向上，地面顶 Y=0）

| 元素 | 中心 | 尺寸 | 碰撞 |
| --- | --- | --- | --- |
| 出生点 A / B | `(0, 0.02, 14.5)` / `(0, 0.02, -14.5)` | yaw `0` / `PI` | — |
| 围墙 | x ±13、z ±17 | 厚 0.6、高 4.5 | 是 |
| 车道隔墙 ×8 | x ±6，\|z\| 中心 4.6 / 9.15 | 0.6×3.0×3.2 / 2.7 | 是 |
| 门洞楣 ×4 | x ±6，\|z\| 7.0 | 0.66×0.6×1.6（底 2.4） | 是 |
| 中央跳台 | (0, 0.35, 0) | 4.6×0.7×4.6 | 是 |
| 台上掩体 ×2 | (±1.35, 1.325, ±1.35) 对角 | 1.7×1.25×0.6 | 是 |
| 屏风墙 ×2 | (1.9, 1.1, 8.0) 及其孪生 | 4.6×2.2×0.5 | 是 |
| head-glitch 箱 ×4 | (±3.4, 0.6, ±4.6) | 1.2×1.2×1.2 | 是 |
| 走廊挡板 ×6 | (-11.1, 1.1, 12/5)、(-7.9, 1.1, 8.5) 及孪生 | 3.2×2.2×0.8 | 是 |
| 涵洞 ×2 | (-10.85, 1.9, 6.8) 及孪生 | 3.7×0.8×1.2（底 1.50） | 是 |
| 涵洞支柱 ×2 | (-9.15, 0.75, 6.8) 及孪生 | 0.3×1.5×0.3 | 是 |
| 坡道 ×2 | 顶面中点 (11.2, 0.525, 13.9) 及孪生 | 宽 2.6、跑 3.0、升 1.05 | 是（旋转盒） |
| 走道台面 ×4 | (10.85, 0.975, 9.5 / 2.4) 及孪生 | 3.7×0.15×5.8 / 4.8（顶 1.05） | 是 |
| 胸墙 ×8 | x 9.15，\|z\| 中心 1.15/3.85/7.8/10.6 | 0.3×1.3×1.7/1.3/1.6/2.0（顶 2.35） | 是 |
| 台面支腿 ×8 | (9.2, 0.45, 1.0/4.2/7.2/11.8) 及孪生 | 0.24×0.9×0.24 | 是 |
| 出生掩体 ×4 | (±3.0, 0.6, ±12.2) | 1.4×1.2×1.0 | 是 |

门洞净宽 1.6 m（|z| 6.2..7.8），隔墙中央缺口 |z|<3，两端 |z|>10.5 开放连通出生区。
碰撞实体共 60 个，全部第 1 层；**无 `practice_target` 组物体**（1v1 不打靶，命中陪练走 target=99 既有路径）。
视觉合批 166 盒 / 14 材质族，沿用 art-pass-01 的贴图、抖动与自发光（`lamp` 用于涵洞底灯带）。

## 3. 改到的函数

仅新增文件，未改任何基线文件：

- `duel_world.gd`：`_ready` 重建布局（不调用父类 `_ready`，靶场不生成）；新增 `_sym`、`_sym_sign`、
  `_ramp`、`_ramp_body`、`_perimeter`、`_lanes`、`_mid`、`_corridor`、`_walkway`、`_spawn_zone`、`_skyline`。
  复用父类 `_palette/_lighting/_box/_build_batches/_sign`；仅覆写地面贴图平铺为 13.3×17.3。
  导出常量 `MAP_ID="D01"`、`MAP_NAME="FOLD"`、`SPAWNS`、`SPAWN_YAW`、`BOUNDS` 供逻辑侧读取。
- `duel_check.gd`：对称配对（位置+尺寸+镜像 basis）、出生点站/蹲碰撞箱净空（含 ±0.4 m 偏移）、
  6 条视线断言、7 项真实 `TrialFighter` 物理动作（跳台、侧跳上走道、跨缺口、坡道行走、涵洞蹲过/站挡、门洞穿越）。
- `duel_preview.gd`：8 个固定评审机位截图 + `--fly` 飞行相机（WASD/E/Q/Shift/鼠标/Esc）。

## 4. 逻辑侧接入点（本次未动 main.gd）

1. `main.gd::_ready` 的 `Arena.new()` 换成按模式选 `DuelWorld.new()`；两者同为 `Node3D` 子场景，接口一致。
2. `main.gd::SPAWN` 为常量：接入时改为读当前地图的 `SPAWNS`；`_place/_arrive/_reset_player/_benchmark_input`
   都经 `_place` 或直接用 `SPAWN`，需一并地图化。
3. **朝向**：`_arrive` 目前不设 yaw（客方默认朝 -Z）。D/01 客方出生朝 +Z，接入时按 `SPAWN_YAW[slot]`
   设 `aim.x`（本地）与远端代理初始 yaw；否则客方背对战场。
4. 回归脚本（self-test / weapon_check / kz_check / bench-run）全部锚定靶场几何：
   **模式选择落地前保持靶场为默认地图**，D/01 作为可选模式接入；D/01 的性能对照按 AGENTS.md
   流程在集成后以导出包复跑（本次仅编辑器路径目视，166 盒合批负载低于靶场）。
5. HUD/准星/联机协议无需改动：`trial_link` 快照与命中路径不依赖地图内容。

## 5. 验证

```powershell
$godot = 'D:\工作区\游戏\角线试玩\.toolchain\Godot_v4.6.1-stable_win64_console.exe'
$qa = (New-Item -ItemType Directory -Path '.toolchain/art-qa' -Force).FullName
$env:APPDATA = $qa
& $godot --headless --path . --import
& $godot --headless --path . --fixed-fps 128 --script res://duel_check.gd
& $godot --headless --path . --fixed-fps 128 -- --self-test
& $godot --headless --path . --fixed-fps 128 --script res://weapon_check.gd
& $godot --headless --path . --fixed-fps 128 --script res://kz_check.gd
& $godot --path . --rendering-method gl_compatibility --audio-driver Dummy --script res://duel_preview.gd
& $godot --path . --rendering-method gl_compatibility --audio-driver Dummy --script res://duel_preview.gd -- --fly
```

- `DUEL_CHECK errors=0`：对称 60/60 配对；出生净空通过；视线 6/6 符合设计；
  跳台落点 y=0.700、侧跳落点 (10.58, 1.050)、跨缺口落点 z=4.741（台面内）、坡道 walking 到 y=1.050、
  涵洞蹲过 z=5.807 / 站挡 z=7.807、门洞穿越 x=-3.81。
- 回归与基线逐字一致：`SELF_TEST PASS … run=215.0 coast=0.8072 counter=0.2842 jump=1.4182 shots=4 distance=4.4966`、
  `WEAPON_CHECK errors=0`、`KZ_CHECK errors=0`。
- 截图 8 张：本树 `.toolchain/duel-map-qa/duel-<机位>.png`，副本在 `D:\工作区\游戏成果存放\duel-map-d01\`。
  机位：spawn-a / spawn-b（镜像对照）、mid、high-line（胸墙缺口俯瞰）、corner（挡板 peek 边）、
  low-line（涵洞蹲姿）、drop（台面端头）、overview（俯视全局）。

## 6. 备注

- 外部素材：无，全部程序化生成，无需登记 `ASSET_SOURCES.md`。
- 已知取舍：走道端头 26 m 跨图视线有意保留（见第 1 节）；涵洞底灯带底 1.495 m，蹲姿余量 0.12 m；
  胸墙顶 0.3 m 宽可站人（技巧点），不作通行路线。
- 侧跳上走道的起跳时机约在台沿前 0.9 m（贴台起跳会撞台侧、只蹭上台沿）——属真实箱跳手感，
  `duel_check.gd` 的起跳参数即按此校核；若后续调台面高度需同步该测试。
- 并行会话 art-pass-01 已在 `7406ddf` 交回；本交回仅新增文件，与其无重叠。