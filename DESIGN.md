# PyConsole Framework — 设计文档 (DESIGN)

> 面向 Python 控制台游戏的框架原型：手搓双缓冲渲染、动作名按键抽象、场景栈、实时模糊搜索百科、按住 Tab 状态总览 overlay。

---

## 1. 目标与非目标

**目标**
- 提供一个可复用的控制台游戏框架底座：渲染、输入、场景管理、键绑定。
- 用样例场景（主菜单 + 百科 + 提示）演示全部交互能力。
- 零第三方依赖，仅用 Python 标准库（msvcrt / ctypes / json / unicodedata / unittest）。

**非目标**
- 不做运行时改键 UI（键绑定可通过 `keybindings.json` 覆盖，手动编辑）。
- 不实现真正的游戏主循环（"开始游戏" 仅弹出演示提示）。
- 不跨平台（专注 Windows + msvcrt；其他平台需替换 io 层）。
- 不做窗口 resize 自适应（固定 100×30 逻辑分辨率）。

---

## 2. 技术选型（grilling 结论）

| 决策点 | 选择 |
|---|---|
| 渲染/输入栈 | 手搓 ANSI 帧缓冲 + msvcrt，零依赖 |
| 双缓冲 diff 粒度 | 单元格级 diff（首帧整屏，后续 diff） |
| 输出方式 | 每帧拼接后一次 `sys.stdout.write` + flush |
| 逻辑分辨率 | 固定 100×30，窗口不足不处理 |
| 颜色模型 | 256 色 ANSI |
| 主题 | 深色主题，颜色常量集中在 `theme.py` |
| 主循环 | 事件驱动 + 轻休眠（无键时 `time.sleep(0.015)`） |
| 按键抽象 | 动作名（Action）抽象层 |
| 键绑定存储 | 代码默认 + `keybindings.json` 覆盖 |
| Tab overlay | 全局 overlay 组件，按住显示 / 松开消失 |
| Tab 释放检测 | `ctypes` 调 `GetAsyncKeyState(VK_TAB)` 轮询 |
| 场景架构 | 场景栈（Scene 基类 + 钩子方法） |
| 场景背景 | 只渲染栈顶 |
| 场景间数据 | 支持参数进栈 / 返回值出栈 |
| Python | C:\.env311（Python 3.11.8） |
| 编码 | 启用 VT 处理 + `stdout.reconfigure(utf-8)`，失败有 fallback |
| 字符宽度 | 处理 CJK 双宽（`unicodedata.east_asian_width`） |
| 装饰 | box-drawing 边框 + ASCII 标题 |
| 测试 | unittest，仅测纯逻辑 |
| 启动 | `python main.py` |

---

## 3. 架构分层

```
pyconsole/
├── __init__.py
├── io/
│   ├── __init__.py
│   ├── width.py        # CJK 双宽计算
│   ├── theme.py        # 256 色主题常量
│   ├── buffer.py       # Cell + FrameBuffer（后缓冲）
│   ├── display.py      # Display：diff 渲染、VT/UTF-8 启用、清理
│   ├── input.py        # Input：msvcrt 读键 → Action 映射；Tab 轮询
│   └── widgets.py      # 画边框、文本、列表、输入框、提示栏等
├── core/
│   ├── __init__.py
│   ├── actions.py      # Action 枚举
│   ├── keys.py        # 原始键码 → Action 默认绑定 + json 加载
│   ├── scene.py        # Scene 基类 + 场景栈 SceneStack
│   ├── overlay.py      # 全局 overlay 组件（Tab 状态总览）
│   ├── app.py          # App：主循环、渲染调度、Tab overlay 注入
│   └── game_state.py   # 示例游戏状态（供 Tab overlay 显示）
├── scenes/
│   ├── __init__.py
│   ├── main_menu.py    # 主菜单场景
│   ├── game21.py       # 21 点人机对战（状态机 + AI 启发式 + tick 延迟动画）
│   ├── wiki.py         # 百科场景（输入框 + 列表 + 详情 + 模糊搜索）
│   └── message.py     # MessageScene（演示提示）
├── game/
│   ├── __init__.py
│   ├── cards.py       # Card / 牌堆 / 21 点点数（纯逻辑，无 IO）
│   └── card_back.py   # 隐写卡背：统一纹理里编码花色/点数（可逆解码 + 缓冲渲染）
├── data/
│   ├── __init__.py
│   ├── wiki.json       # 约 30 条奇幻 RPG 百科样例数据
│   └── wiki_data.py    # JSON 加载 + WikiEntry 数据类 + 模糊搜索
└── tests/
    ├── __init__.py
    ├── test_width.py
    ├── test_search.py
    ├── test_buffer.py
    ├── test_keys.py
    ├── test_cards.py
    ├── test_card_back.py    # 隐写卡背编码/解码可逆 + 缓冲渲染
    └── test_render_smoke.py # 各场景渲染冒烟 + 21 点新规则行为
main.py                 # 入口
README.md
DESIGN.md
PLAN.md
requirements.txt       # 空（零依赖）
```

