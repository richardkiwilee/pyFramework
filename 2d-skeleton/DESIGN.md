# 2D 骨骼动画系统 — 设计文档

## 目标
用 Godot 4.6 原生功能构建 2D 骨骼 + 骨骼动作 + 多套美术资源，提供
`play(骨骼, 动作, 美术)` 形式的动画播放。场景中放置 3 个下拉框（骨骼/动作/美术），
点击「应用」销毁旧对象、按选择重建并播放。无背景。

## 引擎与项目
- Godot 4.6.2，可执行文件 `c:/godot/Godot_v4.6.2-stable_win64.exe`
- 项目目录 `2d-skeleton/`（已存在 `project.godot`，gl_compatibility 渲染）
- 仅操作本目录

## 核心架构

### 数据流
```
gen_all.gd (单一数据源, @tool)
   │  生成 ↓
   ├─ res://skeletons/<sk>.tres   (BoneDef: 骨定义)
   ├─ res://anims/<anim>.tres     (Animation 资源)
   └─ res://art/<set>/<bone>.png  (每骨 PNG) + _meta.tres
        │
        ↓ 运行时扫描
main.gd (@tool)
   ├─ 3 个 OptionButton 扫描 3 个文件夹
   └─ play(sk, anim, art)
         ├─ 销毁旧角色
         ├─ 读 BoneDef → 构建 Skeleton2D + Bone2D
         ├─ 每骨挂 Sprite2D(load art png), z_index 按契约
         ├─ AnimationPlayer 加载 4 个 anim, 用相对路径
         └─ player.play(anim)  # 挥剑完自动回呼吸
```

### 为什么这样设计
- **代码构建骨骼/动画** (非手写 .tscn): Bone2D 的 bone_pose 轨道文本极其冗长且易错；
  代码构建 + `ResourceSaver` 落盘最干净。
- **骨定义为 .tres** 而非 .tscn: 让「骨骼」下拉框能像 美术/动画 一样扫文件夹，
  且未来加骨骼只需加一个数据条目。
- **每动画独立 .tres**: 让「动作」下拉框扫文件夹；加载到同一 player。
- **每骨 PNG** (@tool Image API 光栅化): 满足「光栅 PNG 精灵」，
  运行时只 load 纹理，干净。
- **相对节点路径** (`../Skeleton2D/...`): 让 anim .tres 不依赖角色被挂在哪,
  destroy/respawn 仍可用。
- **原地走/跑**: 固定舞台、无背景、单机位下最清晰。

## 骨骼契约 (15 骨, 共享名称)

```
hip  (z=0)
└─ torso  (z=0)
   ├─ head  (z=0)
   ├─ upper_arm_R (z=+1) → fore_arm_R (+1) → hand_R (+1) → sword (+2)
   ├─ upper_arm_L (z=-1) → fore_arm_L (-1) → hand_L (-1)
   ├─ thigh_R (z=+1) → shin_R (+1) → foot_R (+1)
   └─ thigh_L (z=-1) → shin_L (-1) → foot_L (-1)
```

- **朝向**: 侧视, 面朝右 (+X)
- **比例**: 总高 ~220px
  - head r≈14 / torso 60 / upper_arm 36 / fore_arm 34 / thigh 46 / shin 44 / foot 22 / sword 70
- **静息姿势**: A-pose (手臂略下、腿伸直、剑在右手朝下) ≈ 呼吸第 0 帧
- **剑**: 始终在右手, 是 hand_R 的子骨, 属于可换美术的一部分

## 动画 (4 套, AnimationPlayer 属性轨道驱动 Bone2D)

| key | label | 时长 | 类型 | 关键帧 |
|---|---|---|---|---|
| breath | 呼吸 | 3.0s | loop | 躯干 scale 1±0.02、手臂微摆、头微点 |
| walk | 走动 | 1.0s | loop | 原地; 髋膝抬起 + 手臂摆动 |
| run | 跑步 | 0.5s | loop | 原地; 更前倾、手臂更大、抬腿更高 |
| sword_swing | 挥剑 | 0.7s | one-shot | 防御→上举(右肩上)→前下劈→恢复 |

- **轨道路径**: `../Skeleton2D/hip/torso:rotation` 形式 (角色内相对路径)
- **挥剑后**: `animation_finished` 信号 → 自动转回 `breath`
- **生成后**: 从第 0 帧立即播放选中动作

## 美术 (2 套)

| 集合 | label | 主色 |
|---|---|---|
| A | 骑士 | 桃肉肤色 #f0c090 + 钢蓝盔甲 #5a6a8a + 钢剑 #c8d0e0 |
| B | 兺人 | 绿皮 #6a9a5a + 棕皮甲 #6a4a2a + 暗红剑 #a0202a |

- **形状**: 每骨圆角矩形/圆 (头), 2px 描边, Image-API 光栅化
- **分辨率**: 2× 骨尺寸 + padding (例: torso 128×128, sword 160×96)
- **锚点**: 顶中心(骨首), 向下延伸; 旋转即从关节摆动
- **z 序**: 远侧=-1 / 躯干组=0 / 近侧=+1 / 剑=+2 → 剑劈砍不被遮挡

## UI 与场景

```
Main (Node2D, @tool main.gd)
├─ CanvasLayer
│  └─ HBoxContainer (顶居中)
│     ├─ OptionButton "骨骼"   ← 扫 res://skeletons/*.tres
│     ├─ OptionButton "动作"   ← 扫 res://anims/*.tres
│     ├─ OptionButton "美术"   ← 扫 res://art/*/  (子文件夹)
│     └─ Button "应用"         ← play(当前3项)
└─ Stage (Node2D, 屏幕中心)
   └─ Character (spawn/destroy)
```

- **无背景** (无 BackGround 图/图集)
- **启动**: 屏幕空, 点「应用」才生成
- **Stage 固定位**: 只销毁/重生角色, 不动舞台
- **play()** 是具名函数:
  ```gdscript
  func play(skeleton_name, anim, art_set):
      _free_current()
      var ch = _build(skeleton_name, anim, art_set)
      $Stage.add_child(ch)
      ch.get_node("AnimationPlayer").play(anim)
  ```

## 文件结构
```
2d-skeleton/
├─ project.godot          # 设 main.tscn 为主场景
├─ DESIGN.md / TODO.md
├─ scripts/
│  ├─ bone_spec.gd        # class_name BoneSpec
│  ├─ bone_def.gd         # class_name BoneDef
│  ├─ art_meta.gd         # class_name ArtSetMeta
│  ├─ gen_all.gd          # class_name GenAll (@tool 单一数据源)
│  └─ main.gd             # @tool 主控
├─ main.tscn
├─ skeletons/humanoid.tres
├─ anims/{breath,walk,run,sword_swing}.tres
└─ art/{A,B}/<bone>.png + _meta.tres
```

## 扩展
- 加骨骼 = 在 gen_all.gd 加一条骨骼定义数据 + 重跑生成; 下拉框自动扫到
- 加动作 = 加关键帧数据条目 + 重跑
- 加美术 = 加一套配色 + 重跑

## 技术风险 (实现中验证, 不阻塞)
1. Bone2D 属性轨道运行时是否真的级联到子骨 (Godot 4.6 Skeleton2D
   有时偏好 bone_pose 轨道) → 若不行退到 bone_pose 轨道
2. @tool 下 SubViewport→Image→save_png 是否顺畅 → 若不行用 Image 直接 fill/polygon
