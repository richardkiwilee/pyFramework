# PyConsole Framework

面向 Python 控制台游戏的框架原型：**手搓双缓冲渲染** + **动作名按键抽象** + **场景栈** + **实时模糊搜索百科** + **按住 Tab 状态总览 overlay**。

零第三方依赖，仅用 Python 标准库（`msvcrt` / `ctypes` / `json` / `unicodedata` / `unittest`）。

> 平台：**Windows**（输入用 `msvcrt`，Tab 按住检测用 `GetAsyncKeyState`）。

---

## 运行

```bash
# 使用 C:\.env311（Python 3.11.8）
C:\.env311\Scripts\python.exe main.py
```

建议把控制台窗口拉到至少 **100×30**（程序以该逻辑分辨率渲染，窗口更小会裁切但不崩溃）。

### 操作

| 键 | 动作 | 适用场景 |
|---|---|---|
| ↑ / ↓ | 上下移动焦点 | 主菜单、百科列表、21 点菜单 |
| 空格 | 选中 / 反选当前项 | 百科（21 点与主菜单中无效） |
| 回车 | 确认 / 执行 | 主菜单、21 点 |
| 数字 1-3 | 快捷选择菜单项 | 21 点 |
| H | 进入百科 | 主菜单 |
| Backspace | 删一个字符 | 百科输入框 |
| PgUp / PgDn | 滚动详情 | 百科详情区 |
| Esc | 退出当前场景 | 百科、21 点（→主菜单） |
| **按住 Tab** | 显示状态总览 overlay | 主菜单（松开消失） |

---

## 功能演示

1. **主菜单**：ASCII 标题 + 4 项菜单（单人游戏 / 多人游戏 / 百科 / 退出游戏）。空格无效，回车选择。
   - "单人游戏" → 进入 **21 点人机对战**（见下）。
   - "多人游戏" → 弹出"尚未实现"提示，任意键返回。
   - "百科"（或按 H）→ 进入百科。
   - "退出游戏" → 退出程序。
   - **按住 Tab** → 居中显示"角色状态 + 框架调试"二合一面板，松开消失。
2. **21 点人机对战**：与 AI 对战的 21 点（详见下方"21 点玩法"）。
3. **百科**：上输入框 + 左右分栏。
   - 输入即时模糊搜索（子串包含、大小写不敏感，匹配 name/summary/category）。
   - 左列表显示 `名称 [分类]`，命中子串高亮；↑↓ 切换，详情区同步刷新。
   - 右详情显示全字段（name/分类/摘要/属性/详情），命中高亮，PgUp/PgDn 滚动。
   - 空查询显示提示；无结果显示"未找到"；Backspace 删字；Esc 退出。

---

## 21 点玩法

一副不含大小王的 52 张扑克牌，玩家与 AI **轮流操作**，目标是让桌面牌的点数尽量接近 21 且不超过。

### 规则

- **点数**：A 按 1 或 11 取最优（不爆则按 11），J/Q/K 记 10，2-10 按面值。
- **每回合三选一**：
  1. **抽牌**：从牌堆抽一张，然后选择 **打出上桌** 或 **藏入袖子**。
  2. **从袖子打出**：把袖子里的一张牌打到桌面（袖子有牌时才出现该选项）。
  3. **Pass 停牌**：本方不再操作。
- **袖子**：最多藏 2 张。袖子已满时再藏入，会**丢弃最左边（最旧）**那张。
- **桌面**：每方最多打出 5 张，满 5 张自动停牌。
- **爆牌**：打出后点数 > 21，立即爆牌、当场结算。
- **回合**：每次一个动作后交给对方；若对方已停牌则本方继续；双方都停或任一方爆牌即结算。
- **结算**：一方爆 → 对方胜；双方都爆 → 点数小者胜；双方停牌 → 比点数，高者胜、相等为平局。
- **先后手随机**；牌堆抽空会自动重新洗牌。

### 视觉与节奏

- AI 桌面牌**明牌**、袖子**暗牌**（▓）；玩家桌面与袖子均为**明牌**。
- AI 的每个动作（抽/打/藏/停）有约 0.7 秒的延迟动画，让对局可读。
- 结算时居中弹出结算面板，揭晓 AI 袖子，显示双方点数与胜负，**按任意键返回主菜单**。
- 任意时刻按 **Esc** 可放弃当前对局、返回主菜单。

### 键位（21 点内）

| 键 | 动作 |
|---|---|
| ↑ / ↓ | 切换菜单/选项焦点 |
| 回车 | 确认当前选项 |
| 1 / 2 / 3 | 快捷选择对应菜单项；holding 阶段 `1`=打出、`2`=藏入袖子 |
| Esc | 放弃对局 / sleeve_select 取消回菜单 / 结算后返回主菜单 |

---

## 架构