依赖方向：`main → core.app → scenes → io + data`；`io` 与 `core` 不反向依赖 `scenes`。

---

## 4. 渲染管线（双缓冲）

### 4.1 Cell 与 FrameBuffer
- `Cell(char, fg, bg)`：一个单元格。`char` 为单字符（双宽字符占两个 Cell，第二个为 `""` 占位）。
- `FrameBuffer(w, h)`：二维 `list[list[Cell]]`，外加 `dirty` 集合。提供 `set_char(x,y,ch,fg,bg)`、`put_text(x,y,text,fg,bg)`（自动处理双宽）、`fill(ch,fg,bg)`、`clear()`。

### 4.2 Display
- `Display(w, h)`：
  - `enable_vt()`：`ctypes.windll.kernel32.SetConsoleMode` 启用 `ENABLE_VIRTUAL_TERMINAL_PROCESSING`；`stdout.reconfigure(encoding="utf-8")`；`stdout.reconfigure` 失败则 try `os.environ['PYTHONIOENCODING']` 已生效即可。失败有 fallback（不启用 VT 仍能跑，颜色/光标可能异常）。
  - `hide_cursor()` / `show_cursor()`：ANSI `?25l` / `?25h`。
  - `begin_frame()`：清空后缓冲（`fill`）。
  - `present(front)`：将后缓冲与上一帧（`front`）diff；首帧或尺寸变化时整屏重画（光标归位 `ESC[H` + 全部单元格）；否则仅输出变化单元格（`ESC[y;xH` 定位 + 颜色 + 字符）。拼接成一个大字符串一次 `write` + `flush`。然后后缓冲 → front 快照。
  - `cleanup()`：恢复光标、重置颜色 `\x1b[0m`、可选清屏。

### 4.3 双宽处理（`width.py`）
- `char_width(ch)`：`unicodedata.east_asian_width(ch)` 返回 `W/F` → 2，否则 1；控制字符视为 0/1。
- `put_text` 按宽度逐字写入，双宽字符后补占位 Cell，超出边界截断。

---

## 5. 输入与按键抽象（`input.py` / `keys.py` / `actions.py`）

### 5.1 Action
```
UP, DOWN, LEFT, RIGHT, SELECT, CONFIRM, BACK,        # 通用
TOGGLE_HELP, OPEN_WIKI,                              # 自定义示例
SCROLL_UP, SCROLL_DOWN,                              # 详情滚动（PgUp/PgDn）
CHAR                                  # 可打印字符输入（百科用），携带 ch
```

### 5.2 默认绑定（`keys.py`）
| 原始键 | Action |
|---|---|
| 方向键 ↑/↓/←/→ | UP/DOWN/LEFT/RIGHT |
| 空格 | SELECT |
| 回车 | CONFIRM |
| Esc | BACK |
| H / h | OPEN_WIKI |
| Tab | TOGGLE_HELP（由 overlay 直接消费，见 5.4） |
| PgUp / PgDn | SCROLL_UP / SCROLL_DOWN |
| 可打印 ASCII | CHAR（携带字符） |

方向键在 msvcrt 下是多字节序列（`0xe0` / `0x00` 前缀 + 码）：`H/P/K/M`（↑↓←→）。

### 5.3 键绑定覆盖
- `DEFAULT_BINDINGS: dict[str, Action]`（键名为可读名，如 `"up"`, `"space"`, `"h"`）。
- `load_bindings(path)`：若 `keybindings.json` 存在则读，按键名覆盖默认；文件缺失或损坏用默认，不崩溃。
- `KeyResolver`：把 msvcrt 读到的原始字节解析成 (键名, char)，再查绑定得到 Action。

### 5.4 Tab overlay 的特殊处理
- `Input.poll_tab_held()`：`ctypes.windll.user32.GetAsyncKeyState(VK_TAB=0x09)`，最高位为 1 表示按下。
- 主循环每帧先轮询 Tab：若当前栈顶场景 `allow_status_overlay=True` 且 Tab 按下 → 显示 overlay 并拦截该帧其他输入（模态）。

---

## 6. 场景架构（`scene.py` / `app.py`）

