# 圣兽之王 (Unicorn Overlord) 游戏数据库

本目录包含了《圣兽之王》（Unicorn Overlord）的游戏数据，以程序可读的 JSON 格式整理。

> 游戏信息：Vanillaware 开发，Atlus 发行，2024年3月8日发售。
> 平台：Nintendo Switch / PS4 / PS5 / Xbox Series X|S
> 类型：战术RPG（策略模拟RPG）

---

## 数据文件

| 文件 | 内容 | 条目数 |
|------|------|--------|
| [characters.json](characters.json) | 角色 & 属性 & 加入条件 | 69 名角色 |
| [classes.json](classes.json) | 职业 & 转职 & 技能 & 成长率 | 60+ 种职业 |
| [equipment.json](equipment.json) | 武器 & 盾 & 大盾 & 饰品 & 属性 | 100+ 件装备 |
| [skills.json](skills.json) | 技能 & 效果 & 策略编程条件 | 40+ 技能 + 30+ 条件 |
| [items.json](items.json) | 消耗品 & 材料 & 关键道具 | 30+ 种道具 |

## 数据说明

### characters.json
- 69名可招募角色
- 包含中文名、英文名、职业、成长类型、武器类型、加入条件、所属地区
- 20名可错过角色标注

### classes.json
- 60+ 种职业的完整数据
- 转职路径、转职消耗勋章数
- 转职能力提升数值（HP/Atk/Def/MAtk/MDef/Acc/Eva/Crit/Guard/Speed）
- 成长率等级(E~S)详细数据
- 各职业技能表（习得等级、AP/PP消耗、效果）
- 职业类型分类（步兵/骑兵/飞行/弓兵/法师/治疗/重装/兽人/特殊）
- 职业评价等级（S/A/B/C）

### equipment.json
- 武器：剑(27)、斧(13)、枪(12)、弓(7)、杖(12)
- 盾：小盾(15)、大盾(8)
- 饰品/护符(13)
- 游戏机制说明（格挡系统、伤害公式、异常状态、叠加规则）

### skills.json
- 30+ 主动/被动技能详细数据
- **策略编程条件完整列表**（30+ 条件，分为敌方/友方/自身三类）
- 条件类型：仅（Limit）/ 优先（Prioritize）
- 双条件组合逻辑（仅+仅、仅+优先、优先+优先）
- 策略编程技巧与常见模式
- 被动技能触发顺序

### items.json
- 回复类、耐力类、勇气类、经验类、增益类、工具类、永久属性类
- 材料与交换货币
- 交换所与商店信息

---

## JSON 结构规范

所有文件遵循统一格式：
```json
{
  "game": "圣兽之王",
  "game_en": "Unicorn Overlord",
  "category": "分类名",
  "data_source": "数据来源说明",
  "last_updated": "YYYY-MM-DD",
  // ... 具体数据
}
```

## 数据来源

- game8.co - Unicorn Overlord Wiki
- unicornoverlord.fandom.com - 官方Fandom Wiki
- GameFAQs - 社区攻略与FAQ
- ludo.guide - 装备与职业指南
- namu.wiki - 韩文Wiki
- ragequithq.site - 角色与装备指南
- NGA (ngabbs.com) - 中文社区攻略
- 机核 (gcores.com) - 策略编程指南
- ali213.net - 中文攻略
- 52pk.com / 9game.cn - 角色入队条件
- pinogamer.com - 角色加入条件一览
- thegamer.com / primagames.com - 策略条件指南
- superstarreviews.tech - 职业深入分析
- asia.sega.com - 官方系统介绍

---

## 许可

数据仅供学习研究使用。游戏版权归 Vanillaware / Atlus 所有。
