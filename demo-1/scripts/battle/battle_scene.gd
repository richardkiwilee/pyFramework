extends Control
## =============================================================================
## BattleScene — 战斗播放场景的 UI 控制器
## =============================================================================
## 作用：接收 BattleManager 的信号和行动数据，以动画方式逐步播放战斗过程。
##       包括单位卡片显示、战斗日志、伤害动画、结果总结等所有 UI 元素。
##
## 和 BattleManager 的关系：
##   BattleManager — 纯数据+逻辑层（不关心 UI）
##   BattleScene   — 纯 UI 层（不修改战斗逻辑）
##
##   两者通过以下方式通信：
##     1. 信号：BattleScene 连接 BattleManager 的信号
##        · battle_started  -> _on_battle_started()
##        · round_started   -> _on_round_started()
##        · battle_ended    -> _on_battle_ended()
##     2. 轮询：Timer 定时调用 BattleManager.next_action()
##        获取下一个待播放的行动
##
## =============================================================================
##  战斗 UI 的播放时序（Timing of Battle Playback）
## =============================================================================
##
## 战斗不是"即算即播"的，而是使用 Timer 驱动的"逐行动播放"模式。
## 理解这个时序对理解整个战斗 UI 至关重要。
##
## +------------------------------------------------------------------+
## | 时间线（每个单位行动 = 一次 Timer tick = 0.9 秒）                 |
## +------------------------------------------------------------------+
## |                                                                  |
## |  _ready()                                                        |
## |    |                                                             |
## |    +- 连接 BattleManager 信号                                    |
## |    +- 配置 Timer（wait_time=0.9, one_shot=false）               |
## |    +- 调用 BattleManager.begin_combat()                           |
## |    |                                                             |
## |  begin_combat() 内部:                                            |
## |    +- battle_started.emit()  ----------------------+             |
## |    |    -> _on_battle_started() 收到                   |             |
## |    |      +- _build_unit_displays() 创建单位卡片     |             |
## |    |      +- 日志"战斗开始！"                        |             |
## |    |      +- action_timer.start() 启动计时器 !!!!!     |             |
## |    |                                                |             |
## |    +- _start_next_round()                           |             |
## |       +- round_started.emit(1)  ------------------+ |             |
## |    |       |  -> _on_round_started(1) 收到             | |             |
## |       |  -> 日志"第1回合"                            | |             |
## |       |                                            | |             |
## |    |       +- 预计算所有行动，填充 _pending_actions    | |             |
## |    |                                                 | |             |
## |  +---- Timer 开始循环（每 0.9 秒）-----------------+ |             |
## |  |                                                  |             |
## |  |  Timer tick #1 -> _on_action_tick()               |             |
## |    |    |                                             |             |
## |    |    +- action = BattleManager.next_action()       |             |
## |    |    |  返回第一个行动的 Dictionary                 |             |
## |    |    |                                             |             |
## |    |    +- _play_action(action)                       |             |
## |    |    |  +- _add_log("A -> B  [技能]  -30 HP")       |             |
## |    |    |  +- _animate_hit() 屏幕震动                  |             |
## |    |    |  +- _flash_unit(A, GOLD) 闪烁金色            |             |
## |    |    |  +- _flash_unit(B, RED) 闪烁红色             |             |
## |    |    |  +- _refresh_display_from_action()          |             |
## |    |    |     更新血条/HP文字/AP/状态                  |             |
## |    |    |                                             |             |
## |    |  Timer tick #2 -> ... (下一个行动)                 |             |
## |    |  ...                                             |             |
## |    |  Timer tick #N -> next_action() 返回 {}            |             |
## |    |    -> 队列空了，回合结束                            |             |
## |    |    -> _check_battle_end() 检查胜负                 |             |
## |    |    -> 未结束: _start_next_round() 开始新回合       |             |
## |    |    -> round_started.emit(2)                        |             |
## |    |  ...继续循环直到战斗结束...                        |             |
## |    |                                                  |             |
## |    |  战斗结束:                                        |             |
## |    |    battle_ended.emit("victory"|"defeat")          |             |
## |    |    -> _on_battle_ended()                           |             |
## |    |      +- action_timer.stop() 停止计时器             |             |
## |    |      +- 显示"返回编成"按钮                         |             |
## |    |      +- _show_summary() 显示战斗统计               |             |
## |    |                                                  |             |
## +------------------------------------------------------------------+
##
## wait_time = 0.9 秒的选择：
##   0.9 秒是"节奏感"的平衡。太快则看不清动画，太慢则战斗拖沓。
##   对于自动战斗（玩家不操作），0.9 秒让玩家能跟踪战斗进展但不感到等待。
## =============================================================================

# ==================================================================
#  @onready 节点引用
# ==================================================================
## @onready 变量在 _ready() 执行前初始化，确保 $ 路径在节点进入场景树后有效。
## 如果直接在声明时赋值 $Path，那时节点可能还没进入场景树。