### 6.1 Scene 基类
```
class Scene:
    allow_status_overlay: bool = False     # 主菜单 True，百科 False
    def on_enter(self, ctx, params): ...
    def on_exit(self): ...
    def handle_action(self, action) -> SceneResult | None: ...
    def render(self, buf: FrameBuffer): ...
    def get_hints(self) -> list[str]: ...  # 底部键提示栏
```
- `handle_action` 返回 `SceneResult`：`PUSH(scene, params)` / `POP` / `QUIT` / `None`（留在当前场景）。

### 6.2 SceneStack
- `push(scene, params)` / `pop() -> (scene, return_value)` / `top()`。
- `on_enter` 在 push 时调用；`on_exit` 在 pop 时调用。
- 只渲染栈顶；下层不渲染。

### 6.3 App 主循环
```
while running:
    # 1. Tab overlay 轮询（模态拦截）
    show_overlay = stack.top().allow_status_overlay and input.poll_tab_held()
    # 1b. 推进场景内部定时状态（tick 钩子，驱动 AI 动画等）
    stack.top().on_tick(time.time())
    # 2. 读一个键（若 overlay 显示则不读，或读后丢弃）
    action = input.read_action() if not show_overlay else None
    # 3. 派发动作 → 栈顶 handle_action → 处理 PUSH/POP/QUIT
    # 4. 渲染：display.begin_frame(); stack.top().render(buf); 
    #          if show_overlay: overlay.render(buf); draw_hints(buf)
    # 5. display.present()
    # 6. 无键时 sleep(0.015)
```
- `on_tick(now)`：`Scene` 基类钩子，每帧调用一次（`now = time.time()`）。默认空实现；子类可用它驱动定时状态（如 21 点 AI 延迟动画），只改内部状态、不返回结果。

### 6.4 底部键提示栏
- 框架在每帧渲染末尾，用 `stack.top().get_hints()` 画底部一行提示（统一位置/样式）。

---

## 7. 主菜单场景（`main_menu.py`）

- `allow_status_overlay = False`（主菜单不响应 Tab；状态总览仅在游戏内可用）。
- 内容：ASCII 标题 "PyConsole Framework" + 副标题 "控制台游戏框架 · 双缓冲渲染演示"。
- 菜单项（4 项）：
  1. `单人游戏` → CONFIRM 时 `PUSH(Game21Scene)`（21 点人机对战，见第 8 节）
  2. `多人游戏` → CONFIRM 时 `PUSH(MessageScene, "多人游戏尚未实现 · 敬请期待")`
  3. `百科` → CONFIRM 时 `PUSH(WikiScene)`
  4. `退出游戏` → CONFIRM 时 `QUIT`
- 交互：
  - UP/DOWN 切换焦点项。
  - SELECT（空格）= **无效**（本菜单用回车选择，空格不做任何事）。
  - CONFIRM（回车）= 对焦点项执行操作。
  - OPEN_WIKI（H）= PUSH WikiScene（与菜单项"百科"等效）。
  - BACK（Esc）= 不响应（主菜单是栈底）。
- 布局：标题居中、菜单居中（`> 焦点标记 + 文字`）、底部键提示栏。

---

## 8. 21 点人机对战（`game21.py` / `game/cards.py`）

### 8.1 纯逻辑（`game/cards.py`，无 IO 依赖，可单测）
- `Card(rank, suit)`：rank 1=A,2-10 面值,11=J,12=Q,13=K；suit ∈ ♠♥♦♣。
- `new_deck()`：52 张（无大小王）。
- `shuffle(deck, rng)`：原地洗牌，可注入 `random.Random` 便于测试。
- `hand_score(cards) -> (score, busted)`：A 取 1/11 最优（先按 11 算，超 21 时逐张 A 减 10），JQK=10，busted=score>21。
- `rank_label(rank)`、`suit_color(suit)`（红♥♦→WARN，黑♠♣→FG）。

