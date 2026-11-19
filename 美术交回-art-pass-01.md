# 美术交回 art-pass-01（2026-11-20）

分支 `art/maps`，交回提交为包含本文件的 tip 提交（基线 `f2629db` / 源码基线 `d24b4e6`）。
改动集中在 `world.gd`，新增评审脚本 `art_views.gd`。逻辑侧请在 `main` 按功能合并。

## 改到的函数

- `world.gd::_palette`：新增运行时程序化混凝土贴图（`_surface_texture`，噪声 + 2 px 低对比伸缩缝），地面 2 m 平铺、混凝土墙约 4 m 板缝；新增 `ring`（靶环弱自发光 0.35）与 `lamp`（ gantry 灯条自发光 1.4）两种材质；全部材质开启 `vertex_color_use_as_albedo`。
- `world.gd::_lighting`：环境光 0.62→0.45、太阳 1.0→1.12 且更暖（`#ffe9c8`）、太阳角 -53°→-56°；新增深度雾 `fog_density=0.0055`、`fog_sky_affect=0.25`；天空顶色微调。色调映射保持线性（试过 filmic，中间调发灰，已回退）。
- `world.gd::_build_batches`：MultiMesh 开启 `use_colors`，对 `_JITTERED` 材质族做 ±3% 逐实例明度抖动（确定性 hash），打破大平面单色感。
- `world.gd::_structure`：远景天际线体块（墙外、无碰撞）、 annex 屋顶通风口与管线、gantry 梁下灯条（自发光、无真实光源）、后墙长椅与 `READY / LINE` 标牌；**annex 内表面后退 6 cm**（见下）。
- `world.gd::_range_markings`：左侧检修通道木箱堆与油桶（`_barrel`，新增函数）。
- `world.gd::_jump_course`：跳台正面编号 01–04（纯视觉标牌）。
- `world.gd::_target`：靶环改用 `ring` 自发光材质；靶座正面编号 01–04（纯视觉标牌）。碰撞体、组、`target_id` 均未动。
- `world.gd::_sign`：新增可选 `rotation_y` 参数（后墙标牌朝 -Z 用）。
- 新增 `art_views.gd`：六个固定评审站位自动截图，命令见下。

## 玩法锚点：全部未动

出生点 `(0, 0.02, 6)` / `(3, 0.02, 6)`、C/01 拐角、四跳台顶高 0.35/0.70/1.05/1.40 及其位置、四靶中心与半径、gantry、距离牌、`weapon_check.gd` 测速道（`z≈8, x∈[-4.5, 4.5]`）与 `Plate_01` 刀测区均保持基线值。改后 `SELF_TEST` 数值与改前逐字一致：`run=215.0 coast=0.8072 counter=0.2842 jump=1.4182 shots=4 distance=4.4966`。

## 新增碰撞实体（第 1 层，供逻辑侧复核移动）

| 实体 | 中心 | 尺寸 | 备注 |
| --- | --- | --- | --- |
| 木箱 ×5 | `(-11.1, 0.475, z)`，z ∈ [-33, -23, -13, -3, 5] | 1.15×0.95×1.15 | 检修通道，距侧墙内面 0.7 m |
| 叠箱 ×2 | `(-11.0, 1.38, z+0.1)`，z ∈ [-23, -3] | 0.8×0.7×0.8 | 坐在木箱顶 |
| 油桶 ×3 | `(-10.3, 0.45, z)`，z ∈ [-26.4, -6.4, 3.6] | 圆柱 r0.34 h0.9 | `_barrel` 生成 |
| 椅面 | `(0, 0.46, 13.05)` | 7×0.14×0.55 | 后墙长椅 |
| 椅背 | `(0, 0.86, 13.32)` | 7×0.62×0.10 | 同上 |
| 椅腿 ×4 | `(x, 0.20, 13.05)`，x ∈ [-3.2, -1.1, 1.1, 3.2] | 0.12×0.40×0.5 | 同上 |