## 回合标签 "第 N 回合"
@onready var round_label: Label = $Header/RoundLabel

## 玩家/敌方单位卡片容器
@onready var player_grid: VBoxContainer = $BattleArea/PlayerSide/UnitGrid
@onready var enemy_grid: VBoxContainer = $BattleArea/EnemySide/UnitGrid

## 战斗日志列表（滚动显示）
@onready var battle_log: VBoxContainer = $LogPanel/ScrollContainer/LogList

## 战斗结果覆盖层（默认隐藏，战斗结束后显示）
@onready var result_overlay: Control = $ResultOverlay

## 行动播放计时器 — 驱动整个战斗播放的"心跳"
@onready var action_timer: Timer = $ActionTimer

## "返回编成"按钮（默认隐藏，战斗结束后显示）
@onready var return_btn: Button = $ReturnBtn

## "查看统计"按钮（代码动态创建，战斗结束后显示在右下角）
var view_stats_btn: Button

## "复制日志"按钮（代码动态创建，战斗结束后显示在右下角）
var copy_log_btn: Button

## 存储战斗结果（延迟到用户点击"查看统计"时使用）
var _battle_result: String = ""
var _battle_stats: Dictionary = {}

## 结果面板的子控件
@onready var summary_player: VBoxContainer = $ResultOverlay/Panel/VBox/PlayerStats
@onready var summary_enemy: VBoxContainer = $ResultOverlay/Panel/VBox/EnemyStats
@onready var summary_header: Label = $ResultOverlay/Panel/VBox/SummaryHeader
@onready var summary_total: Label = $ResultOverlay/Panel/VBox/TotalStats
@onready var summary_close_btn: Button = $ResultOverlay/Panel/VBox/CloseBtn

# ==================================================================
#  运行时状态
# ==================================================================

## 玩家单位卡片的引用列表 — Array[{unit: Dictionary, card: Control}]
## 用于快速通过 unit.name_zh 查找对应卡片进行闪烁/更新
var player_bars: Array = []

## 敌方单位卡片的引用列表
var enemy_bars: Array = []

## 战斗是否已结束（防止结束后继续处理 tick）
var battle_done: bool = false


# ==================================================================
#  _ready() — 初始化
# ==================================================================

func _ready() -> void:
	# --- 初始 UI 状态 ---
	result_overlay.visible = false   # 隐藏结果覆盖层
	return_btn.visible = false       # 隐藏返回按钮（战斗结束后显示）

	# --- 连接按钮信号 ---
	return_btn.pressed.connect(_on_return_to_formation)
	summary_close_btn.pressed.connect(_on_return_to_formation)

	# --- 连接 BattleManager 信号 ---
	BattleManager.battle_started.connect(_on_battle_started)
	BattleManager.round_started.connect(_on_round_started)
	BattleManager.battle_ended.connect(_on_battle_ended)

	# --- 配置行动计时器 ---
	action_timer.wait_time = 0.9
	action_timer.one_shot = false
	action_timer.timeout.connect(_on_action_tick)

	# --- 样式化按钮 ---
	_style_return_btn()

	# --- 创建右下角"查看统计"按钮（战斗结束后和 return_btn 一起显示）---
	view_stats_btn = Button.new()
	view_stats_btn.text = "查看统计"
	view_stats_btn.visible = false
	view_stats_btn.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
	view_stats_btn.add_theme_font_size_override("font_size", 13)
	view_stats_btn.begin_bulk_theme_override()
	view_stats_btn.add_theme_stylebox_override("normal", UITheme.default_button_style())
	view_stats_btn.end_bulk_theme_override()
	view_stats_btn.pressed.connect(_on_view_stats)
	add_child(view_stats_btn)

	# --- 创建右下角"复制日志"按钮 ---
	copy_log_btn = Button.new()
	copy_log_btn.text = "复制日志"
	copy_log_btn.visible = false
	copy_log_btn.add_theme_color_override("font_color", UITheme.INK2)
	copy_log_btn.add_theme_font_size_override("font_size", 12)
	copy_log_btn.begin_bulk_theme_override()
	copy_log_btn.add_theme_stylebox_override("normal", UITheme.default_button_style())
	copy_log_btn.end_bulk_theme_override()
	copy_log_btn.pressed.connect(_on_copy_log)
	add_child(copy_log_btn)

	# --- 将三个按钮定位到右下角 ---
	_position_bottom_buttons()

	# --- 启动战斗 ---
	BattleManager.begin_combat()


