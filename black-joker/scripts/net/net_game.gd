class_name NetGame
extends Node
## =============================================================================
## NetGame — 可选联机对战（ENet 直连，主机权威）
## =============================================================================
## 对外接口与 LocalGame 对齐：state_changed(snapshot) 信号 + submit_action。
## - 主机：持有 MatchState（权威），校验动作后广播全量快照；
## - 客户端：只发意图（{"seat","action"}），从快照渲染。
## 传输层为手动 PacketPeer 协议（JSON 文本包）：
##   - 不依赖 Node.rpc / set_multiplayer（本环境实测 set_multiplayer 不存在、
##     multiplayer 属性不可写，协程 Callable.call() 也是硬错误）；
##   - 直接在 ENetMultiplayerPeer 上收发包，_process 里 poll + 处理。
## 同进程回环可测（test_net.gd 双实例真 UDP 通信）。
## =============================================================================

signal state_changed(snap: Dictionary)
signal connected()      # 对局建立（主机：客户端加入；客户端：连上服务器）
signal opponent_left()

var ms: MatchState      # 仅主机有效
var is_host: bool = false
var my_seat: int = 1    # 主机 0 / 客户端 1
var last_snap: Dictionary = {}
var settle_delay: float = 2.0

var _peer: ENetMultiplayerPeer
var _started := false
var _pending_settle := false


static func make_host(port: int) -> NetGame:
	var g := NetGame.new()
	g.is_host = true
	g.my_seat = 0
	g._peer = ENetMultiplayerPeer.new()
	g._peer.create_server(port, 1)
	g._peer.peer_connected.connect(g._on_peer_connected)
	g._peer.peer_disconnected.connect(g._on_peer_disconnected)
	return g


static func make_client(ip: String, port: int) -> NetGame:
	var g := NetGame.new()
	g.is_host = false
	g.my_seat = 1
	g._peer = ENetMultiplayerPeer.new()
	g._peer.create_client(ip, port)
	return g


func _process(_delta: float) -> void:
	if _peer == null:
		return
	_peer.poll()
	# 客户端侧连接/断开没有专用信号，轮询连接状态（ENetMultiplayerPeer
	# 只有 peer_connected/peer_disconnected 两个 peer 级信号）
	if not is_host:
		var status := _peer.get_connection_status()
		if not _started and status == MultiplayerPeer.CONNECTION_CONNECTED:
			_started = true
			connected.emit()
		elif _started and status == MultiplayerPeer.CONNECTION_DISCONNECTED:
			_started = false
			opponent_left.emit()
	while _peer.get_available_packet_count() > 0:
		var bytes := _peer.get_packet()
		_handle_packet(bytes)


func submit_action(p: int, action: String) -> void:
	if is_host:
		_apply_action(p, action)
	else:
		_send({"seat": p, "action": action})


func snapshot() -> Dictionary:
	if is_host and ms != null:
		return ms.snapshot()
	return last_snap


func shutdown() -> void:
	if _peer != null:
		_peer.close()


# ==================================================================
#  传输层
# ==================================================================

func _send(data: Dictionary) -> void:
	var bytes := JSON.stringify(data).to_utf8_buffer()
	# set_target_peer(0)=广播；主机快照广播，客户端动作只发给服务器(1)
	_peer.set_target_peer(0 if is_host else 1)
	_peer.put_packet(bytes)


func _handle_packet(bytes: PackedByteArray) -> void:
	var text := bytes.get_string_from_utf8()
	var data = JSON.parse_string(text)
	if data is not Dictionary:
		return
	if is_host:
		var p: int = int(data.get("seat", -1))
		var action: String = str(data.get("action", ""))
		_apply_action(p, action)
	else:
		last_snap = data
		state_changed.emit(data)


# ==================================================================
#  主机侧
# ==================================================================

func _on_peer_connected(_id: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	ms = MatchState.new(rng)
	ms.start_round()
	_started = true
	connected.emit()
	_broadcast()


func _on_peer_disconnected(_id: int) -> void:
	if ms != null and not ms.match_over:
		ms.match_over = true
		ms.match_winner = my_seat  # 对方掉线，己方胜
	_broadcast()
	opponent_left.emit()


func _apply_action(p: int, action: String) -> void:
	if ms == null or ms.match_over or not _started:
		return
	var round := ms.round
	if round == null or not round.can_act(p):
		return
	if action == "hit":
		round.hit()
	elif action == "stand":
		round.stand()
	else:
		return
	_broadcast()
	if round.is_over():
		_schedule_settle()


func _schedule_settle() -> void:
	if _pending_settle:
		return
	_pending_settle = true
	await get_tree().create_timer(settle_delay).timeout
	_pending_settle = false
	if ms == null or ms.match_over:
		return
	ms.settle_round()
	_broadcast()
	if ms.match_over:
		return
	ms.start_round()
	_broadcast()


## 广播快照：发给客户端 + 本地也触发渲染
func _broadcast() -> void:
	_send(ms.snapshot())
	state_changed.emit(ms.snapshot())


# ==================================================================
#  客户端侧（连接状态轮询见 _process）
# ==================================================================