```
pyconsole/
├── io/            渲染（双缓冲）与输入
│   ├── width.py      CJK 双宽计算
│   ├── theme.py      256 色主题常量
│   ├── buffer.py     Cell + FrameBuffer（后缓冲）
│   ├── display.py    Display：diff 渲染、VT/UTF-8 启用、清理
│   ├── input.py      msvcrt 读键 + Tab 按住轮询
│   └── widgets.py    边框/文本/列表/输入框/进度条/提示栏
├── core/          动作、键绑定、场景栈、主循环、overlay
│   ├── actions.py    Action 抽象
│   ├── keys.py       默认绑定 + keybindings.json 覆盖 + KeyResolver
│   ├── scene.py      Scene 基类 + SceneStack
│   ├── game_state.py 示例游戏状态
│   ├── overlay.py    Tab 状态总览面板
│   └── app.py        主循环、渲染调度
├── scenes/        具体场景
│   ├── main_menu.py  主菜单
│   ├── game21.py     21 点人机对战（状态机 + AI 启发式 + tick 延迟动画）
│   ├── wiki.py       百科（输入+搜索+列表+详情）
│   └── message.py    提示场景
├── game/          游戏纯逻辑（无 IO 依赖，可单测）
│   └── cards.py      Card / 牌堆 / 21 点点数
├── data/          数据
│   ├── wiki.json     30 条奇幻 RPG 百科样例
│   └── wiki_data.py  加载 + 模糊搜索
└── tests/         unittest（纯逻辑 + 渲染冒烟）
main.py            入口
```

依赖方向：`main → core.app → scenes → io + data`。详见 [DESIGN.md](DESIGN.md)。

---

## 双缓冲是怎么工作的

1. **后缓冲**（`FrameBuffer`）：100×30 的单元格矩阵，每格 `Cell(char, fg, bg)`。所有场景渲染先写进这里。
2. **前缓冲**：上一帧的快照。
3. **diff**（`Display.present`）：
   - 首帧 / 尺寸变化 → 整屏重画（光标归位 + 全部单元格）。
   - 否则 → **单元格级 diff**：只对变化的单元格发定位 + 重绘指令，拼接成一个大字符串一次 `write + flush`。
4. 双宽字符（中文）占两个 Cell，第二个为占位格，保证边框/光标不错位。

这是控制台避免闪烁的核心：只重画变化的部分，且一次性输出。

---

## 如何扩展

### 加一个新场景

```python
# my_scene.py
from pyconsole.core.scene import Scene, SceneResult, NONE, PUSH, POP
from pyconsole.core import actions
from pyconsole.io.buffer import FrameBuffer

class MyScene(Scene):
    allow_status_overlay = False  # 想让 Tab 能在此显示就设 True

    def handle_action(self, event) -> SceneResult:
        if event.action == actions.BACK:   # Esc
            return POP()
        return NONE()

    def render(self, buf: FrameBuffer) -> None:
        buf.put_text(2, 2, "我的场景", 213)  # 颜色码见 theme.py

    def get_hints(self) -> list[str]:
        return ["Esc 返回"]
```

从任意场景压栈：在 `handle_action` 里 `return PUSH(MyScene())`。

### 加一个新键绑定

编辑 `keybindings.json`（与 `main.py` 同目录，不存在则用代码默认值）：

```json
{
  "h": "confirm",
  "space": "open_wiki"
}
```

格式 `key_name → action`。可用的 `key_name`：`up/down/left/right/space/enter/escape/backspace/h/page_up/page_down` 等；可用的 `action` 见 `core/actions.py`。文件损坏或值非法会静默回退默认，不崩溃。

### 加百科条目

编辑 `data/wiki.json`，每条：

```json
{
  "id": "w999",
  "name": "幻影斗篷",
  "category": "防具",
  "summary": "穿戴后短暂隐身的法袍。",
  "detail": "由影丝织就……（多行会自动折行）",
  "attrs": {"防御": 4, "特效": "隐身", "价格": 2000}
}
```

`category` / `name` / `summary` 参与搜索，`detail` 不参与（太长会干扰）。

---

## 测试

```bash
C:\.env311\Scripts\python.exe -m unittest discover -s pyconsole/tests -v
```

覆盖：CJK 双宽、缓冲写入/截断、模糊搜索/命中区间、键绑定加载与解析、21 点牌堆与点数（A=1/11 取最优、多 A、JQK=10、爆牌）、21 点游戏场景各阶段渲染（不输出到终端，只验证渲染不抛异常、AI 能推进到结算）。共 82 个用例。

---

## 设计与计划

- [DESIGN.md](DESIGN.md)：完整设计决策（grilling 结论汇总）。
- [PLAN.md](PLAN.md)：分阶段实施计划。

---

## 已知限制

- **Windows 专属**：输入依赖 `msvcrt` 与 `GetAsyncKeyState`；移植到 Linux/macOS 需替换 `io/input.py`（用 `termios`/`tty` + select）。
- **固定分辨率**：100×30 逻辑分辨率，不做窗口 resize 自适应。
- **无运行时改键 UI**：键绑定通过 `keybindings.json` 手动编辑覆盖。
- **VT 启用有 fallback**：若 `SetConsoleMode` 启用 VT 失败（极旧系统），程序仍能跑，但颜色/光标控制可能异常。
