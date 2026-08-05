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
│   ├── cards.py       # Card / Suit / DeckDef / 牌堆 / 21 点点数（多值泛化，纯逻辑无 IO）
│   ├── effects.py     # Effect / SlotEffect / EFFECT_REGISTRY（卡牌+卡槽效果执行器）
│   ├── card_back.py   # 隐写卡背：统一纹理里编码花色/点数（可逆解码 + 缓冲渲染）
│   └── deck_defs/     # 套牌定义（每套一文件）：基础 / 剥削 / 损坏
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
    ├── test_effects.py      # 剥削/损坏/空壳执行器 + 放牌时序
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

> 阶段 7 引入经济 + 效果 + 多轮系统，对玩法做重大扩展。本节先给「数据契约与核心机制」，
> 详细规则见 §14（经济与多轮）、§15（套牌与卡牌）、§16（卡槽栈模型）、§17（回合与软 pass）。
> 旧版「抽牌锁定 = 抽过必须打出」「爆牌当场结算」「pass 永久停」已被 §17 取代。
> **实现状态**：阶段 7 已落地，149 个单测全绿（cards 31 + effects 17 + card_back 9 + render_smoke 45 + 其余 47）。
> 关键常量：`MAX_SLOTS=5` / `MAX_SLEEVE=2` / `AI_STEP_DELAY=0.7` / `CARD_W=8` / `CARD_H=4` / `START_GOLD=20` / `GOLD_CAP=20` / `HIDE_COST=2`。

### 8.1 纯逻辑（`game/cards.py` + `game/deck_defs/`，无 IO 依赖，可单测）
- `Card(suit, tag, points, rank?, on_play?, on_activate?, on_end?)`（frozen dataclass）：
  - `rank: int | None`：标准套用 1..13（兼容旧逻辑）；怪套牌可为 None。
  - `suit: str`：花色，标识所属套牌（`Suit.symbol`）。
  - `tag: str`：显示标签，如 `"A"` / `"10"` / `"8|0"`（多值牌明文显示候选）。
  - `points: tuple[int, ...]`：**多值候选**。单值 `(v,)` 即普通固定点数；多值如 A 的 `(1,11)`、怪牌 `(8,0)`。计分时从每张牌的候选里选一组使总和最优且不爆。
  - `on_play / on_activate / on_end: Effect | None`：三类卡牌效果（见 §15）。
- `make_standard_card(rank, suit) -> Card`：标准套工厂（`tag=rank_label`、`points` 标准映射，A=`(1,11)`）。**旧位置构造 `Card(rank, suit)` 不再支持**，所有调用点改用此工厂。
- `Suit(symbol, name, cards, archetype)`：一套牌定义。`cards: tuple[Card, ...]` 点数/标签可非标准；`archetype` 为能力倾向标签（如 `"点数套"` / `"负点数套"`），纯描述、不做数值平衡。
- `DeckDef(suits)`：全部已定义套牌。`sample_for(n_players, rng)` 抽 `n_players` 套合并洗牌成**单一共享牌组**（所有玩家共用）。
- `new_deck()` / `shuffle(deck, rng)`：兼容旧签名；`hand_score(cards) -> (score, busted)` 泛化为「枚举每张牌 `points` 候选的笛卡尔积，≤21 取最大，否则取最小并标 busted」，A 的 1/11 是多值 `(1,11)` 的特例。
- `rank_label` / `suit_color`：保留；`rank_label` 优先用 `card.tag`，回退到 rank。
- 三套预置套牌（各占 `game/deck_defs/` 一文件，`__init__.py` 汇总 `DECK_DEF = DeckDef((基础, 剥削, 损坏))`）：
  - `<基础>`：标准 13 张，A=`(1,11)` 多值，其余 `points=(面值,)`，无效果。
  - `<剥削>`：点数分布同基础，2/3/4/5 带「打出效果:剥削1」（`on_play`）。机制：打出时所有其他玩家各付 1 进公共池。
  - `<损坏>`：点数分布同基础，6/7/8/9 带「终局效果:损坏」（`on_end`）。机制：轮末从活跃牌池移除（不进弃牌堆、本局剩余轮永久缺席）。