## 给返回按钮应用金色样式（和编成界面的"开始战斗"按钮风格一致）
func _style_return_btn() -> void:
	return_btn.add_theme_color_override("font_color", Color("2c1c0e"))  # 深棕文字
	return_btn.add_theme_font_size_override("font_size", 13)
	return_btn.begin_bulk_theme_override()
	return_btn.add_theme_stylebox_override("normal", UITheme.gold_button_style())
	return_btn.end_bulk_theme_override()

	# 结果面板的关闭按钮也应用相同样式
	summary_close_btn.add_theme_color_override("font_color", Color("2c1c0e"))
	summary_close_btn.add_theme_font_size_override("font_size", 14)
	summary_close_btn.begin_bulk_theme_override()
	summary_close_btn.add_theme_stylebox_override("normal", UITheme.gold_button_style())
	summary_close_btn.end_bulk_theme_override()


## 将 return_btn 和 view_stats_btn 定位到屏幕右下角
func _position_bottom_buttons() -> void:
	# copy_log_btn：右下角最左
	copy_log_btn.anchor_left = 1.0
	copy_log_btn.anchor_right = 1.0
	copy_log_btn.anchor_top = 1.0
	copy_log_btn.anchor_bottom = 1.0
	copy_log_btn.offset_left = -330
	copy_log_btn.offset_right = -235
	copy_log_btn.offset_top = -55
	copy_log_btn.offset_bottom = -20

	# view_stats_btn：右下角中间
	view_stats_btn.anchor_left = 1.0
	view_stats_btn.anchor_right = 1.0
	view_stats_btn.anchor_top = 1.0
	view_stats_btn.anchor_bottom = 1.0
	view_stats_btn.offset_left = -225
	view_stats_btn.offset_right = -135
	view_stats_btn.offset_top = -55
	view_stats_btn.offset_bottom = -20

	# return_btn：右下角最右（金色，最显眼）
	return_btn.anchor_left = 1.0
	return_btn.anchor_right = 1.0
	return_btn.anchor_top = 1.0
	return_btn.anchor_bottom = 1.0
	return_btn.offset_left = -125
	return_btn.offset_right = -15
	return_btn.offset_top = -55
	return_btn.offset_bottom = -20


## "查看统计"按钮回调
func _on_view_stats() -> void:
	if not _battle_stats.is_empty():
		_show_summary(_battle_result, _battle_stats)


## "复制日志"按钮回调 -- 收集所有日志文字并复制到系统剪贴板
func _on_copy_log() -> void:
	var lines: Array = []
	for child in battle_log.get_children():
		if child is Label:
			lines.append(child.text)
	var log_text = "\n".join(lines)
	if log_text != "":
		DisplayServer.clipboard_set(log_text)
		_add_log("📋 日志已复制到剪贴板")

# ==================================================================
#  Timer 回调 — 战斗播放的"心跳"
# ==================================================================

## ---------------------------------------------------------------------------
## _on_action_tick() — Timer 每次 timeout 时调用
## ---------------------------------------------------------------------------
## 这是战斗播放的主循环。每次 tick：
##   1. 调用 BattleManager.next_action() 获取下一个行动
##   2. 如果返回空 {}，说明当前没有行动可播放（回合间隙或战斗结束）
##   3. 如果返回有效行动，调用 _play_action() 播放
##
## 注意：next_action() 可能在一次调用中触发回合结束检测和下一回合开始，
##       但 Timer tick 的 0.9 秒间隔确保了 UI 有时间显示回合切换。
## ---------------------------------------------------------------------------
func _on_action_tick() -> void:
	# 战斗已结束，不再处理
	if battle_done:
		return

	var action = BattleManager.next_action()

	if action.is_empty():
		# 无行动可播放 — 可能是回合间隙或战斗结束
		# 不需要特别处理，等待下一个 timer tick 或 battle_ended 信号
		return

	# 播放该行动
	_play_action(action)


# ==================================================================
#  行动播放 (Action Playback)
# ==================================================================

