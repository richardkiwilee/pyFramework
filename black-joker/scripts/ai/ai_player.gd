class_name AIPlayer
extends RefCounted
## =============================================================================
## AIPlayer — AI 决策（纯函数，输入快照输出 "hit"/"stand"）
## =============================================================================
## - 简单（easy）：不读牌背，经典阈值策略（≤16 要牌）。
## - 困难（hard）：完美读牌背（知道下一张）、看对手明手与停牌状态：
##   领先且对方已停 → 停；落后 → 已知下一张不爆就追；对方未停 → 17 点以上停。
## =============================================================================


static func decide(snapshot: Dictionary, difficulty: String) -> String:
	var turn: int = snapshot["turn"]
	var totals: Array = snapshot["totals"]
	var stood: Array = snapshot["stood"]
	var my := int(totals[turn])
	var opp := int(totals[1 - turn])
	var opp_stood := bool(stood[1 - turn])
	if difficulty == "easy":
		return "stand" if my > 16 else "hit"
	return _hard_decide(snapshot, turn, my, opp, opp_stood)


## 下一张牌加入我手后的最佳点数贡献（A 按 11 计除非会爆）
static func _next_value(snapshot: Dictionary, my: int) -> int:
	var top: Dictionary = snapshot["top"]
	if top.is_empty():
		return -1
	var rank: int = top["rank"]
	if rank == CardData.Rank.ACE:
		return 11 if my + 11 <= 21 else 1
	return 10 if rank >= CardData.Rank.TEN else rank


static func _hard_decide(snapshot: Dictionary, turn: int, my: int, opp: int, opp_stood: bool) -> String:
	if my >= 21:
		return "stand"
	var next_val := _next_value(snapshot, my)
	if next_val < 0:
		# 牌堆顶不可见（理论不发生）：保守策略
		return "stand" if my >= 12 else "hit"
	if my + next_val > 21:
		# 已知下一张必爆：站着还有希望；仅当站着必输（对方已停且领先）才赌
		if opp_stood and opp > my:
			return "hit"
		return "stand"
	if opp_stood:
		# 对方停牌，明手对比
		if my > opp:
			return "stand"
		# 落后则追（已知下一张安全）
		return "hit"
	# 对方未停：17 点以上收手
	return "stand" if my >= 17 else "hit"