### 8.2 效果系统（`game/effects.py`，新增）
- `Effect(kind, level=0, params={})`：卡牌效果，三类（on_play/on_activate/on_end）。`强制` = `on_activate.params["forced"]=True`。
- `SlotEffect(kind, cost=0, params={})`：卡槽效果（on-place）。`cost` 为放牌费用（0=免费槽）。
- `EFFECT_REGISTRY: dict[str, Callable]`：按 `kind` 查执行器，签名 `executor(scene, actor_idx, slot_idx, card, effect) -> None`。新增效果 = 加一条注册，不改 Card/Suit 结构。给商店覆盖接口留口子（§16）。
- 栈模型判定函数：`slot_can_place(slot, card)`（可放）/ `slot_is_occupied(slot)`（栈顶非空壳牌，5 槽满判定）/ `slot_is_open(slot)`（与具体牌无关的「还能否放牌」，双重检查自动 pass 与 AI 选槽用）/ `is_shell_card` / `is_forced_activate`。
- 已知执行器（`scenes/game21.py` 末尾 `_register_known_effects` 注册，幂等）：剥削（on_play，他人各付 level）、损坏（on_end，记日志；移除由 `_trigger_on_end` 收集）、空壳（无操作，参与 `slot_can_place` 判定）。

### 8.3 场景状态机（`game21.py`）
- `Side(slots, sleeve, gold, passed, pass_score)`：一方的 **5 个卡槽**（`list[Slot]`，`Slot.cards: list[Card]` 有序栈 + `slot_effect: SlotEffect|None`，只读 `table` 视图派生为扁平所有牌）/ 袖子（≤2，跨轮保留）/ 金币（软上限 20）/ 软 pass 标志 + 记录的总点数。
- `Game21Scene` 持有 `self.players: list[Side]`（`[human, ai]`，取代硬编码 player/ai，多人兼容；`player`/`ai` 为只读属性别名）、`self.pool: int`、`self.round_num: int`、`self.current: int`（当前玩家索引）、`self.deck: list[Card]`（抽牌堆）、`self.discard: list[Card]`（弃牌堆）。
- `phase`：`menu`（玩家回合主菜单）→ `holding`（刚抽到牌，待决定打出/藏袖子）→ `discard`（袖子已满藏牌时手动选弃）→ `sleeve_select`（选袖子牌打出）→ `slot_select`（选目标卡槽放牌，←→ 切换、回车确认）→ `activate_prompt`（放牌后问是否激活，**Y/N**，强制牌跳过、爆牌跳过）→ `ai_turn` → `round_settled`（轮结算，任意键进下一轮）/ `game_over`（游戏结束，任意键返回主菜单）。
- 规则要点见 §14/§16/§17。

### 8.4 tick 钩子 + 时间队列（AI 延迟动画）
- 事件驱动主循环无内置定时器；用 `on_tick(now)` 每帧驱动场景内 `_tasks: list[(due, fn)]`。
- `schedule(delay, fn)` 追加任务；`on_tick` 取出到期任务执行，任务可再 `schedule` 下一步（AI 每步间隔 `AI_STEP_DELAY=0.7s`）。
- 任务只修改场景内部状态，不返回 SceneResult（结算面板的“任意键继续”仍由按键驱动）。
- POP 后场景实例不再被 tick，残留任务自然失效。