## ---------------------------------------------------------------------------
## _play_action() — 播放一个行动
## ---------------------------------------------------------------------------
## 根据行动类型（kind）执行不同的 UI 表现：
##
##   "attack"  — 攻击行动：
##     · 写入战斗日志："⚡ 亚连 -> 敌人  [技能攻击]  -25 HP"
##     · 播放屏幕震动动画
##     · 攻击者闪烁金色（表示行动方）
##     · 目标闪烁红色（表示受伤方）
##
##   "death"   — 死亡行动：
##     · 写入战斗日志："💀 敌人 阵亡！"
##     · 死亡单位卡片变灰色
##
##   "skipped" — 跳过行动（行动者已阵亡）：
##     · 写入战斗日志："⏭ 敌人 行动取消（已在本回合被击杀）"
##
## 每种行动播放完后，调用 _refresh_display_from_action() 更新血条显示。
##
## GDScript 的 match 语句：
##   等价于 Python 3.10+ 的 match-case，或传统 switch-case。
##   比 if-elif-else 链更清晰。不需要 break（不会穿透）。
## ---------------------------------------------------------------------------
func _play_action(action: Dictionary) -> void:
	match action.kind:
		"attack":
			# --- 1. 主日志行 ---
			var ap_cost = action.get("ap_cost", 0)
			var pp_cost = action.get("pp_cost", 0)
			var icon := "⚡"
			var dmg_type = action.get("damage_type", "physical")
			if dmg_type == "heal": icon = "✨"
			elif dmg_type in ["buff", "shield"]: icon = "🛡️"
			elif dmg_type in ["debuff", "utility"]: icon = "🔮"

			_add_log("%s %s 消耗%dAP 使用 [%s]" % [
				icon, action.actor_name, ap_cost, action.skill_name
			])

			# --- 2. 每个目标一行 ---
			var hits = action.get("hits", 1)
			for t in action.get("targets", []):
				if t.get("heal", 0) > 0:
					_add_log("   ✅ %s 恢复 %d HP (HP %d/%d)" % [t.name, t.heal, t.hp, t.max_hp])
				elif t.get("damage", 0) > 0:
					var dmg_str := "%d" % t.damage
					if hits > 1:
						dmg_str += " (%d段)" % hits
					if t.get("alive", true):
						_add_log("   💥 %s 受到 %s 伤害 (HP %d/%d)" % [t.name, dmg_str, t.hp, t.max_hp])
					else:
						_add_log("   💀 %s 受到 %s 伤害，阵亡！" % [t.name, dmg_str])
				else:
					_add_log("   🔮 %s（效果暂未实现）" % t.name)

			# --- 3. 被动触发 ---
			var passive_name = action.get("passive_name", "")
			if passive_name != "" and pp_cost > 0:
				_add_log("🔵 %s 消耗%dPP 触发被动 [%s]" % [
					action.actor_name, pp_cost, passive_name
				])

			# --- 动画 ---
			_animate_hit(action)
			_flash_unit(action.actor_name, UITheme.GOLD_BRIGHT)
			if dmg_type == "heal":
				_flash_unit(action.target_name, UITheme.GREEN)
			elif action.get("target_alive", true):
				_flash_unit(action.target_name, UITheme.RED)
			else:
				_flash_unit(action.target_name, Color.GRAY)

		"death":
			_flash_unit(action.actor_name, Color.GRAY)

		"skipped":
			_add_log("⏭ %s 行动取消（已在本回合被击杀）" % action.actor_name)

		"wait":
			_add_log("⏸ %s 资源不足，本回合待机" % action.actor_name)

	_refresh_display_from_action(action)


## ---------------------------------------------------------------------------
## _flash_unit() — 单位卡片闪烁效果
## ---------------------------------------------------------------------------
## 改变卡片的 modulate 颜色，然后通过 Tween 渐恢复到原来的颜色。
## 整个过程约 0.4 秒。
##
## modulate 属性说明：
##   modulate 是 CanvasItem 的颜色调制属性。它和原始颜色相乘。
##   白色 modulate（默认） = 保持原始颜色。
##   红色 modulate = 画面变红。
##   灰色 modulate = 画面变灰。
##   类似于在图片上叠加一层半透明颜色滤镜。
##
## Tween 说明：
##   create_tween() 创建一个新的 Tween 实例。
##   tween_property(obj, "property", final_value, duration)
##   在 duration 秒内将 obj 的 property 平滑过渡到 final_value。
## ---------------------------------------------------------------------------
func _flash_unit(unit_name: String, color: Color) -> void:
	# 在玩家和敌方卡片列表中查找匹配的单位
	for entry in player_bars + enemy_bars:
		if entry.unit.name_zh == unit_name:
			var card = entry.card
			var orig_mod = card.modulate  # 保存原始 modulate
			card.modulate = color         # 立即设置闪烁颜色
			# 在 0.4 秒内平滑恢复原始颜色
			var tween := create_tween()
			tween.tween_property(card, "modulate", orig_mod, 0.4)
			break  # 找到就退出，名字唯一


## ---------------------------------------------------------------------------
## _animate_hit() — 受击屏幕震动效果
## ---------------------------------------------------------------------------
## 微调场景根节点的 position.x，产生类似"镜头震动"的效果。
## 左右快速晃动的参数序列：+4 -> -4 -> +2 -> 0
## 整个震动约 0.13 秒（0.03 + 0.03 + 0.03 + 0.04）。
##
## 注意：这个方法修改的是 self（BattleScene 控件自身）的 position，
##       所以是整个战斗界面的震动。如果只想震目标卡片，应该震动卡片。
##
## Tween 链式调用：
##   每个 tween_property 返回一个 Tween，可以链式 .set_delay() 等。
##   多个 tween_property 调用创建的是一个顺序动画序列：
##   先完成第一个 -> 再第二个 -> 再第三个 -> 再第四个。
## ---------------------------------------------------------------------------
func _animate_hit(_action: Dictionary) -> void:
	var orig_pos = position
	var tween := create_tween()
	# 向右偏移 4 像素，0.03 秒
	tween.tween_property(self, "position:x", position.x + 4, 0.03)
	# 向左偏移 4 像素（相对于原始位置），0.03 秒
	tween.tween_property(self, "position:x", position.x - 4, 0.03)
	# 向右偏移 2 像素，0.03 秒
	tween.tween_property(self, "position:x", position.x + 2, 0.03)
	# 回到原位，0.04 秒（稍慢的恢复）
	tween.tween_property(self, "position:x", orig_pos.x, 0.04)


