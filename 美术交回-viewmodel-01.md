# 美术交回 viewmodel-01（2026-11-20，v0.8.0 轮）

分支 `art/maps`。本轮：手部与三武器重模 + CS2 风格动作模组。纯表现层，**逻辑判定零改动**。

## 新增文件

- `art/viewmodel/weapons.gd`（`VmWeapons`）：AK-47（弯弹匣三段、木护木/枪托、拉机柄、斜切防跳器）、USP-S（独立消音器+环带、可动套筒、后置锯齿）、爪子刀（闭合鹰嘴轮廓挤出刃+指环、反握拳）。手套手+腕部按武器姿态建模。静态件按材质合并为单个 ArrayMesh（每武器 ≤8 draw call），动件（Mag/Slide/Handle）独立节点。`build_*(mats, hands=false)` 供第三人称无手版本。
- `art/viewmodel/viewmodel.gd`（`VmRig`）：动作状态机 deploy/idle/reload/inspect + 叠加层（开火后坐、挥刀、移动 bob、视角 sway、落地 dip、idle 呼吸）。
- `viewmodel_views.gd`：动作相位截图 QA（10 帧），命令见下；已加入导出排除。

## 改到的函数（合并时按功能保留双方修改）

- `main.gd`：`_build_presentation`（只挂载 VmRig，保留曳光/弹痕池）、`_process` 表现段（改调 `_viewmodel.tick`）、`_local_shot`（改调 `notify_attack`）、`_input`（新增 KEY_F 检视）。删除旧 `_rig/_weapon_models/_muzzle/_swing_time/_flash_time/SWING_DURATION`；准星开火反馈改读 `_viewmodel.firing()`。
- `fighter.gd`：`show_avatar` / `_show_avatar_weapon`（第三人称换用无手武器模型，三节点切换）；`_swing_avatar_knife` 时序未动。
- `trial_hud.gd`：底部按键提示加「F 检视」。

## 动作时长（贴合 fighter.gd 常量，未改逻辑）

| 动作 | 时长 | 说明 |
| --- | --- | --- |
| 部署/切换 | 0.22 s | 等于切换 cooldown，首发射击时枪已抬起 |
| 换弹 | 手枪 1.55 / 步枪 2.10 s | 关键帧：倾斜→掉匣→插匣→坐匣→套筒/拉机柄后拉 |
| 检视 | 手枪 2.6 / 步枪 3.6 / 刀 3.2 s | F 键；开火/切换/换弹即取消；刀为指环双翻 |
| 挥刀 | 0.26 s 视觉窗 | 逻辑 KNIFE_CYCLE 0.4 s 不变 |
| 开火 | 闪光 0.042 s | 后坐弹簧衰减；步枪交替微偏航 |

## 验证

```powershell
& $godot --headless --path . --fixed-fps 128 -- --self-test
& $godot --headless --path . --fixed-fps 128 --script res://weapon_check.gd
& $godot --headless --path . --fixed-fps 128 --script res://kz_check.gd
& $godot --path . --script res://viewmodel_views.gd -- --test-resolution=1920x1080
```

截图 `user://vm-*.png`：rifle-idle / rifle-inspect / rifle-reload-mag / rifle-reload-rack / pistol-idle / pistol-inspect / knife-idle / knife-inspect / knife-slash / rifle-fire。改后三项检查全过且 SELF_TEST 数值与基线逐字一致。

## 已知取舍

- 风格化低模贴合靶场美术，非 CS2 写实资源；手部为手套块面+腕部，无手指骨骼。
- 检视/换弹期间手部随武器整体运动（无独立手指动画）。
- 刀刃双面材质（`blade`）兜底挤出绕向；金属度 0.3 保证背光面不发黑。
- 第三人称武器为无手同模，挥刀 tween 时序保持基线。