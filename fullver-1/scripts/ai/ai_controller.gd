class_name AIController
extends RefCounted
## =============================================================================
## AIController — AI 策略加载与调度（纯逻辑）
## =============================================================================
## 职责（docs/00-design.md §10.3）：
##   1. 按势力数据里的 ai_strategy 路径加载策略脚本（空串 = 内置 BasicAI）
##   2. 每个 AI 回合创建 AIContext（注入状态/势力/指令处理器）
##   3. 按约定顺序调用策略回调，每阶段检查战斗请求并中断
##
## 返回约定（对接 TurnManager 的 ai_turn 回调）：
##   {}                   — 回合正常结束
##   {"battle": {...}}    — 策略行动引发战斗，请求中断流程
##
## 类比 Python：
##   相当于一个插件加载器 + 执行器：读配置 → import 模块 → 按协议调用。
## =============================================================================

## 游戏状态（只读使用）
var state: GameState

## 指令处理器注册表（命令名 → Callable），透传给每个 AIContext
## 由 GameManager 在系统就绪后注入（P4 移动、P5 外交）
var command_handlers: Dictionary = {}

## 策略实例缓存：势力ID → BaseAIStrategy（避免每回合重复加载脚本）
var _strategy_cache: Dictionary = {}


func _init(gs: GameState) -> void:
	state = gs


## ---------------------------------------------------------------------------
## run_faction_turn() — 执行一个 AI 势力的完整回合
## ---------------------------------------------------------------------------
func run_faction_turn(faction: Faction) -> Dictionary:
	var strategy := _strategy_for(faction)
	var ctx := _make_context(faction)
	# 回调顺序：回合开始 → 军团行动 → 外交 → 回合结束
	# 任何阶段产生战斗请求都立即中断返回（战斗是回合流程的打断点）
	strategy.on_turn_start(ctx)
	if not ctx.pending_battle.is_empty():
		return {"battle": ctx.pending_battle}
	strategy.on_army_phase(ctx)
	if not ctx.pending_battle.is_empty():
		return {"battle": ctx.pending_battle}
	strategy.on_diplomacy_phase(ctx)
	if not ctx.pending_battle.is_empty():
		return {"battle": ctx.pending_battle}
	strategy.on_turn_end(ctx)
	if not ctx.pending_battle.is_empty():
		return {"battle": ctx.pending_battle}
	return {}


## ---------------------------------------------------------------------------
## _strategy_for() — 加载势力的 AI 策略（带缓存）
## ---------------------------------------------------------------------------
## 流程：
##   1. 读 faction.ai_strategy：空串 → 内置 BasicAI
##   2. 缓存命中直接返回
##   3. load(路径) 加载脚本并实例化；类型校验必须继承 BaseAIStrategy
##      （防配置错误挂上无关脚本）；校验失败回退 BasicAI 并报错
## ---------------------------------------------------------------------------
func _strategy_for(faction: Faction) -> BaseAIStrategy:
	if _strategy_cache.has(faction.id):
		return _strategy_cache[faction.id]

	var strategy: BaseAIStrategy = null
	var path: String = faction.ai_strategy
	if path == "":
		strategy = BasicAI.new()
	else:
		if not ResourceLoader.exists(path):
			Log.error("[AIController] 势力 {} 的 AI 策略脚本不存在: {}，回退 BasicAI", faction.id, path)
			strategy = BasicAI.new()
		else:
			var script: Script = load(path)
			var obj: Variant = script.new()
			if obj is BaseAIStrategy:
				strategy = obj
			else:
				# 类型不符：配置错误，必须显式报错并回退
				Log.error("[AIController] 势力 {} 的 AI 策略 {} 未继承 BaseAIStrategy，回退 BasicAI", faction.id, path)
				strategy = BasicAI.new()
	strategy.setup(faction)
	_strategy_cache[faction.id] = strategy
	return strategy


## 构建 AIContext 并注入指令处理器
func _make_context(faction: Faction) -> AIContext:
	var ctx := AIContext.new()
	ctx.state = state
	ctx.faction = faction
	for cmd in command_handlers:
		ctx.register_command(cmd, command_handlers[cmd])
	return ctx