## ---------------------------------------------------------------------------
## _refresh_display_from_action() — 根据行动数据刷新 UI
## ---------------------------------------------------------------------------
## 行动中包含目标单位的状态快照（hp, alive 等），
## 这里把这些快照应用到 UI 卡片的显示上。
##
## 注意区分：
##   BattleManager 中的 unit Dictionary 是"权威数据源"。
##   _update_unit_bar 会修改 unit.hp 等字段，这些修改是对 BattleManager
##   中同一 Dictionary 的直接修改（因为 Dictionary 是引用类型）。
##   所以 UI 的更新会同步反映到 BattleManager 的状态中。
## ---------------------------------------------------------------------------
func _refresh_display_from_action(action: Dictionary) -> void:
	# wait/skipped 行动没有目标字段，只更新行动者（如有AP信息）
	if not action.has("target_name"):
		if action.has("actor_ap"):
			_update_unit_bar(action.actor_name, action.actor_hp, action.actor_max_hp,
				true, action.actor_side, action.actor_ap, action.actor_max_ap)
		return

	# 多目标：逐个更新（新技能系统的 targets 数组）
	if action.has("targets"):
		for t in action.targets:
			_update_unit_bar(t.name, t.hp, t.max_hp, t.alive, t.side)
	else:
		_update_unit_bar(action.target_name, action.target_hp, action.target_max_hp,
			action.target_alive if action.has("target_alive") else true, action.target_side)

	# 更新行动者单位（AP 消耗等）
	if action.has("actor_ap"):
		_update_unit_bar(action.actor_name, action.actor_hp, action.actor_max_hp,
			true, action.actor_side, action.actor_ap, action.actor_max_ap)


## ---------------------------------------------------------------------------
## _update_unit_bar() — 更新单个单位卡片的 UI 显示
## ---------------------------------------------------------------------------
## 这是UI更新的核心方法。根据 side 参数在 player_bars 或 enemy_bars
## 中查找对应单位，更新其 UI 元素。
##
## 更新的 UI 元素（通过 unit Dictionary 上的临时字段引用）：
##   unit._hp_bar   -> ProgressBar（血条）的颜色和值
##   unit._hp_text  -> Label（HP 文字）
##   unit._status_lbl -> Label（存活/阵亡状态）
##   unit._ap_pp    -> Label（AP/PP 显示）
##
## 血条颜色规则：
##   HP >= 60% -> 绿色
##   HP >= 30% -> 金色（警告）
##   HP <  30% -> 红色（危险）
##
## 这些 _hp_bar 等字段是在 _create_unit_card() 中挂到 unit Dictionary 上的。
## 因为 GDScript 的 Dictionary 可以动态添加任意字段（类似 Python dict），
## 所以可以用这种方式把 UI 引用和数据绑定在一起。
## ---------------------------------------------------------------------------
func _update_unit_bar(unit_name: String, hp: int, max_hp: int, alive: bool, side: String,
		ap_val: int = -1, max_ap: int = -1) -> void:
	# 根据阵营选择对应的卡片列表
	var bars = player_bars if side == "player" else enemy_bars

	for entry in bars:
		if entry.unit.name_zh == unit_name:
			var unit = entry.unit
			# 更新 unit Dictionary 中的值（直接影响 BattleManager 的数据！）
			unit.hp = hp
			unit.max_hp = max_hp
			unit.is_alive = alive
			if ap_val >= 0:
				unit.ap = ap_val
				unit.max_ap = max_ap

			# --- 更新血条 ProgressBar ---
			# .has() 检查字典中是否有该键（UI 引用可能在 _create_unit_card 时设置）
			if unit.has("_hp_bar"):
				var bar: ProgressBar = unit._hp_bar
				bar.max_value = max_hp
				bar.value = hp
				# 根据血量百分比改变血条颜色
				if hp < max_hp * 0.3:
					bar.add_theme_stylebox_override("fill", _hp_fill_style(UITheme.RED))
				elif hp < max_hp * 0.6:
					bar.add_theme_stylebox_override("fill", _hp_fill_style(UITheme.GOLD))
				else:
					bar.add_theme_stylebox_override("fill", _hp_fill_style(UITheme.GREEN))

			# --- 更新 HP 文字 ---
			if unit.has("_hp_text"):
				unit._hp_text.text = "HP: %d/%d" % [hp, max_hp]

			# --- 更新存活状态标签 ---
			if unit.has("_status_lbl"):
				unit._status_lbl.text = "存活" if alive else "阵亡"
				unit._status_lbl.add_theme_color_override("font_color",
					UITheme.GREEN if alive else UITheme.RED)

			# --- 更新 AP/PP 显示 ---
			# ap_val >= 0 表示行动中包含 AP 信息（attack 行动有，death 没有）
			if unit.has("_ap_pp") and ap_val >= 0:
				unit._ap_pp.text = "🔴AP:%d/%d  🔵PP:%d/%d" % [ap_val, max_ap, unit.pp, unit.max_pp]

			break  # 找到就退出


