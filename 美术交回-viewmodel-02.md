# 美术交回 viewmodel-02（v0.9.0 手指级视图模型轮）

分支 `art/maps`。本轮把 v0.8.0 的"方块手+方块枪"重建为手指级可动手部与按 CS2 侧视参考细化的高模，并重排动作与取景。逻辑判定零改动。

## 新增 / 重写

| 文件 | 内容 |
| --- | --- |
| `art/viewmodel/vm_geo.gd` | 共享几何：顶点色合批（同材质静态件=1 surface）、倒角挤出 `bevel`、变厚度挤出 `extrude_z_taper`（磨刃）、星形枪口焰。材质仅 matte / metal / flash 三种。 |
| `art/viewmodel/hands.gd` | 可动手部绑定。规范手空间：伸指 -Z、掌面 -Y、拇指 ∓X。`orient(rig, pos, axis, palm)` 以**被握物轴**为弯曲轴摆握姿；`curl/blend/curl_all` 逐指控制；`live` 指定哪些指给关节（2=MCP+PIP，1=MCP）；`dual=true` 时另烘焙静息指网格 `RestFingers`，`set_live` 切换合批/关节。 |
| `art/viewmodel/weapons.gd` | 三武器高模 + CS2 握姿。AK：罩式准星、导气管、清洁杆、上下护木、肋纹四段弯匣、机匣盖肋、选择杆、拉机柄（动件）、木托。USP-S：开槽消音器、套筒防滑纹/抛壳口（动件）、握把贴片、扳机护圈。爪刀：柄指槽、尾指环、鹰嘴刃（刃面与柄轴共面、脊厚刃薄）。手：步枪右手握把+左手托护木，手枪双手叠握，刀反握食指穿环。`MagSpare` 挂在支援手上供换弹演出。 |
| `art/viewmodel/viewmodel.gd` | 动作编排。取景 BASE_POS/ROT 重算使手与枪落在 CS2 式右下；换弹支援手关键帧（离握→卡榫→掉匣→取匣→插匣→拉机柄/套筒→回握）+ 手指张合；开火食指扣扳机+枪机/套筒往复+星形焰；刀检视绕指环双翻且其余指张开；部署刀翻转。保留 bob/sway/dip/breath。 |
| `fighter.gd` | 第三人称 avatar 改用带手版本（`build_*(mats, true)`）。 |
| `viewmodel_views.gd` | 扩到 20 帧：部署/ idle /检视/换弹四拍/开火/挥刀，并打印 `VM_STATS` draw call 与图元数。 |
| `vm_solo.gd` | 新工具：隐藏地图、外部双机位拍单武器，用于调握姿与磨刃。 |

## 验证

- headless：`SELF_TEST PASS`、`WEAPON_CHECK errors=0`、`KZ_CHECK errors=0`（`.toolchain/art-qa/*-vm09.log` 与 release-qa/0.9.0）。
- 截图目视：`vm-views-09g.log` 20 帧全过；握姿/取景/磨刃经 `vm_solo.gd` 与第一人称交替复核 6 轮。
- draw call（整帧，1080p）：步枪 108 / 手枪 110 / 刀 107；v0.8.0 步枪约 110。静息合批后 idle 不高于旧版。
- 性能（1080p / GL Compatibility / Dummy，暖缓存）：v0.8.0 包 1872.0、1858.4 FPS / P99 1.41、1.39 ms；v0.9.0 包 1729.8、1740.9 FPS / P99 1.48、1.43 ms（合批前 1706.4、1719.0 / 1.51、1.50）。约 -6.4% 平均、+0.04~0.09 ms P99，开销在手指/袖口几何与近景填充，不在 draw call。日志 `角线试玩/.toolchain/release-qa/0.9.0/bench-v*.log`。

## 已知取舍

- 风格化低模，非 CS2 写实资源；中指/无名指/小指在支援手为单关节（MCP），张合时近端整段摆动。
- 爪刀刃为程序化磨刃挤出，刃口厚度 0.5 mm 级，远看偏细。
- 换弹插匣瞬间用 `MagSpare`/`Mag` 显隐交换完成"入匣"，非真实物理插入。
- 退出时 `ObjectDB instances leaked at exit` 依旧，逻辑侧追踪中。

## 查看站位

出生点 `(0, 0.02, 6)` 朝 -Z 即第一人称默认取景；`vm_solo.gd` 双机位看模型细节；`viewmodel_views.gd` 看动作各拍。