# 素材资源下载指南

> 本文档列出实现《圣兽之王》风格战斗系统所需的所有免费素材资源及下载链接。

---

## 一、素材需求清单

### 角色精灵（至少14种不同类型）
| 职业类型 | 数量 | 备注 |
|---------|------|------|
| 战士/骑士 | 2 | 前排物理 |
| 法师 | 2 | 后排魔法 |
| 弓手 | 2 | 后排物理 |
| 牧师/治疗 | 2 | 后排辅助 |
| 盗贼/斥候 | 2 | 前排高速 |
| 重甲步兵 | 2 | 前排坦克 |
| 枪兵 | 1 | 前排穿刺 |
| 狮鹫/飞龙骑士 | 1 | 飞行单位 |

### UI素材
- 按钮（正常/悬停/按下 三态）
- 面板/边框
- 图标（攻击、防御、速度、HP、AP、PP）
- 装备槽图标（武器、盾牌、饰品）
- 技能类型图标（红色AP、蓝色PP）

### 特效
- 斩击/打击特效
- 魔法/火焰/冰冻特效
- 治疗特效
- 格挡/护盾特效
- 伤害数字字体

### 音效
- 攻击命中
- 技能释放
- 格挡
- 暴击
- 胜利/失败
- 背景音乐

---

## 二、推荐免费素材来源

### 角色精灵

#### 1. itch.io — 推荐首选

以下为高评分免费像素角色包（CC0/CC-BY 许可）：

| 资源名称 | 链接 | 内容 |
|---------|------|------|
| 540 Fantasy Sprites Bundle | itch.io 搜索 "540 sprites fantasy" | 540个人形+怪物精灵 |
| Free Animated Top-Down Characters | itch.io 搜索 "free animated top-down rpg characters" | 俯视角动画角色 |
| 8 Free SNES-Style Heroes | itch.io 搜索 "8 SNES style heroes" | SNES风格英雄+战斗动画 |
| 45 Fantasy Humanoids | itch.io 搜索 "45 humanoid fantasy sprites" | 45个人形角色 |
| Animated Monsters for RPG | itch.io 搜索 "animated monsters turn-based rpg" | 怪物动画精灵 |

#### 2. CraftPix.net

| 资源名称 | 链接 | 内容 |
|---------|------|------|
| Free Knight Character | craftpix.net 搜索 "free knight pixel art" | 骑士角色精灵表 |
| Free Skeleton Sprites | craftpix.net 搜索 "free skeleton pixel art" | 骷髅敌人精灵 |
| Free Fantasy Characters | craftpix.net 搜索 "free fantasy characters pixel art" | 多个免费角色包 |

#### 3. OpenGameArt.org

| 资源名称 | 链接 | 内容 |
|---------|------|------|
| LPC Medieval Fantasy Characters | opengameart.org 搜索 "LPC medieval" | 大量中世纪角色（CC0/CC-BY） |
| RPG Battle Sprites | opengameart.org 搜索 "rpg battle sprites" | 战斗精灵 |

### UI素材

| 资源名称 | 来源 | 链接 |
|---------|------|------|
| Free Fantasy UI Pack | itch.io 搜索 "free fantasy ui pack" | 中世纪风格UI |
| RPG GUI Bundle | craftpix.net 搜索 "free rpg gui" | RPG界面元素 |
| Pixel Art Icons | itch.io 搜索 "free pixel art icons rpg" | 像素图标集 |
| Kenney Game Assets | kenney.nl/assets | 海量免费UI/图标（CC0）|

### 特效

| 资源名称 | 来源 | 链接 |
|---------|------|------|
| Free Pixel Effects Pack | itch.io 搜索 "free pixel art effects" | 像素特效包 |
| Magic Spells Effects | craftpix.net 搜索 "free magic spells effects" | 魔法特效 |
| Hit / Slash Effects | itch.io 搜索 "free pixel hit slash effect" | 打击特效 |

### 音效

| 资源名称 | 来源 | 链接 |
|---------|------|------|
| Free RPG Sound Effects | itch.io 搜索 "free rpg sound effects" | RPG音效包 |
| 300+ Fantasy SFX | opengameart.org 搜索 "fantasy sound effects" | 奇幻音效 |
| Victory / Defeat Fanfare | freesound.org 搜索 "victory fanfare" | 胜利/失败音乐 |
| 8-Bit Battle BGM | itch.io 搜索 "free 8bit battle music" | 战斗背景音乐 |
| Free Medieval Music | opengameart.org 搜索 "medieval battle music" | 中世纪风格BGM |

