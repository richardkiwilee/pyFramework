class_name BaseAIStrategy
extends RefCounted
## =============================================================================
## BaseAIStrategy — AI 策略基类（readme 硬性要求的扩展点）
## =============================================================================
## 作用：把"AI 回合的思考与行动"做成可替换的 GDScript 脚本。
## 用户（或 mod）编写一个继承本类的脚本，挂载到势力的 ai_strategy 字段，
## 即可替换该势力在战略层的全部决策——为难度分级/自定义启发式 AI 做准备。
##
## 使用步骤（docs/00-design.md §10.3）：
##   1. 写脚本 `extends BaseAIStrategy`（class_name 可选）
##   2. 覆写需要的回调（未覆写的保持 pass，不影响流程）
##   3. 在 data/factions.json 给该势力配 "ai_strategy": "res://你的脚本路径"
##      （留空 = 内置 BasicAI）
##
## 回调顺序（AIController 保证）：
##   on_turn_start → on_army_phase → on_diplomacy_phase → on_turn_end
##
## 回调参数 ctx 是 AIContext：
##   - 只读视图：局面信息（我方军团/城市/敌人/邻接关系……）
##   - 指令集：ctx.command("move", {...}) 等，全部经系统校验后执行
##   - AI 无法直接改数据——防越权（docs/00-design.md §10.2）
##
## 类比 Python：
##   相当于定义抽象基类（abc.ABC），用户继承后按需覆写方法。
##   GDScript 没有抽象方法语法，约定"空实现 = 该时点无决策"。
## =============================================================================


## 初始化：策略实例创建时调用一次，可在这里保存势力引用/做预计算
func setup(faction: Faction) -> void:
	pass


## 回合开始：内政/建设/征兵决策（在军团行动之前）
func on_turn_start(ctx: AIContext) -> void:
	pass


## 军团行动：移动/进攻决策
## 引发战斗的方式：ctx.command("move", {...}) 进入敌对城市时，
## 系统会把战斗请求写入 ctx.pending_battle，AIController 检测后中断流程。
func on_army_phase(ctx: AIContext) -> void:
	pass


## 外交阶段：宣战/求和/贸易/结盟决策
func on_diplomacy_phase(ctx: AIContext) -> void:
	pass


## 回合结束：收尾决策（当前无额外钩子，预留）
func on_turn_end(ctx: AIContext) -> void:
	pass
