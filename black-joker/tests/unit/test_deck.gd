extends TestBase
## Deck 单元测试：52 张唯一、种子洗牌可复现、抽空自动洗回弃牌堆


func _rng(seed: int = 12345) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r


func test_deck_has_52_unique() -> void:
	var deck := Deck.new()
	assert_eq(deck.remaining(), 52, "初始 52 张")
	var seen := {}
	while deck.remaining() > 0:
		var c := deck.draw(_rng())
		seen[c.id()] = true
	assert_eq(seen.size(), 52, "抽出的 52 张全部唯一")


func test_shuffle_reproducible_with_seed() -> void:
	var d1 := Deck.new()
	var d2 := Deck.new()
	d1.shuffle(_rng(42))
	d2.shuffle(_rng(42))
	assert_eq(_all_ids(d1), _all_ids(d2), "同种子洗牌顺序一致")


func test_shuffle_differs_across_seeds() -> void:
	var d1 := Deck.new()
	var d2 := Deck.new()
	d1.shuffle(_rng(111))
	d2.shuffle(_rng(222))
	assert_true(_all_ids(d1) != _all_ids(d2), "不同种子洗牌顺序不同")


func test_recycle_discard() -> void:
	var deck := Deck.new()
	var rng := _rng()
	for i in 30:
		deck.discard(deck.draw(rng))
	assert_eq(deck.remaining(), 22, "抽 30 张后剩 22")
	var ids: Array[String] = []
	for i in 22:
		ids.append(deck.draw(rng).id())
	var first_recycled := deck.draw(rng)
	assert_true(first_recycled != null, "牌堆空后洗回弃牌堆仍能抽牌")
	ids.append(first_recycled.id())
	for i in 29:
		ids.append(deck.draw(rng).id())
	assert_eq(ids.size(), 52, "洗回后共抽 52 张")
	var uniq := {}
	for s in ids:
		uniq[s] = true
	assert_eq(uniq.size(), 52, "洗回后仍全部唯一")


func _all_ids(d: Deck) -> Array[String]:
	var out: Array[String] = []
	var rng := _rng()
	for i in d.remaining():
		out.append(d.draw(rng).id())
	return out