### 字体

| 资源名称 | 链接 | 内容 |
|---------|------|------|
| 思源黑体 (Source Han Sans) | GitHub - adobe-fonts/source-han-sans | 中文UI字体（免费商用） |
| Pixel Font | itch.io 搜索 "free pixel font" | 像素风格伤害数字字体 |

---

## 三、关键素材直接链接

以下是经过验证的具体下载页面（截至2026年8月可用）：

### 角色
1. **itch.io 免费奇幻角色** → https://itch.io/game-assets/free/tag-fantasy/tag-pixel-art/tag-sprites
2. **CraftPix 免费角色** → https://craftpix.net/freebies/page/2/
3. **OpenGameArt LPC 角色** → https://opengameart.org/art-search-advanced?field_art_tags=lpc

### UI
4. **Kenney UI Pack** → https://kenney.nl/assets/category:UI
5. **Kenney Icons** → https://kenney.nl/assets/category:Icons

### 音效
6. **Kenney RPG Audio** → https://kenney.nl/assets/category:Audio
7. **Freesound** → https://freesound.org/

---

## 四、素材处理要求

下载后的素材可能需要以下处理（请AI协助完成）：

1. **精灵表裁剪**：将精灵表拆分为单独帧（使用 Godot 的 AtlasTexture 或 SpriteFrames）
2. **尺寸统一**：所有战斗角色统一到 64×64 或 128×128 像素
3. **背景透明**：确保所有精灵背景为透明 PNG
4. **颜色调整**：蓝方角色带蓝色系色调，红方角色带红色系色调
5. **格式转换**：音效统一为 OGG 或 WAV 格式

---

## 五、预置素材放置规范

```
godot-battle/assets/
├── sprites/
│   └── units/
│       ├── blue_knight.png        # 蓝方骑士
│       ├── blue_mage.png          # 蓝方法师
│       ├── blue_archer.png        # 蓝方弓手
│       ├── blue_cleric.png        # 蓝方牧师
│       ├── blue_thief.png         # 蓝方盗贼
│       ├── blue_tank.png          # 蓝方重甲
│       ├── blue_soldier.png       # 蓝方枪兵
│       ├── red_knight.png         # 红方骑士
│       ├── red_mage.png           # 红方法师
│       ├── red_archer.png         # 红方弓手
│       ├── red_cleric.png         # 红方牧师
│       ├── red_thief.png          # 红方盗贼
│       ├── red_tank.png           # 红方重甲
│       └── red_soldier.png        # 红方枪兵
├── ui/
│   ├── button_normal.png
│   ├── button_hover.png
│   ├── button_pressed.png
│   ├── panel_bg.png
│   ├── icon_atk.png
│   ├── icon_def.png
│   ├── icon_speed.png
│   ├── icon_hp.png
│   ├── icon_ap.png                # 红色宝石图标
│   ├── icon_pp.png                # 蓝色宝石图标
│   ├── slot_weapon.png
│   ├── slot_shield.png
│   └── slot_accessory.png
├── effects/
│   ├── slash.png
│   ├── fire.png
│   ├── ice.png
│   ├── heal.png
│   └── shield.png
└── audio/
    ├── sfx/
    │   ├── hit.wav
    │   ├── slash.wav
    │   ├── magic.wav
    │   ├── block.wav
    │   ├── crit.wav
    │   ├── heal.wav
    │   ├── victory.wav
    │   └── defeat.wav
    └── bgm/
        └── battle_theme.ogg
```

---

## 六、备用方案：程序化生成素材

如果无法下载外部素材，可采用以下程序化方案：

### 角色
- 使用 Godot 的 `draw_rect`/`draw_circle` 绘制简单的几何形状角色
- 不同职业用不同形状和颜色区分（圆形=法师，方形=战士，三角形=盗贼）
- 蓝方(#4488ff) vs 红方(#ff4444)

### UI
- 使用 Godot 内置的 Theme 系统
- StyleBoxFlat 创建纯色/渐变按钮和面板
- 使用 Unicode 符号作为临时图标

### 特效
- 使用 Godot 的 CPUParticles2D 生成粒子特效
- 不同颜色代表不同技能类型

### 音效
- 使用 Godot 的 AudioStreamGenerator 生成简单的8-bit音效

---

> **文档版本**: v1.0 | **最后更新**: 2026-08-10