# ==================================================================
#  BattleManager 信号处理
# ==================================================================

## ---------------------------------------------------------------------------
## _on_battle_started() — 战斗开始
## ---------------------------------------------------------------------------
## 在收到 battle_started 信号后：
##   1. 根据 BattleManager 中的单位数据创建 UI 卡片
##   2. 写入第一条战斗日志
##   3. 启动 action_timer（开始逐行动播放）
##
## 注意：这里才启动 timer，而不是在 _ready() 中。
##       因为 begin_combat() 内部先 emit battle_started，再 _start_next_round，
##       所以 timer 启动时，第一个回合的行动已经预计算好了。
## ---------------------------------------------------------------------------
func _on_battle_started() -> void:
	# 创建所有单位的 UI 卡片显示
	_build_unit_displays()

	# 战斗开始日志
	_add_log("⚔️ 战斗开始！双方共 %d vs %d 人参战" % [
		BattleManager.player_units.size(), BattleManager.enemy_units.size()
	])

	# 启动行动计时器 — 战斗播放开始！
	action_timer.start()


## ---------------------------------------------------------------------------
## _on_round_started() — 新回合开始
## ---------------------------------------------------------------------------
## 更新回合标签文字，写入回合分隔日志。
## ---------------------------------------------------------------------------
func _on_round_started(round_num: int) -> void:
	round_label.text = "第 %d 回合" % round_num
	# 使用 ━━━ 作为回合分隔线，让日志更易读
	_add_log("━━━ 第 %d 回合 ━━━" % round_num)


## ---------------------------------------------------------------------------
## _on_battle_ended() — 战斗结束
## ---------------------------------------------------------------------------
## 无论胜负，都会：
##   1. 设置 battle_done 标记（停止处理 timer tick）
##   2. 停止 action_timer
##   3. 显示"返回编成"按钮
##   4. 获取统计数据
##   5. 显示结果覆盖层（含统计面板）
##   6. 写入最终结果日志
## ---------------------------------------------------------------------------
func _on_battle_ended(result: String) -> void:
	battle_done = true
	action_timer.stop()

	# 保存统计数据（延迟到用户点击"查看统计"时使用）
	_battle_result = result
	_battle_stats = BattleManager.get_stats_summary()

	# 最终结果日志
	if result == "victory":
		_add_log("🏆 我方胜利！历经 %d 回合" % _battle_stats.rounds)
	else:
		_add_log("💀 我方败北...历经 %d 回合" % _battle_stats.rounds)

	# 在右下角显示"返回编成"和"查看统计"按钮（不弹覆盖层）
	_add_log("━━━ 战斗结束，可滚动查看日志 ━━━")
	return_btn.visible = true
	view_stats_btn.visible = true
	copy_log_btn.visible = true


# ==================================================================
#  结果统计面板 (Result Summary)
# ==================================================================

## ---------------------------------------------------------------------------
## _show_summary() — 显示战斗结果统计面板
## ---------------------------------------------------------------------------
## 构建一个覆盖层，显示：
##   · 结果标题（"🎉 胜利！" / "💔 败北..."）
##   · 我方统计：每个角色的输出、承伤、HP
##   · 敌方统计：同上
##   · 总计：双方总输出和总承伤
## ---------------------------------------------------------------------------
func _show_summary(result: String, stats: Dictionary) -> void:
	result_overlay.visible = true

	# --- 结果标题 ---
	var result_text = "🎉 胜利！" if result == "victory" else ("⚖️ 平局" if result == "draw" else "💔 败北...")
	var result_color = UITheme.GOLD_BRIGHT if result == "victory" else (UITheme.INK_DIM if result == "draw" else UITheme.RED)
	summary_header.text = result_text
	summary_header.add_theme_color_override("font_color", result_color)
	summary_header.add_theme_font_size_override("font_size", 24)
	summary_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# --- 我方统计 ---
	# 先清空旧的子节点
	for child in summary_player.get_children():
		child.queue_free()
	_build_side_summary(summary_player, stats.player, "我方", UITheme.GOLD_BRIGHT)

	# --- 敌方统计 ---
	for child in summary_enemy.get_children():
		child.queue_free()
	_build_side_summary(summary_enemy, stats.enemy, "敌方", UITheme.RED)

	# --- 总计 ---
	summary_total.text = "我方输出: %d  我方承伤: %d\n敌方输出: %d  敌方承伤: %d" % [
		stats.player.total_damage_dealt, stats.player.total_damage_taken,
		stats.enemy.total_damage_dealt, stats.enemy.total_damage_taken,
	]
	summary_total.add_theme_color_override("font_color", UITheme.INK)
	summary_total.add_theme_font_size_override("font_size", 12)
	summary_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## ---------------------------------------------------------------------------