以上全部避开测速道与刀测区（最近木箱距 `Plate_01` 刀测站位 >6 m）。纯视觉新增：天际线 5 块、屋顶通风口 6 + 管线 1、灯条 8、编号/后墙标牌 9、靶环自发光。

## 顺带修复的基线缺陷

annex 内表面与侧墙内面原先同在 `x=-12.4`，重叠 z 段共面 z-fighting，掠射角出现斜纹（基线即存在，近距站位才暴露）。annex 中心 `-15.0`→`-15.06` 消除共面；屋顶盖、通风口、管线相对关系不变。另：贴图缝最初用 1 px 高对比线，长墙掠射角 mipmap 摩尔纹，已改 2 px、0.80 低对比，**不要改回硬缝**。

## 验证方法

```powershell
$godot = 'D:\工作区\游戏\角线试玩\.toolchain\Godot_v4.6.1-stable_win64_console.exe'
$qa = (New-Item -ItemType Directory -Path '.toolchain/art-qa' -Force).FullName
$env:APPDATA = $qa
& $godot --headless --path . --import
& $godot --headless --path . --fixed-fps 128 -- --self-test
& $godot --headless --path . --fixed-fps 128 --script res://weapon_check.gd
& $godot --headless --path . --fixed-fps 128 --script res://kz_check.gd
& $godot --path . -- --visual-test --test-view=0 --test-resolution=1920x1080
& $godot --path . --script res://art_views.gd -- --test-resolution=1920x1080
& $godot --path . --rendering-method gl_compatibility --audio-driver Dummy -- --bench-run --test-resolution=1920x1080
```

改后三项检查：`SELF_TEST PASS`、`WEAPON_CHECK errors=0`、`KZ_CHECK errors=0`。
`art_views.gd` 站位（ yaw 0 朝 -Z，-PI/2 朝 +X，PI 朝 +Z ）：

| 站位名 | 位置 | yaw / pitch | 看什么 |
| --- | --- | --- | --- |
| spawn | (0, 0.02, 6) | 0 / 0 | 出生点全景：地面贴图、雾、天际线 |
| jump | (6.5, 0.02, 4.5) | -0.37 / -0.12 | 跳台编号与顶面 chalk 边 |
| target1 | (-4.7, 0.02, -5.0) | 0 / -0.05 | 靶 1 环自发光、靶座编号、距离牌 |
| lane | (-6.0, 0.02, 2.0) | 1.07 / -0.10 | 左通道木箱/油桶、墙板缝、annex 无共面纹 |
| gantry | (0, 0.02, -20.5) | 0 / 0.30 | 梁下灯条、RANGE/03、靶 4 |
| rear | (0, 0.02, 6) | PI / -0.05 | 后墙长椅与 READY / LINE |

截图输出 `user://art-view-<站位名>.png`。对比图已放 `D:\工作区\游戏成果存放\art-pass-01\`（before-range / after-range / after-各站位）。

## 性能（1920×1080、GL Compatibility、Dummy 音频、编辑器路径）

| 配置 | 平均 FPS | P99 ms |
| --- | --- | --- |
| 基线·会话早段 ×2 | 1987.8 / 1994.5 | 0.87 / 0.87 |
| 基线·会话晚段同时刻对照 ×2（HEAD 临时工作树） | 1561.7 / 1596.2 | 1.17 / 1.16 |
| 改后 ×2 | 1438.7 / 1411.4 | 1.22 / 1.20 |

会话内机器状态漂移约 0.3 ms P99，故以同时刻对照为准：**美术增量约 P99 +0.05 ms、平均 -10%**（贴图采样 + 深度雾 + 少量实例），余量仍大。导出包改前/改后对照按 AGENTS.md 流程由逻辑与性能侧复跑；原始日志在本树 `.toolchain/art-qa/bench-*.log` 与 `.toolchain/art-qa-before/bench-now-*.log`。

## 备注

- 工作树中另有未跟踪 `duel_check.gd` / `duel_world.gd`（含 .uid），非本次美术改动，未纳入提交，归属待逻辑侧确认。
- 外部素材：无。贴图与模型全部运行时程序化生成，无需登记 `ASSET_SOURCES.md`。