### 8.2 场景状态机（`game21.py`）
- `Side(slots, sleeve, passed, busted)`：一方的 **5 个固定卡槽**（`slots: list[Card|None]`，`None`=空，只读 `table` 视图派生自非空槽）/ 袖子 / 状态。
- `phase`：`menu`（玩家回合主菜单）→ `holding`（刚抽到牌，待决定打出/藏袖子）→ `discard`（袖子已满藏牌时，手动选一张丢弃）→ `sleeve_select`（选袖子牌打出）→ `slot_select`（选目标卡槽放牌，←→ 切换、回车确认；占用槽放置失败停留重选）→ `ai_turn`（AI 行动，忽略玩家输入）→ `settled`（结算，任意键 POP）。
- 规则要点：
  - **5 固定卡槽**：打出牌必须手动选放到哪个卡槽；选中已被占用的卡槽 → 放置失败，停留重选。5 槽放满即无处可放（须 pass）。
  - **抽牌锁定**：本回合一旦抽牌（`_drawn_this_turn=True`），唯一结束方式是打出一张牌到桌面空卡槽；期间可"抽→藏→抽→…"，但**不能 pass、不能从袖子打出**来结束回合（这两项在抽过牌时被禁用）。藏牌不结束回合。
  - **袖子满手动弃**：袖子已满 2 张再藏入时，不再自动丢弃最旧，而是进入 `discard` 阶段手动选一张丢弃，再藏入新牌。
  - 爆牌（>21）上桌即判、当场结算。A=1/11 取最优，JQK=10。先后手随机；牌堆抽空重洗。
- 结算：一方爆→对方胜；双爆比小；双方停→比点数（高胜、等平）。

### 8.3 tick 钩子 + 时间队列（AI 延迟动画）
- 事件驱动主循环无内置定时器；用 `on_tick(now)` 每帧驱动场景内 `_tasks: list[(due, fn)]`。
- `schedule(delay, fn)` 追加任务；`on_tick` 取出到期任务执行，任务可再 `schedule` 下一步（AI 每 ~0.7s 一步）。
- 任务只修改场景内部状态，不返回 SceneResult（结算面板的"任意键返回"仍由按键 POP）。
- POP 后场景实例不再被 tick，残留任务自然失效。

### 8.4 AI 启发式
- 遵循与玩家完全相同的规则约束：抽牌后必须打出一张牌（不能 pass / 不能从袖子打出）；袖子满再藏时丢弃最小点数牌；桌满无处放则强制 pass。
- 点数 ≥17 大概率（85%）停牌；≤11 必抽；12-16 按距 21 缺口与玩家可见点数概率抽牌，玩家已停且点数更高时被迫追。
- 偶尔从袖子出牌（若有且打出不爆，仅本回合未抽牌时）。抽到牌后：不爆则多数打出（小概率藏入袖子）；会爆则优先藏入袖子，袖子满则丢弃一张再藏；藏入后仍须打出一张牌（继续抽，直到抽到不爆的牌打出）。

### 8.5 渲染（100×30）
- 上：AI 区（点数、5 个卡槽明牌、袖子暗牌 ▓）。
- 中：状态/回合提示 + 握牌区（holding/slot_select/discard/sleeve_select 时居中显示当前持有牌）。
- 下：玩家区（5 个卡槽明牌、袖子明牌、点数）。
- 卡槽焦点颜色（`slot_select` 且 owner=player）：**金色边框=空槽可放置**，**红色边框=已占用（放置会失败）**；非选择阶段不高亮。←→ 切换焦点，1-5 直选。
- 操作面板（menu/holding/discard/sleeve_select/slot_select/ai_turn 各自布局，焦点高亮）+ 最近 2 条日志。
- 结算：居中 overlay 面板，揭晓 AI 袖子、显示双方点数与胜负，任意键返回。

---

## 9. 百科场景（`wiki.py`）

### 9.1 布局（上输入 + 左右分栏）
```
┌─ 百科全书 ──────────────────────────────────────────────────────┐  (标题)
│ 搜索: [输入框____________________________________]               │  (输入框)
├──────────────────────────────┬─────────────────────────────────┤
│ 列表区（名称 + [分类]）       │ 详情区                          │
│   可滚动                       │   name / category / summary /    │
│                               │   detail（可滚动 PgUp/PgDn）       │
├──────────────────────────────┴─────────────────────────────────┤
│ ↑↓切换 · PgUp/PgDn滚详情 · Backspace删字 · Esc退出              │  (提示)
└────────────────────────────────────────────────────────────────┘
```

### 9.2 交互规则
- 输入框：末尾追加式。可打印字符追加（限制长度 30），Backspace 删末尾，空格**不响应**（搜索无需空格）。
- 搜索：每次输入即时重新过滤，子串包含（大小写不敏感），匹配 `name+summary+category`，结果按 name 升序。
- 空输入：列表区空，提示"请输入关键字"；详情区提示"请输入关键字，然后选择条目查看详情"。
- 输入后：列表显示结果，默认选中第一项，详情区同步显示其详情。
- 无结果：列表区"未找到匹配条目"，详情区清空提示。
- 选中：UP/DOWN 切换条目（列表自动滚动跟随）；详情区同步刷新。
- 详情滚动：PgUp/PgDn 滚动详情文本。
- 高亮：列表条目命中子串高亮；详情区命中子串高亮。
- Esc：POP 回主菜单。