### 8.5 AI 启发式（`_ai_act`，遵循与玩家相同的约束）
- 状态机守卫：已 pass/busted → 结束回合；桌满无处放 → 强制 pass；本回合已抽牌 → 必须打出（继续抽）。
- 点数层：≥17 大概率（85%）停牌；≤11 必抽；12-16 按距 21 缺口与玩家可见点数概率抽，玩家已停且点数更高时被迫追。
- 经济层：抽牌前评估付费卡槽能否承担（`_ai_find_affordable_slot` 换可放且付得起的槽）；藏牌时 `gold < HIDE_COST(2)` 不藏。
- 效果层：按效果 `kind` 硬编码启发式（每机制一个决策函数，参数化 `level` 与选择对象）；受效果约束（强制激活就激活）。
- 软 pass 层：被取消 pass 后重新按点数启发式决策。
- 激活选择：on_activate 按启发式（对自己有利才激活）；v1 尚无已知 on_activate 执行器，默认**不激活**（保守），强制牌已在放牌时序中直接激活。
- 多轮意识：无望局面（`gold ≤ 2` 且点数 < 12）pass 认输省金币。
- AI 走与玩家相同的放牌时序（`_ai_try_place`：付卡槽费用→卡槽效果→on_play→可能取消人类 pass→激活），但不进 `slot_select`/`activate_prompt` 阶段。

### 8.6 渲染（100×30）
- 上：AI 区（点数、金币、爆牌/停牌标记 + 5 个卡槽明牌 + 袖子暗牌 ▓）；行1 右侧补 `牌堆/弃牌/公共池` 计数，标题栏含 `第N轮`。
- 中：状态/回合提示（`_status_text`）+ 握牌区（holding/slot_select/discard/sleeve_select/activate_prompt 时居中显示当前持有牌）。
- 下：玩家区（5 个卡槽明牌、袖子明牌、点数/金币/停牌标记）。
- 牌宽 `CARD_W=8`（加宽以容纳多值标签如 `1|11`）；多值牌牌面显示 `tag`；空壳叠放显示栈顶牌 + `×N` 计数。
- 卡槽编号旁标注卡槽效果与费用（如 `[4剥削·1金]`，金色；空槽显 `[n]`）。
- 卡槽焦点颜色（`slot_select` 且 owner=player）：**金色边框=空槽/空壳顶可放置**，**红色边框=栈顶非空壳（放置会失败）**；非选择阶段不高亮。←→ 切换焦点，1-5 直选。
- 操作面板（menu/holding/discard/sleeve_select/slot_select/activate_prompt/ai_turn 各自布局，焦点高亮）+ 最近 2 条日志。
- `round_settled`：居中 overlay 面板，揭晓双方点数与金币明细、本轮胜负，任意键进入下一轮。
- `game_over`：居中 overlay 面板，按最终金币最多者判胜负，任意键返回主菜单。

---

## 14. 经济与多轮系统（阶段 7）

### 14.1 金币
- 每方持有 `gold`，基础额 = 20（`START_GOLD`，**软上限** `GOLD_CAP=20`）。
- 软上限语义：轮内可超 20（如卡牌效果从公共池拿钱）；**轮末结算后丢弃超额到 ≤20**（加速游戏收敛）。
- 所有玩家支付的金币进**单一公共池** `self.pool`。
- 经济方法挂场景：`_pay(who, amt) -> int`（扣款进池，不足全交，返回实付）、`_settle_pool(winners)`（分池，平分向下取整余数丢弃）、`_clamp_gold()`（轮末丢弃超额）。底注在 `_begin_round` 内直接调用 `_pay`（`ante = round_num * 2`），无独立 `_ante()`。

### 14.2 多轮
- 每轮开始所有玩家交**底注 = 轮数×2**（第1轮=2，第2轮=4…），不足则全交。
- 游戏结束条件 = **任一玩家金币归 0**（仅轮末第6步检查；底注抽干会触发结算→游戏结束，而非当场判负）。
- 终局胜负 = 现存金币最多者胜（`_begin_game_over` 取 `max(gold)`），并列则同胜。
- 玩家金币跨轮保留；袖子跨轮保留（§16）。先手每轮随机（`_rng.random() < 0.5`）。

