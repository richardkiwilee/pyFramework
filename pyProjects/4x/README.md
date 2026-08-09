# TheGreatConquest

Windows 平台 4X 回合制策略游戏。在一张有固定线路连线的大地图上，把地图移动简化为"跳（Hop）"，把战略重心从"如何在地图上移动"转移到"何时、向哪里用兵"。玩家通过占领据点扩张版图、经营经济、招募英雄与军队，最终以攻破敌方首都为目标。游戏强调时机掌控：月相与昼夜两套独立时间周期持续修正战场。

## 文档导航

- **[游戏规格.md](游戏规格.md)** — 完整实现规格。整合总设计、交互规格、原型范围、精确数据模型与常量、Game 公共 API、回合执行顺序、全部数据定义文件、剧本默认值、存档格式、mod 支持。**目标：仅凭此文档即可直接开始编写 Godot 4.7 版本。**
- **[CONTEXT.md](CONTEXT.md)** — 术语表（精确定义，不含实现细节）。
- **[docs/adr/](docs/adr/)** — 不可逆架构决策记录（ADR-0001 ~ 0013）。

## 验证（Python 原型）

```bash
cd u:/pyFramework/pyProjects/4x
py smoke_test.py                              # 对局冒烟（exit 0 = 过）
py -m unittest discover -s pyconsole/tests   # 框架测试（149）
py -m unittest discover -s pydemo/tests       # 业务层测试（71）
```

技术栈：纯 Python 标准库，零第三方依赖。先在 Python 做小地图验证核心机制与架构，通过后再在 Godot 4.7 实现 UI 版本。