### 9.3 数据（`data/wiki.json` + `wiki_data.py`）
- `WikiEntry`：`id, name, category, summary, detail, attrs(dict)`。
- 约 30 条奇幻 RPG 条目，分类：武器 / 防具 / 消耗品 / 怪物 / 技能。
- `load_entries(path)`：读 JSON，缺失文件返回空列表（不崩）。
- `search(entries, query)`：纯函数，返回排序后的匹配列表 + 命中位置信息（供高亮）。

---

## 10. Tab overlay（`overlay.py` + `Scene.render_overlay`）

- 全局组件，不入场景栈。
- 触发条件：栈顶 `allow_status_overlay=True` 且 Tab 物理按下（`GetAsyncKeyState`）。
  栈顶为 `False`（如主菜单、百科）时 Tab 完全无效——不读取也不渲染。
- 模态：显示期间拦截其他输入。
- 渲染：在当前场景渲染后，先调用 `top.render_overlay(buf, w, h)`：
  - 返回 `True` → 场景已自绘 overlay（如 21 点的牌堆总览 + 隐写卡背），App 跳过通用面板。
  - 返回 `False`（默认实现）→ App 回退到 `overlay.render` 的通用"状态总览"面板。
- 通用面板内容（状态 + 调试二合一）：
  - 上半：示例游戏状态（角色名/等级、HP/MP 条、金币、位置、背包数、任务进度）—— 来自 `game_state.py`。
  - 下半：框架调试信息（当前场景名、栈深度、逻辑分辨率、活跃键绑定计数）。
- 21 点场景（`Game21Scene`）自定义 overlay：
  - 左上角：抽牌堆顶牌的**隐写卡背**（`game/card_back.py`：统一纹理里用 `┆`/`┈` 字符变体编码花色/点数，可逆解码）。
  - 右上角：编码说明 + 位置图例。
  - 下方：完整牌堆 4×13 网格，按牌当前归属（抽牌堆 / 你-桌面 / 你-袖子 / AI-桌面 / AI-袖子）着色。
- 松开 Tab 立即消失。

---

## 11. 终端生命周期

- 启动：`enable_vt()` → `hide_cursor()`。
- 运行：主循环。
- 退出（正常 QUIT / KeyboardInterrupt / 异常）：`finally` 中 `show_cursor()` + `\x1b[0m` 重置颜色 + 恢复模式。

---

## 12. 测试（`tests/`，unittest）

仅测纯逻辑 / 渲染冒烟（不输出到终端）：
- `test_width.py`：CJK 双宽、ASCII 单宽、控制字符、组合截断。
- `test_search.py`：子串命中、大小写不敏感、多字段匹配、排序、空查询、无结果、命中位置。
- `test_buffer.py`：`put_text` 双宽写入、越界截断、`set_char`、`fill`。
- `test_card_back.py`：隐写卡背 52 张编码→解码可逆、缓冲渲染可解码、花色映射覆盖。
- `test_keys.py`：默认绑定、json 覆盖、文件缺失用默认、方向键序列解析。
- `test_render_smoke.py`：主菜单/百科/Message/21 点各阶段渲染不抛；Tab overlay 渲染与隐写解码；以及 21 点新规则行为：5 卡槽默认空、`table` 只读视图、抽牌锁定（pass/出袖子被禁、藏牌不结束回合、打出才结束）、占用槽放置失败重选、←→ 焦点循环、袖子满手动弃、袖子牌打出进卡槽、AI 能推进到结算。

IO 渲染 / 输入轮询不测。

---

## 13. 关键不变量与风险

- **双宽对齐**：所有文本必须经 `put_text`，禁止直接 `buf[y][x] = ...` 写字符串。
- **首帧整屏**：`present` 在 front 为 None 时整屏重画。
- **Tab 模态**：overlay 显示时不派发其他 action。
- **`table` 只读**：`Side.table` 是 `slots` 非空项的只读派生视图，外部不得赋值（测试亦改写 `slots[i]`）。
- **抽牌锁定不可绕过**：`_drawn_this_turn` 一旦为 True，pass 与从袖子打出均被 `_can_pass`/`_can_play_sleeve` 拒绝；只有 `_try_place` 成功才会 `_after_play` 清零并交回合。
- **Esc 分层**：每个场景自己定义 BACK 语义（主菜单忽略、百科 POP）。
- **风险**：msvcrt / GetAsyncKeyState 仅 Windows；老 conhost 不支持 VT → fallback 路径需保证不崩。