## _build_side_summary() — 构建单方统计子面板
## ---------------------------------------------------------------------------
## 参数：
##   container  — 放置统计 UI 的容器
##   side_stats — 阵营统计数据 Dictionary
##   label      — 标签文字（"我方"/"敌方"）
##   color      — 标签颜色
##
## 每行显示一个角色：[状态图标] 角色名 [职业]  输出:XXX  承伤:XXX  HP:XX/XX
## ---------------------------------------------------------------------------
func _build_side_summary(container: VBoxContainer, side_stats: Dictionary,
		label: String, color: Color) -> void:
	# 阵营标题行：显示标签、总输出、总承伤
	var header := Label.new()
	header.text = "—— %s ——  输出: %d  承伤: %d" % [
		label, side_stats.total_damage_dealt, side_stats.total_damage_taken
	]
	header.add_theme_color_override("font_color", color)
	header.add_theme_font_size_override("font_size", 12)
	container.add_child(header)

	# 每个角色的统计行
	for u in side_stats.units:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		# 存活状态图标
		var status_icon := "✅" if u.alive else "💀"

		# 角色名 + 职业
		var name_lbl := Label.new()
		name_lbl.text = "%s %s [%s]" % [status_icon, u.name, u["class"]]
		name_lbl.add_theme_color_override("font_color",
			UITheme.INK if u.alive else UITheme.INK_DIM)
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # 占满水平空间
		row.add_child(name_lbl)

		# 战斗数据
		var dmg_lbl := Label.new()
		dmg_lbl.text = "输出:%d  承伤:%d  HP:%d/%d" % [
			u.damage_dealt, u.damage_taken, u.hp, u.max_hp
		]
		dmg_lbl.add_theme_color_override("font_color", UITheme.INK2)
		dmg_lbl.add_theme_font_size_override("font_size", 10)
		row.add_child(dmg_lbl)

		container.add_child(row)


# ==================================================================
#  单位卡片创建 (Unit Card Building)
# ==================================================================

## ---------------------------------------------------------------------------
## _build_unit_displays() — 创建所有单位的 UI 卡片
## ---------------------------------------------------------------------------
## 在战斗开始时调用。遍历 BattleManager 的 player_units 和 enemy_units，
## 为每个单位创建一个 VBox 卡片，包含：
##   · 角色名 + 职业（Label）
##   · HP 血条（ProgressBar）
##   · HP 文字（Label）
##   · AP/PP 文字（Label）
##   · 存活状态标签（Label）
##
## 卡片引用和 unit Dictionary 一起存入 player_bars/enemy_bars 数组，
## 方便后续通过角色名查找卡片。
## ---------------------------------------------------------------------------
func _build_unit_displays() -> void:
	# 清空旧的（理论上 _ready 时没有旧内容，但防御性编程）
	for child in player_grid.get_children():
		child.queue_free()
	for child in enemy_grid.get_children():
		child.queue_free()
	player_bars.clear()
	enemy_bars.clear()

	# 创建玩家单位卡片
	for unit in BattleManager.player_units:
		var card = _create_unit_card(unit, false)  # false = 不是敌方
		player_grid.add_child(card)
		player_bars.append({"unit": unit, "card": card})

	# 创建敌方单位卡片
	for unit in BattleManager.enemy_units:
		var card = _create_unit_card(unit, true)  # true = 是敌方
		enemy_grid.add_child(card)
		enemy_bars.append({"unit": unit, "card": card})


