# 2D 骨骼动画系统 — TODO

## 项目
- 引擎: Godot 4.6.2 (`c:/godot/`)，项目目录 `2d-skeleton/`
- 仅在本目录工作，不读写其他文件夹
- 尽可能使用 Godot 原生类: `Skeleton2D` / `Bone2D` / `Sprite2D` / `AnimationPlayer`

## 任务清单

### 1. 资源类 (自定义 Resource)
- [x] `bone_spec.gd` — `class_name BoneSpec`
- [x] `bone_def.gd` — `class_name BoneDef`
- [x] `art_meta.gd` — `class_name ArtSetMeta`

### 2. 生成器 `gen_all.gd` (单一数据源, @tool 可调用)
- [x] 骨骼定义数据 (15 骨)
- [x] 计算 local pos/rot, 保存 `res://skeletons/humanoid.tres`
- [x] 4 套动画关键帧 → `res://anims/*.tres`
- [x] 2 套美术 PNG + `_meta.tres`

### 3. 主场景 `main.tscn` + `main.gd` (@tool)
- [x] `_ready` 生成+扫描填充
- [x] UI 顶部 HBox + 3 下拉框 + 应用
- [x] `Stage` 容纳角色
- [x] `play(sk,anim,art)` 销毁/重建/播放
- [x] 挥剑后回呼吸
- [x] 启动空屏

### 4. 接线与验证
- [x] `project.godot` 设主场景
- [x] headless 运行捕获脚本错误
- [x] 修复报错
- [x] 运行时验证：4 个动画均驱动骨骼
- [x] 静态轨道解析验证（BAD_TRACKS=0/9）
- [x] 干净重建自动生成
- [x] GUI 运行无脚本错误、无 mixer 警告
- [x] 修复角色横躺（根骨不烤 90° 进 rotation，仅存角度差；精灵 offset=(0,h/2) 沿局部 +Y 向下）
- [x] 修复下拉框尺寸（custom_minimum_size 180/160/180×36 + HBox 加宽到 920）
- [x] 主场景设为 autoload `Main`（不重复生成；main.gd 用 @onready 取场景内节点，autoload 自动实例化主场景）

## 骨骼契约 (15)
`hip → torso → head`、`upper_arm_R→fore_arm_R→hand_R→sword`、`upper_arm_L→fore_arm_L→hand_L`、`thigh_R→shin_R→foot_R`、`thigh_L→shin_L→foot_L`

## 动画
| key | label | 时长 | 循环 |
|---|---|---|---|
| breath | 呼吸 | 3.0s | loop |
| walk | 走动 | 1.0s | loop |
| run | 跑步 | 0.5s | loop |
| sword_swing | 挥剑 | 0.7s | one-shot→回呼吸 |

- 轨道: `Bone2D` 属性轨道 (`rotation`/`position`/`scale`), 路径形如 `../Skeleton2D/hip/torso:rotation`
- 走/跑原地 (根固定), 挥剑为右上举→前下劈, 右臂在前 (z=+2)

## 美术 (2 套, 每骨 1 PNG)
| 集合 | label | 主色 |
|---|---|---|
| A | 骑士 | 桃肉肤色 + 钢蓝盔甲 + 钢剑 |
| B | 兽人 | 绿皮 + 棕皮甲 + 暗红剑 |

- 形状: 圆角矩形/圆, 2× 骨尺寸 + padding, 2px 描边
- 锚点: 顶中心(骨首), 向下延伸
- z 序: 远侧(L 臂+L 腿)=-1, 躯干/头/髋=0, 近侧(R 臂+R 腿)=+1, 剑=+2

## 文件结构
```
2d-skeleton/
├─ project.godot
├─ scripts/
│  ├─ bone_spec.gd
│  ├─ bone_def.gd
│  ├─ art_meta.gd
│  ├─ gen_all.gd
│  └─ main.gd
├─ main.tscn
├─ skeletons/   (humanoid.tres)
├─ anims/       (breath/walk/run/sword_swing.tres)
└─ art/A,B/     (per-bone .png + _meta.tres)
```