### 14.3 轮末事件顺序（不可变）
1. **21 结算**（`_resolve_winners`，决胜链见 §14.5）。
2. **终局效果**（`_trigger_on_end`）：所有玩家卡槽上的牌触发终局效果。损坏牌此刻从活跃牌池移除（不进弃牌堆、本局剩余轮永久缺席）。触发顺序：**按卡槽号横向触发**——先所有玩家的卡槽1，再卡槽2，…直到卡槽5（卡槽上多张牌时按叠放顺序触发各自 on_end）。
3. **分池**（`_settle_pool`）：唯一胜者独得整池；21 平局按决胜链平分（向下取整，余数从游戏内丢弃）。
4. **轮末整理**：桌面牌（未被移除的）→ 弃牌堆；袖子保留；抽牌堆/弃牌堆各自留。清空卡槽、重置 passed/pass_score。
5. **丢弃超额金币**（`_clamp_gold`）：每方 gold >20 的部分丢弃。
6. **0 检查**：有人在 0 → 游戏结束（比谁钱多）；否则进入下一轮（交底注）。

### 14.4 洗牌规则（重写）
- 旧「牌堆抽空→重建全新牌堆」**作废**。
- 新规则：抽牌堆抽空 → 将**弃牌堆**洗牌成为新抽牌堆。**袖子里的牌不洗、不进弃牌堆**（袖子是独立的持久持有区）。
- 牌的归属区：抽牌堆 / 弃牌堆 / 桌面（卡槽栈）/ 袖子（跨轮持久）。
- **风险（R2）兜底**：袖子跨轮保留 + 损坏移除 → 共享牌组可抽总量逐轮减少。已落地兜底：抽牌堆与弃牌堆**双空**时，`_draw_from_deck` 重建一副新的共享牌组（`DECK_DEF.sample_for`）保证游戏不卡死——属与玩家约定的未定义行为，留待实测后可改为更严格规则。

### 14.5 21 决胜链（定胜者，`_resolve_winners`）
- 基底：不爆牌前提下最接近 21。
- 爆牌者负；全员爆牌则点数最小者胜。
- 未爆者中点数最高者胜。
- 最高点数被 ≥2 人并列**且正好=21** → 组成 21 的桌面牌**张数少者**胜（不含袖子）→ 仍并列则**单张最大点数大者**胜（`_max_single_point`，取每张牌 `points` 最大候选，A 算 11；详见 §15.3）→ 仍并列则平分池。
- 并列但非 21 → 直接平分池。
- 唯一胜者独得整池。

---

## 15. 套牌与卡牌系统（阶段 7）

### 15.1 套牌（Suit）
- 一套牌 = 一种花色 + 自带一组牌（牌数/点数可非标准）。每套一个文件（`game/deck_defs/`）。
- 套牌间**职责不重叠**（只一套管负点数等），靠分工保证 21 总体可达；不做套牌间数值平衡（共享牌组下强弱对所有人等概率）。
- `archetype` 标签纯描述、不参与数值。
- **共享牌组**：开局从所有套牌中抽 = 玩家数 的若干套，合并成单一共享牌组，所有玩家从中抽牌。2 人局抽 2 套。

### 15.2 卡牌效果（三类）
- `on_play`（打出效果）：放牌入栈、卡槽效果触发后触发。如剥削：其他玩家各付 level 进公共池。
- `on_activate`（激活效果）：放牌完成后立刻询问是否发动，**免费**。`强制`词条 = 有 on_activate 则必须激活、无选择权。爆牌跳过激活。
- `on_end`（终局效果）：轮末第2步触发。如损坏：从活跃牌池移除。
- 效果数据契约见 §8.2（`Effect` / `SlotEffect` / `EFFECT_REGISTRY`）。
- 已知效果表（首版仅此三类 + 框架，未定效果留 registry 接口、表来了逐条注册）：
  - 剥削（on_play，`level`=付费额）：打出时所有其他玩家各付 level 进公共池。
  - 损坏（on_end）：从活跃牌池移除。执行器仅记日志，实际移除由 `_trigger_on_end` 按 `kind` 统一收集后剔除（不进弃牌堆）。
  - 空壳（被动，无执行逻辑）：参与可放牌判定（见 §16），其执行器为空操作。

