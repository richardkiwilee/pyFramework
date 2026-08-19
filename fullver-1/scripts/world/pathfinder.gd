class_name Pathfinder
extends RefCounted
## =============================================================================
## Pathfinder — 据点图寻路（Dijkstra）
## =============================================================================
## 职责：在无向据点图上找两城之间的最短路径（docs/00-design.md §8，ADR-0002）。
##
## 为什么 Dijkstra 而不是 A*：
##   图上只有 12 个节点，Dijkstra 复杂度完全够；A* 需要启发函数
##   （欧氏距离），对"城市间路线可能绕弯"的据点图并不更优。
##
## 类比 Python：
##   相当于 networkx.shortest_path 的一个手写最小实现。
## =============================================================================

## 邻接表：城市ID → 相邻城市ID数组（由 WorldMapModel 从地图数据构建）
var adjacency: Dictionary = {}


func _init(adj: Dictionary) -> void:
	adjacency = adj


## ---------------------------------------------------------------------------
## find_path() — 求 from_id → to_id 的最短路径
## ---------------------------------------------------------------------------
## 返回路径上的城市 ID 数组（含起点与终点）；无路返回 []。
## 统一边权 1（路线表无距离字段；未来加地形权重只需改这里的边权计算）。
## ⚠️ GDScript 4 的字面量 [] 是无类型 Array，直接 return 会触发
## "expected Array[String]" 运行时错误（本环境实测）——必须返回类型化数组。
## ---------------------------------------------------------------------------
func find_path(from_id: String, to_id: String) -> Array[String]:
	if from_id == to_id:
		var same: Array[String] = [from_id]
		return same
	if not adjacency.has(from_id) or not adjacency.has(to_id):
		var empty: Array[String] = []
		return empty

	# dist：起点到各节点的最短距离；prev：前驱节点（还原路径用）
	# 类比 Python 的 dict[str, int] / dict[str, str]
	var dist: Dictionary = {}
	var prev: Dictionary = {}
	var visited: Dictionary = {}
	for city_id in adjacency:
		dist[city_id] = 1 << 30  # 大数当作无穷（Python 里用 float('inf')）
	dist[from_id] = 0

	# 简单实现：每次从未访问节点中取 dist 最小的（12 节点 O(n²) 足够快）
	var current: String = from_id
	while current != "":
		visited[current] = true
		if current == to_id:
			break
		for neighbor in adjacency.get(current, []):
			if visited.has(neighbor):
				continue
			var nd: int = int(dist[current]) + 1
			if nd < int(dist.get(neighbor, 1 << 30)):
				dist[neighbor] = nd
				prev[neighbor] = current
		# 找下一个最近的未访问节点
		current = _next_closest(dist, visited)

	# 终点不可达（dist 仍是无穷大）
	if int(dist.get(to_id, 1 << 30)) >= (1 << 30):
		var empty: Array[String] = []
		return empty

	# 从终点回溯前驱链，反转得到 起点→终点
	var path: Array[String] = [to_id]
	var cur: String = to_id
	while cur != from_id:
		if not prev.has(cur):
			var broken: Array[String] = []
			return broken  # 防御：前驱链断裂（数据异常）
		cur = prev[cur]
		path.append(cur)
	path.reverse()
	return path


## 从未访问节点中取 dist 最小者；全部访问完返回空串
func _next_closest(dist: Dictionary, visited: Dictionary) -> String:
	var best: String = ""
	var best_dist := 1 << 30
	for city_id in dist:
		if visited.has(city_id):
			continue
		var d: int = int(dist[city_id])
		if d < best_dist:
			best_dist = d
			best = city_id
	return best
