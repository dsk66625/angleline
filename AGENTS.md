# 《角线试玩》美术、地图与玩法交接

本次交接基于可玩的 **v0.7.0**，游戏源码基线提交为 `d24b4e6`。本机美术工作树是 `D:\工作区\游戏\角线美术`（`art/maps`），玩法、性能和集成工作树是 `D:\工作区\游戏\角线试玩`（`main`）。在各自工作树中用 Godot 4.6.1 打开 `project.godot` 并按 F5。初次运行会出现设置菜单，点「进入练习」查看地图。

## 从哪里改

| 工作 | 当前入口 | 协作约定 |
| --- | --- | --- |
| 美术与地图建模 | `world.gd` 的 `_palette`、`_lighting`、`_structure`、`_range_markings`、`_jump_course`、`_target` | 美术 agent 主改场景、模型、材质和灯光。新模型或子场景可直接放入美术工作树，通过 `world.gd` 实例化。外部素材按工作区的 `../docs/ASSET_SOURCES.md` 登记来源与许可。 |
| 手持模型与角色外观 | 第一人称为 `main.gd::_build_presentation`，第三人称为 `fighter.gd::show_avatar` | 更换模型时优先把美术内容放进独立场景，入口只处理挂载。第一人称模型数组按手枪、步枪、刀排列。玩家快捷键依次是 1 步枪、2 手枪、3 刀。 |
| 游戏逻辑和性能 | `fighter.gd` 管移动、蹲姿、攻击和快照，`main.gd` 管输入、物理步、命中和性能采样，`trial_link.gd` 管联机同步。 | 逻辑 agent 主改这些函数并做性能对照。涉及同一文件时在交接记录中写明改到的函数，合并时按功能保留双方修改。 |
| HUD、准星与视角 | `trial_hud.gd`、`crosshair.gd`、`main.gd::_sync_render_size` | 美术可调整界面表现。准星像素、4:3 黑边或拉伸、世界视野已有校准，改到时可运行 `fov_check.gd` 并在设置中看实机画面。 |

## 地图与游戏的接口

- **加载。** `main.tscn` 只有挂脚本的 `AngleLine` 根节点。`main.gd::_ready` 添加 `Arena.new()`，`world.gd::_ready` 再生成靶场。想在编辑器里摆模型，可以单独编辑地图子场景，再从该入口加载一次。
- **比例与出生点。** 地图以米建模，Y 向上，默认向 −Z 看，地面顶是 Y=0。1 游戏单位（u）等于 0.0254 米。主客出生点分别是 `(0, 0.02, 6)`、`(3, 0.02, 6)`。玩家宽 32 u，站高 72 u，蹲高 54 u。普通站跳脚底升高约 55.83 u，跳后收脚约 64.83 u，可用于估算台阶、门洞和跳台净空。
- **碰撞与命中。** 地图实体和靶板使用第 1 层，玩家在第 2 层。玩家移动查询第 1 层，攻击射线查询两层。`world.gd::_box` 仅在 `solid=true` 时生成实体。让墙、掩体、台沿的碰撞面与模型对齐，地面油漆和边条可只做视觉。射线实际打到的靶板碰撞体须属于 `practice_target` 组，并带整数 `target_id`。当前四靶编号为 1–4。
- **改图时顺带验证什么。** 现有 C/01 拐角用于急停，右侧四个跳台的顶高依次为 0.35、0.70、1.05、1.40 米。`weapon_check.gd` 在真实地图的 `(-4, 0.01, 8)` 朝 +X 测速，并查找 `Plate_01`，在靶前 1.1 米和 3 米验证刀的命中与挥空。如果设计要移动这些地点，一并调整测试站位，继续覆盖同一个玩法。`kz_check.gd` 使用自建测试场，61 u 高台和 58 u 低顶可独立复核角色碰撞。
- **渲染。** 当前使用 GL Compatibility，`world.gd::_build_batches` 把同材质静态方块合并为 MultiMesh，靶板保留独立碰撞身份。替换为导入模型时，可在同分辨率和相同镜头路径上对比改前、改后的 P99 帧时间。固定物理频率为 128 Hz。

## 验证与交回

Agent 在用户当前桌面用下方 `--headless` 命令调试，不操作系统鼠标、键盘或编辑器的 F5。需要模拟操作时，在测试脚本内发送游戏输入。人工试玩仍可使用 F5。

以下示例在工作树根目录的独立 PowerShell 窗口运行。临时 `APPDATA` 只供该窗口启动的测试进程使用，日志和测试设置位于本工作树已忽略的 `.toolchain/art-qa`。本机两棵工作树共用已有引擎。

```powershell
$godot = 'D:\工作区\游戏\角线试玩\.toolchain\Godot_v4.6.1-stable_win64_console.exe'
$qa = (New-Item -ItemType Directory -Path '.toolchain/art-qa' -Force).FullName
$env:APPDATA = $qa
& $godot --headless --path . --import
& $godot --headless --path . --fixed-fps 128 -- --self-test
& $godot --headless --path . --fixed-fps 128 --script res://weapon_check.gd
& $godot --headless --path . --fixed-fps 128 --script res://kz_check.gd
```

主场景自检输出 `SELF_TEST PASS`，另外两项成功时输出 `WEAPON_CHECK errors=0` 和 `KZ_CHECK errors=0`。以下图形命令在独立测试机或有独立输入会话的虚拟机中运行。第一条保存设置页与靶场截图，第二条测量渲染表现。`art_views.gd`、`viewmodel_views.gd` 和 `duel_preview.gd` 也使用该环境。环境未就绪时记录待测项并继续本机无窗口检查。

```powershell
& $godot --path . -- --visual-test --test-view=0 --test-resolution=1920x1080
& $godot --path . --rendering-method gl_compatibility --audio-driver Dummy -- --bench-run --test-resolution=1920x1080
```

截图路径见 `VISUAL_TEST` 输出。性能看 `RANGE_BENCH` 的实际渲染尺寸、GPU、平均 FPS 和 P99 毫秒。该基准预热约 2 秒、采样约 15 秒，覆盖出生区自动平移、转头和开火。新地图的高负载区域可另选固定站位复测。

**2026-11-20 性能基线。** 已导出的 v0.7.0 在本机 Core Ultra 9 275HX、RTX 5080 Laptop（驱动 621.24）上，以 1920×1080、GL Compatibility、Dummy 音频连续运行两次。平均帧率分别为 1070.8、902.7 FPS，P99 帧时间分别为 1.37、2.02 ms。后续用同样参数顺序运行改前、改后的 Windows 导出包，分别保存日志。本机原始日志在主工作树的 `.toolchain/handoff-v070-qa/bench-1080p-1.log` 和 `bench-1080p-2.log`。两次退出时均有 `ObjectDB instances leaked at exit` 提示，交由逻辑与性能侧追踪。

美术交回时提供分支提交、改动场景、查看效果的站位，以及有意调整过的碰撞或测试锚点。逻辑侧据此在 `main` 集成，复核移动、命中、联机和帧时间。完整操作与手感数据见[试玩说明](./试玩说明.txt)。