### 15.3 决胜单张点数（`_max_single_point`）
- 21 并列决胜的「单张最大点数大者胜」环节，实现简化为：取该方桌面每张牌 `points` 候选里的**最大值**（A 算 11），再取所有牌中的最大。非严格「结算采用组合里的值」，但首版套牌均为标准点数，结论等价；怪套/负点数套若引入需复核。

---

## 16. 卡槽栈模型（阶段 7）

### 16.1 数据结构升级
- `Side.slots` 从 `list[Card|None]` → `list[Slot]`（5 个）。
- `Slot.cards: list[Card]`（有序栈，最后一张=栈顶）+ `slot_effect: SlotEffect|None`。
- `Side.table`（只读视图）= 扁平所有卡槽所有牌 `[c for s in slots for c in s.cards]`，供点数计算/决胜。
- 单人开局第4、5卡槽**随机获得卡槽效果**（从卡槽效果表抽）。**实现现状**：v1 尚无卡槽效果表，`_random_slot_effect()` 暂返回 `None`（空槽无费用），第 4、5 槽保持空白占位，等效果表来逐条注册后即生效。
- 留**商店接口**：未来可购买卡槽效果覆盖某槽 `slot_effect`（赋值即可）。

### 16.2 空壳机制
- **空壳牌**：其上可继续叠牌的牌。
- **空壳卡槽效果**：该槽可无限叠牌。
- **可放牌判定**（替代旧「占用即失败」）：
  - 空槽 → 可放（任意牌）。
  - 栈顶是空壳牌 → 可放（任意牌）。
  - 该槽有空壳卡槽效果 → 永远可放（无论栈顶）。
  - 栈顶是非空壳牌 → **不可放**（失败重选，沿用旧交互）。
- **"是否占据" ⟺ 栈顶是非空壳牌**（用于「5槽放满无处放须 pass」判定）。
- **点数**：栈里所有牌都算，叠越多越易爆（空壳牌也贡献点数，是叠放的代价）。无堆叠张数上限。
- 放牌始终选槽位（不选叠在某张牌上）。

### 16.3 卡槽效果触发
- on-place 一次性、绑槽不绑牌。每次放牌触发一次。
- **独立实例、数值结果自然叠加**：每次触发是独立效果实例，但数值结果会累加（往+1金币槽放3张→+3）。
- 空槽无效果（卡槽效果在放牌时才触发）。

### 16.4 一次放牌完整时序
1. 选槽（slot_select；AI 由 `_ai_try_place` 自动挑可放且付得起的槽）。
2. 校验可放（栈顶空壳/空槽/空壳效果槽；否则失败重选）。
3. 付卡槽费用（若 `slot_effect.cost>0`）：够付→扣款进公共池；不够→拒绝、停留重选。
4. 消耗来源牌（`held_card` 置空 / 从袖子 `pop`）。
5. 放牌入栈 `slot.cards.append(card)`。
6. 触发卡槽效果（on-place）。
7. 触发打出效果（on_play，如剥削）→ **软 pass 取消扫描**（他人总点数被改则取消 pass）。
8. 重算点数（爆牌**不立即结算**，仅记日志标记危险态）。
9. 激活效果询问（on_activate）：放牌完成后立刻问，免费；`强制`牌必须激活（直接执行不询问）；爆牌跳过激活。玩家进 `activate_prompt`（Y/N），AI 走 `_ai_resolve_activate`（默认不激活）。激活若执行效果同样触发软 pass 取消扫描。
10. 自动结束 turn（出牌→结束，§17）。
- AI 走与玩家完全相同的时序（`_ai_try_place`），但不进 `slot_select`/`activate_prompt` 阶段。

---

## 17. 回合与软 pass 模型（阶段 7，最重大改写）