## ---------------------------------------------------------------------------
## _create_unit_card() — 创建单个单位卡片
## ---------------------------------------------------------------------------
## 返回一个 VBoxContainer，内部包含名称、血条、HP文字、AP文字、状态标签。
##
## 关键设计：把 UI 控件的引用直接挂在 unit Dictionary 上
##   unit["_hp_bar"] = hp_bar
##   unit["_hp_text"] = hp_text
##   unit["_status_lbl"] = status_lbl
##   unit["_ap_pp"] = ap_pp
##
## 这样做的好处是 _update_unit_bar() 可以通过 unit 直接访问对应的 UI 控件，
## 不需要额外的映射表。代价是数据和 UI 耦合在一起。
## 这是一种"脏快"的做法，适合原型阶段。
##
## ProgressBar 说明：
##   ProgressBar 是 Godot 的进度条控件。
##   min_value / max_value = 值范围
##   value = 当前值
##   add_theme_stylebox_override("fill", style) — 设置填充部分的样式
## ---------------------------------------------------------------------------
func _create_unit_card(unit: Dictionary, is_enemy: bool) -> Control:
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 4)  # 子控件间距
	card.custom_minimum_size = Vector2(160, 90)

	# --- 名称行 ---
	var name_lbl := Label.new()
	name_lbl.text = "%s [%s]" % [unit.name_zh, unit.class_zh]
	# 敌方用红色，友方用金色
	name_lbl.add_theme_color_override("font_color",
		UITheme.RED if is_enemy else UITheme.GOLD_BRIGHT)
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(name_lbl)

	# --- HP 血条 ---
	var hp_bar := ProgressBar.new()
	hp_bar.min_value = 0
	hp_bar.max_value = unit.max_hp
	hp_bar.value = unit.hp
	hp_bar.custom_minimum_size = Vector2(150, 14)
	hp_bar.add_theme_stylebox_override("fill", _hp_fill_style(UITheme.GREEN))
	card.add_child(hp_bar)
	unit["_hp_bar"] = hp_bar  # 挂载到 unit 上方便后续更新

	# --- HP 文字 ---
	var hp_text := Label.new()
	hp_text.text = "HP: %d/%d" % [unit.hp, unit.max_hp]
	hp_text.add_theme_color_override("font_color", UITheme.INK)
	hp_text.add_theme_font_size_override("font_size", 10)
	hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(hp_text)
	unit["_hp_text"] = hp_text

	# --- AP/PP 资源显示 ---
	# 🔴 = AP（行动点，用于主动技能）
	# 🔵 = PP（被动点，用于被动技能）
	var ap_pp := Label.new()
	ap_pp.text = "🔴AP:%d/%d  🔵PP:%d/%d" % [unit.ap, unit.max_ap, unit.pp, unit.max_pp]
	ap_pp.add_theme_color_override("font_color", UITheme.INK_DIM)
	ap_pp.add_theme_font_size_override("font_size", 9)
	ap_pp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(ap_pp)
	unit["_ap_pp"] = ap_pp

	# --- 存活状态标签 ---
	var status_lbl := Label.new()
	status_lbl.text = "存活" if unit.is_alive else "阵亡"
	status_lbl.add_theme_color_override("font_color",
		UITheme.GREEN if unit.is_alive else UITheme.RED)
	status_lbl.add_theme_font_size_override("font_size", 9)
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(status_lbl)
	unit["_status_lbl"] = status_lbl

	return card


## 创建血条填充颜色样式（小圆角的纯色块）
func _hp_fill_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = 3; sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3; sb.corner_radius_bottom_right = 3
	return sb


# ==================================================================
#  战斗日志 (Battle Log)
# ==================================================================

## ---------------------------------------------------------------------------
## _add_log() — 向战斗日志添加一条消息
## ---------------------------------------------------------------------------
## 创建新的 Label 追加到日志列表底部，然后自动滚动到底部。
##
## await get_tree().process_frame：
##   await 是 GDScript 的异步等待关键字（类似 Python 的 await）。
##   get_tree().process_frame 是一个信号，表示"下一帧处理前"。
##   await 这个信号意味着"等到下一帧再继续执行后续代码"。
##
##   为什么需要等一帧？
##   因为新添加的 Label 需要经过一帧的布局计算后，
##   ScrollContainer 才知道新的最大滚动位置。
##   如果在同一帧内直接设置 scroll_vertical，可能获取到的
##   max_value 还是旧的（没有包含新 Label 的高度）。
##
## 类比 Python asyncio：
##   await get_tree().process_frame
##   相当于
##   await asyncio.sleep(0)  # 让出控制权，等事件循环下一轮
## ---------------------------------------------------------------------------
func _add_log(msg: String) -> void:
	var lbl := Label.new()
	lbl.text = msg
	lbl.add_theme_color_override("font_color", UITheme.INK2)
	lbl.add_theme_font_size_override("font_size", 11)
	battle_log.add_child(lbl)

	# 自动滚动到底部
	var scroll = battle_log.get_parent()
	if scroll and scroll is ScrollContainer:
		# 等待一帧让布局更新，然后滚动到底部
		await get_tree().process_frame
		scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value


# ==================================================================
#  返回编成界面
# ==================================================================

## ---------------------------------------------------------------------------
## _on_return_to_formation() — "返回编成"按钮回调
## ---------------------------------------------------------------------------
## 重置 BattleManager（清空战斗数据），切换回编成场景。
##
## change_scene_to_file() 说明：
##   切换到指定场景文件。当前场景的所有节点会被销毁，
##   Autoload 节点（BattleManager、DataManager、UITheme）保留。
##   新场景的 _ready() 会被重新调用。
## ---------------------------------------------------------------------------
func _on_return_to_formation() -> void:
	BattleManager.reset()
	get_tree().change_scene_to_file("res://scenes/main.tscn")
