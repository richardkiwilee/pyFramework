extends TestBase
## NetGame 回环联机测试：同进程双 SceneMultiplayer 上下文跑完整一局
## 策略（受控牌堆全 10 点牌）：座位0 打两张停、座位1 一直要 → 座位1 必爆，
## 座位0 每回合必胜，10 回合后对局结束。


const PORT := 9201


func test_net_loopback_match() -> void:
	# 直接协程形态（runner 对协程方法 await 完成 Signal）
	var tree: SceneTree = ctx["tree"]
	var host := NetGame.make_host(PORT)
	var client := NetGame.make_client("127.0.0.1", PORT)
	host.settle_delay = 0.05
	tree.root.add_child(host)
	tree.root.add_child(client)

	var flags := {"got_state": false, "snaps": 0, "match_over": false}
	client.state_changed.connect(func(_s = null) -> void:
		flags["snaps"] = int(flags["snaps"]) + 1
		flags["got_state"] = true)

	assert_true(await _wait_signal(host.connected, 10.0), "主机收到客户端连接")
	assert_true(host.ms != null, "主机已建立对局")
	assert_true(await _wait_until(func() -> bool: return flags["got_state"], 10.0),
		"客户端收到首个快照")

	# 受控牌堆：全 10 点牌（足够 10 回合）
	var deck := host.ms.deck
	deck.draw_pile.clear()
	for i in 80:
		deck.draw_pile.append(CardData.new(0, 10))

	# 驱动整局：座位0 每回合打两张停，座位1 一直要
	# （帧数与墙钟双上限：headless 帧率不固定，只限帧数会因机器而异）
	var s0_hits := {"round": -1, "count": 0}
	var deadline: SceneTreeTimer = tree.create_timer(20.0)
	var guard := 0
	while guard < 3000 and not flags["match_over"] and deadline.time_left > 0.0:
		await tree.process_frame
		guard += 1
		var snap: Dictionary = client.last_snap
		if snap.is_empty() or not snap.has("round"):
			continue
		# match_over 检查必须在 round 空判定之前：对局结束的快照 round == {}
		if bool(snap["match_over"]):
			flags["match_over"] = true
			break
		var r: Dictionary = snap["round"]
		if r.is_empty():
			continue
		if int(r["phase"]) != RoundEngine.Phase.TURN:
			continue
		var rn: int = snap["round_number"]
		if s0_hits["round"] != rn:
			s0_hits["round"] = rn
			s0_hits["count"] = 0
		var turn: int = r["turn"]
		if turn == 0:
			if int(s0_hits["count"]) < 2:
				host.submit_action(0, "hit")
				s0_hits["count"] = int(s0_hits["count"]) + 1
			else:
				host.submit_action(0, "stand")
		else:
			client.submit_action(1, "hit")

	assert_true(flags["match_over"], "对局正常结束")
	var final_snap: Dictionary = client.last_snap
	assert_eq(int(final_snap["match_winner"]), 0, "座位0 每回合必胜")
	# JSON 往返后 int 变 float（200.0），断言前转回 int
	assert_eq([int(final_snap["chips"][0]), int(final_snap["chips"][1])], [200, 0], "筹码 200:0")
	assert_eq(int(final_snap["pot"]), 0, "底池清零")
	assert_true(int(flags["snaps"]) > 10, "客户端收到大量状态广播")
	# 主机快照过一遍 JSON 往返后应与客户端收到的一致（同型比较）
	var host_roundtripped = JSON.parse_string(JSON.stringify(host.snapshot()))
	assert_eq(host_roundtripped, final_snap, "主机与客户端最终快照一致")

	host.shutdown()
	client.shutdown()
	tree.root.remove_child(host)
	tree.root.remove_child(client)
	host.free()
	client.free()


## 等信号（带超时）
func _wait_signal(sig: Signal, secs: float) -> bool:
	var done := {"ok": false}
	sig.connect(func(_a = null) -> void: done["ok"] = true, CONNECT_ONE_SHOT)
	return await _wait_until(func() -> bool: return done["ok"], secs)


## 轮询条件直到为真（带超时）
func _wait_until(cond: Callable, secs: float) -> bool:
	var t: SceneTreeTimer = ctx["tree"].create_timer(secs)
	while not bool(cond.call()):
		if t.time_left <= 0.0:
			return false
		await ctx["tree"].process_frame
	return true
