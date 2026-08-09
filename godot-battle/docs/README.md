# 《圣兽之王》战斗系统 — Godot 实现文档索引

> 本项目包含基于《圣兽之王》(Unicorn Overlord) 战斗系统的完整设计文档和 AI 实现提示词。

---

## 文档索引

| 文件 | 内容 | 用途 |
|------|------|------|
| [01-game-design.md](./01-game-design.md) | 完整游戏设计文档 | 战斗系统、属性、技能、装备、编程条件的详细规格 |
| [02-ai-implementation-prompt.md](./02-ai-implementation-prompt.md) | 场景实现提示词 | 队伍编辑场景 + 战斗场景的详细实现规格 |
| [03-assets-guide.md](./03-assets-guide.md) | 素材资源指南 | 所需素材清单、来源、处理要求 |
| [04-master-prompt.md](./04-master-prompt.md) | **主提示词（推荐）** | 合并所有内容的完整 AI 实现提示词，直接发送给 AI |
| [05-asset-download-list.md](./05-asset-download-list.md) | 素材下载清单 | 可直接在浏览器中打开的下载链接 |

---

## 快速开始

### 如果你想自己实现：
1. 阅读 [01-game-design.md](./01-game-design.md) 了解战斗系统设计
2. 阅读 [02-ai-implementation-prompt.md](./02-ai-implementation-prompt.md) 了解场景规格
3. 参考 [03-assets-guide.md](./03-assets-guide.md) 准备素材

### 如果你想让 AI 实现：
1. 将 [04-master-prompt.md](./04-master-prompt.md) 的完整内容发送给支持 Godot 4.x 的 AI 编码助手
2. 按照 [05-asset-download-list.md](./05-asset-download-list.md) 下载所需素材
3. 将下载的素材放入 `assets/` 对应目录

---

## 项目结构

```
godot-battle/
├── docs/                              # 文档目录
│   ├── README.md                      # 本文件
│   ├── 01-game-design.md              # 游戏设计文档
│   ├── 02-ai-implementation-prompt.md # 场景实现提示词
│   ├── 03-assets-guide.md             # 素材指南
│   ├── 04-master-prompt.md            # 主提示词（发送给AI）
│   └── 05-asset-download-list.md      # 素材下载清单
├── scripts/
│   └── data/
│       └── placeholder_assets.gd      # 占位符素材生成器
├── assets/                            # 素材目录（下载后放入）
│   ├── sprites/units/                 # 角色精灵
│   ├── ui/                           # UI素材
│   ├── effects/                       # 特效素材
│   └── audio/                         # 音效/音乐
├── scenes/                            # 场景文件（AI实现后生成）
├── icon.svg                           # 项目图标
└── project.godot                      # Godot 项目配置
```

---

## 核心设计要点

### 战斗自动进行
- 按行动速度排序回合
- 角色按预设策略自动选择技能和目标
- AP（红）用于主动技能，PP（蓝）用于被动技能

### 编程条件系统
- **「仅」(限定)**：条件不满足→技能跳过
- **「优先」(优先)**：优先选择符合条件的目标
- 两种条件组合实现 if-then 逻辑
- 策略按优先级从上到下依次检查

### 伤害计算链
```
命中判定 → 暴击判定 → 基础伤害 → 属性克制 → 防御减免 → 格挡减免 → 最终伤害
```

---

> **创建日期**: 2026-08-10 | **基于**: 《圣兽之王》(Unicorn Overlord) 战斗系统深度研究