### 17.1 核心改写
- **爆牌不立即结算**：点数 >21 只是危险态，可抽负点数牌自救。结算时仍爆才判负。
- **操作结束 ⟺ pass**：一个 turn = **出牌 或 pass 二选一**（互斥）。
  - **出牌**（抽来的牌或袖子牌）成功打出后**自动结束 turn**。
  - **pass** = settle down，不打任何牌（0 点 pass 也合法，无「空过」概念）。
  - 出牌与 pass 互斥：出牌改变点数（可能影响他人），pass 不改点数——**不可能同动作既改点数又 pass**。

### 17.2 抽牌锁定（新形态）
- **抽牌与 pass 互斥**：选了抽牌 → 本 turn 必须打出一张牌（不能 pass）。
- 藏牌不结束 turn（沿用）。出袖子牌也算出牌、自动结束 turn。
- 费用：**抽牌免费 / 藏牌 2 金 / pass 免费**。

### 17.3 软 pass
- pass 后进入冻结态，被动取消（玩家无感）。记录 `pass_score = score()[0]` 作为取消比对基准。
- **取消触发 = 只看总点数数值变化**：`_after_effect_cancel_pass` 在每次效果结算后扫描所有 passed 玩家，`score()[0] != pass_score` → 系统自动取消其 pass（`passed=False`、清 `pass_score`）。交换牌但点数不变则**不**取消。
- pass 取消后**不立即插队**，等当前行动方回合结束（多人时等前方所有玩家回合结束）。
- **结算触发 = 所有人都 pass**，**只在 pass 动作后检查一次**（`_end_turn` 入口，不做每动作检查）。前提：点数变动导致的他人 pass 取消必须及时（效果结算后立刻改他人 `passed`）。
- **风险（R1）**：若日后某效果能「无限次改变对方点数而不推进局面」可能死循环；靠效果设计规避，系统层不加上限。

### 17.4 回合推进
- 固定行动顺序（2人：玩家↔AI；多人：座次），轮到当前 pass 的玩家则跳过。
- 未 pass 玩家行动，行动结束（出牌或 pass）后交下一位。
- pass 被取消的玩家重新进入待行动队列（等当前行动方结束）。
- 先后手每轮随机（影响减弱：谁后 pass 谁触发结算）。

### 17.5 双重检查自动 pass
- 抽牌前检查 + 回合结束时检查。
- 若**无可用槽**（无空槽、无栈顶空壳、无空壳效果槽）且非 pass → **自动结束回合并设为 pass**。
- 袖子满 + 槽满 = 无处可放 → 自动 pass 兜底。
- 不变式：进入抽牌前的预检保证玩家抽牌后总有处可放或已 pass。

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
  - 下方：本局牌组构成网格——按 `DECK_DEF.suits` 的套牌顺序排成行、rank 排成列（实际套牌数，非固定 4×13），按牌当前归属（抽牌堆 / 你-桌面 / 你-袖子 / AI-桌面 / AI-袖子 / 弃牌堆 / 已出）着色。
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
- `test_render_smoke.py`：主菜单/百科/Message/21 点各阶段（含 menu/holding/discard/sleeve_select/slot_select/activate_prompt/ai_turn/round_settled/game_over）渲染不抛；Tab overlay 渲染与隐写解码；以及 21 点新规则行为：5 卡槽栈默认空、`table` 只读视图、抽牌锁定（pass/出袖子被禁、藏牌不结束回合、打出才结束）、栈顶非空壳槽放置失败重选、←→ 焦点循环、袖子满手动弃、袖子牌打出进卡槽、AI 能推进到结算、底注收费与缩放、底注不足全交、金币归 0 触发游戏结束、软 pass 取消（点数变才取消 / 同点数不取消）、双重检查自动 pass、空壳槽允许叠放、决胜链（唯一高点 / 爆牌者负 / 21 平局张数少者 / 21 平局平分）、抽牌堆耗尽洗弃牌堆、overlay 位置追踪与空牌堆、Tab 开关。

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
