# 素材下载清单

> ⚠️ 当前环境网络受限，无法直接下载素材。请在本机浏览器中打开以下链接手动下载，解压后放入对应目录。

---

## 下载完成后的操作

1. 下载下方推荐的素材包（均为 CC0 或 CC-BY 许可，可免费商用）
2. 解压到 `godot-battle/assets/` 对应子目录
3. 如未下载素材，项目会自动使用 `placeholder_assets.gd` 生成的占位符素材

---

## 推荐下载资源（按优先级排序）

### 🥇 第一优先：角色精灵

| # | 资源名称 | 下载链接（请复制到浏览器） | 许可 | 放入目录 |
|---|---------|--------------------------|------|---------|
| 1 | **Kenney Tiny Dungeon** (16x16 地牢角色) | https://kenney.nl/assets/tiny-dungeon | CC0 | `assets/sprites/units/` |
| 2 | **LPC Medieval Fantasy Characters** | https://opengameart.org/content/liberated-pixel-cup-lpc-base-assets-sprites-map-tiles | CC-BY 3.0 / GPL | `assets/sprites/units/` |
| 3 | **Free Animated Top-Down Characters** | https://itch.io/game-assets/free/tag-fantasy/tag-pixel-art/tag-sprites | 见各页面 | `assets/sprites/units/` |

**Kennney Tiny Dungeon 直接下载**：
- 访问 https://kenney.nl/assets/tiny-dungeon → 点击 "Download" 按钮
- 含骑士、法师、骷髅、史莱姆等角色

**itch.io 推荐具体包**：
- https://itch.io/game-assets/free/tag-2d/tag-fantasy/tag-pixel-art/tag-sprites
- 筛选 "Top Free"，挑选合适的中世纪奇幻角色包

### 🥈 第二优先：UI素材

| # | 资源名称 | 下载链接 | 许可 | 放入目录 |
|---|---------|---------|------|---------|
| 4 | **Kenney UI Pack** | https://kenney.nl/assets/ui-pack | CC0 | `assets/ui/` |
| 5 | **Kenney Game Icons** | https://kenney.nl/assets/game-icons | CC0 | `assets/ui/` |
| 6 | **Free Fantasy GUI** | https://itch.io/game-assets/free/tag-ui/tag-fantasy | 见各页面 | `assets/ui/` |

### 🥉 第三优先：特效素材

| # | 资源名称 | 下载链接 | 许可 | 放入目录 |
|---|---------|---------|------|---------|
| 7 | **Kenney Particle Pack** | https://kenney.nl/assets/particle-pack | CC0 | `assets/effects/` |
| 8 | **Free Pixel Spell Effects** | https://itch.io/game-assets/free/tag-pixel-art/tag-effects/tag-spell | 见各页面 | `assets/effects/` |

### 🎵 音效素材

| # | 资源名称 | 下载链接 | 许可 | 放入目录 |
|---|---------|---------|------|---------|
| 9 | **Kenney RPG Audio** | https://kenney.nl/assets/rpg-audio | CC0 | `assets/audio/` |
| 10 | **Kenney Interface Sounds** | https://kenney.nl/assets/interface-sounds | CC0 | `assets/audio/sfx/` |
| 11 | **Free 8-Bit Battle Music** | https://itch.io/game-assets/free/tag-music/tag-battle/tag-8bit | 见各页面 | `assets/audio/bgm/` |

### 🔤 字体

| # | 资源名称 | 下载链接 | 许可 | 放入目录 |
|---|---------|---------|------|---------|
| 12 | **思源黑体** (中文字体) | https://github.com/adobe-fonts/source-han-sans/releases | SIL Open Font | 系统安装 |
| 13 | **Pixel Font** (伤害数字) | https://www.dafont.com/pixel.font 或 itch.io 搜索 "free pixel font" | 见各页面 | `assets/ui/` |

---

## 快速下载命令（如果有 wget/curl 可用）

```bash
# Kenney 素材 (CC0 = 完全免费可商用)
# 注意：这些 URL 可能会变化，请优先使用浏览器访问上方链接

# UI Pack
wget https://kenney.nl/content/2-assets/31-ui-pack/kenney_ui-pack.zip

# Game Icons  
wget https://kenney.nl/content/2-assets/21-game-icons/kenney_game-icons.zip

# RPG Audio
wget https://kenney.nl/content/2-assets/62-rpg-audio/kenney_rpg-audio.zip

# Particle Pack
wget https://kenney.nl/content/2-assets/51-particle-pack/kenney_particle-pack.zip
```

---

## 备用方案：程序化生成

如果无法下载任何外部素材，项目已内置占位符生成器：

**文件**：`scripts/data/placeholder_assets.gd`

**使用方式**：
1. 在 Godot 项目设置中将 `placeholder_assets.gd` 添加为 Autoload（名称：`PlaceholderAssets`）
2. 在任意脚本中调用 `PlaceholderAssets.generate_all_placeholders()` 即可生成所有占位符素材
3. 不同职业使用不同几何形状和颜色区分：
   - 骑士=蓝色菱形 | 法师=紫色圆形 | 弓手=绿色三角形
   - 牧师=白色十字 | 盗贼=灰色星形 | 重甲=棕色方形
   - 蓝方底部蓝色标识带 | 红方底部红色标识带

---

> **提示**：Kenney 的 CC0 素材是最推荐的 — 完全免费，无需署名，可商用，质量高且统一风格。
