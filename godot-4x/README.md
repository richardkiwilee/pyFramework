# TheGreatConquest — Godot 版本

Python 原型（`pyProjects/4x/pydemo`）的 Godot 移植，实现规格见 `../pyProjects/4x/游戏规格.md`（本文档为契约）。

## 架构：布局 / 图形 / 数据 分离 + 现代 4X 界面

- **主界面切换**（主菜单 ↔ 游戏 ↔ 百科全屏）：`SceneStack.change_scene` —— 旧场景销毁，无残留。
- **子界面**：每个功能是**独立 Window 场景**（`scenes/windows/*.tscn`），模态弹出、
  可拖动/调整大小/关闭，可在编辑器单独 F6 调试；关闭回值经 `return_window` 交付。
- **鼠标优先**（现代 4X 布局）：
  - 大地图：美术底图 + 滚轮缩放 + 左键拖动摄像机；点据点 → 底部中间信息栏
    （方形信息 + 建筑槽位，点槽位弹建造选项）；点部队小人 → 拉起箭头，
    点相邻目标移动，右键取消。
  - 顶栏：全局资源（图标占位 + 下回合变更）+ 右侧 百科/日志/设置 按钮。
  - 左下角：图标按钮（科技文化 / 管理小队 / 招募单位）。
  - 键盘导航保留为辅助（↑↓ 焦点、回车确认、ESC 关闭）。

```
godot-4x/
├── data/                  # 数据层：声明式 JSON（从 pydemo/data 复制，含 mod 覆盖支持）
├── assets/map_bg.png      # 大地图美术底图（tools/gen_map_bg.gd 生成，可换真实美术）
├── scripts/core/          # 逻辑层：纯 GDScript，无任何界面依赖（对应 pydemo/game/ + scenario）
│   ├── game.gd            #   Game 核心编排（全部 action_* 接口 + 存档 snapshot/restore）
│   ├── map_system.gd      #   地图：据点坐标 + 道路（坐标对 + 曲线信息）
│   ├── battle.gd / ai.gd  #   Tick 战斗引擎 / 贪心 AI
│   └── ...                #   日历/经济/单位/部队/修正/效果/时点/策略/羁绊/事件
├── scripts/ui/            # 图形层：功能图形组件（每个功能一个文件）
│   ├── frame.gd           #   程序生成边框面板（美术替换点）
│   ├── map_view.gd        #   大地图视图（底图/缩放/拖动/虚线道路/据点/部队小人）
│   ├── icon_button.gd     #   矢量图标按钮（科技/小队/招募/百科/日志/设置）
│   ├── list_widget.gd / grid9.gd / text_info.gd / hint_bar.gd / log_bar.gd
│   └── base_screen.gd / base_window.gd   # 场景基类 / 窗口基类（含右上角定位）
├── scenes/                # 布局层：场景 = 用容器把图形组件组合成界面
│   ├── main_menu.tscn / game_screen.tscn / wiki.tscn   # 全屏主场景
│   └── windows/*.tscn     # 子界面：独立 Window 场景（可单独调试）
│       ├── tech_culture.tscn       # 科技/文化合一（顶部居中切换 + 横向卷轴树）
│       ├── army.tscn               # 管理小队（在队/待命切换 + 单位详情）
│       ├── recruit.tscn            # 招募（三等分三栏 + 招募按钮）
│       ├── stronghold / stronghold_overview / unit_roster / inventory
│       ├── log_window.tscn         # 日志（右上角弹出、滚轮滚动）
│       ├── settings_window.tscn    # 设置（居中：语言/改键/存档/回主菜单）
│       └── esc_menu / event_dialog / message / equip_picker / map_screen / recruit_unit
├── scripts/scenes/        # 场景脚本
│   ├── game_screen.gd     # 大地图主场景（顶栏资源/按钮/据点信息栏/建造浮层/Toast）
│   ├── tree_screen.gd     # 科技文化树（文明系列样式：卡片+前置连线+拖动/滚轮）
│   └── boot.gd            #   启动入口（`-- --ui-smoke` 跑 UI 冒烟）
├── autoload/              # 单例（模块级解耦，对应 pydemo/tui/controller.py）
│   ├── game_controller.gd #   Game 单例 + 回合编排 + 日志 + 存档
│   ├── scene_stack.gd     #   主场景切换 + 子窗口栈
│   ├── input_bindings.gd  #   按键绑定唯一映射点（设置窗可运行时改键，持久化）
│   ├── ui_theme.gd        #   颜色/字体/主题（美术替换点）
│   └── loc.gd             #   i18n（中英切换，L 键/设置窗）
├── i18n/en.csv            # 英文词表（中文源串为 msgid）
├── tests/run_tests.gd     # 逻辑层 headless 测试（117 断言）
└── tools/gen_map_bg.gd    # 地图底图生成器（一次性工具）
```

## 可替换性接口（规格 §2）

| 接口 | 位置 | 说明 |
|------|------|------|
| 按键 | `autoload/input_bindings.gd` | 动作名 ↔ 物理键唯一映射；设置窗可点击改绑（持久化到 user://keybindings.cfg） |
| 语言 | `i18n/en.csv` + `autoload/loc.gd` | 中文源串为 msgid；数据名（单位/建筑/资源）也走翻译 |
| 美术 | `assets/map_bg.png` + `map_view.gd` + `icon_button.gd` + `ui_theme.gd` | 底图为生成式（`tools/gen_map_bg.gd` 重跑可换种子）；换真实美术时覆盖图片/换成 TextureRect 即可 |
| 数据 | `data/*.json` + `scripts/core/data_loader.gd` | mod 层叠覆盖（`mods/` 目录同名 id 整条覆盖） |

## 运行

```bash
# 编辑器
D:\Godot\Godot_v4.6.2-stable_win64.exe --path .

# 逻辑层测试（headless，exit 0 = 过）
D:\Godot\Godot_v4.6.2-stable_win64_console.exe --headless --path . -s tests/run_tests.gd

# UI 冒烟（启动 → 主菜单 → 开新局 → 逐窗口打开 → 地图交互 → 结束回合）
D:\Godot\Godot_v4.6.2-stable_win64_console.exe --headless --path . -- --ui-smoke
```

## 大地图交互

- **滚轮**：缩放（朝光标）；**按住左键拖动**：平移摄像机。
- **左键点据点**：底部中间弹出信息栏（方形信息 + 右侧建筑槽位）；再点同据点关闭。
- **点建筑槽位**：空槽 → 弹建造选项；已建 → 拆除。
- **左键点部队小人**：选中并拉起引导箭头；**点相邻目标**移动过去；**右键**取消。
- 道路以虚线绘制（坐标对 + 曲线信息存档持久化）。

## 与 Python 原型的对应关系

- 逻辑层逐模块对应 `pydemo/game/`，动作返回中文消息（源语言）；行为经 117 断言与全自动冒烟对局验证（玩家可胜出）。
- 交互层对应 `pydemo/tui/` 场景语义：PUSH/POP + 回值通道（`return_window`）。
- 事件弹窗交互式（玩家自由选择）；资源净变动细项以悬停弹窗呈现。
- 科技/文化树、管理小队、招募界面按现代 4X 布局重做（文明系列样式）。
