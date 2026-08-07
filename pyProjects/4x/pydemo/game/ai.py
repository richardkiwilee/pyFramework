"""
AI:贪心启发式,5 条优先级规则。

1. 首都不受威胁时补经济、建产出建筑
2. 凑信念/资源招英雄扩军
3. 遇中立据点弱驻军则夺
4. 遇敌方主力弱势则攻
5. 有机会夺敌首都优先

重建兜底(ADR-0005 待命池落地后补):当阵营已无玩家编组部队,但有待命·可用英雄
驻于己方据点,则新建一支部队(任队长),使阵营失去初始部队后能重建、继续推进,
避免冒烟对局长期"双方 0 部队"死局。新建部队后,若还有待命·可用单位,尽量派进
停在己方据点的部队(上场须部队在己方据点)。

返回一个动作列表,由 Game 执行。每个动作是 (kind, payload) 元组。
"""
from __future__ import annotations
from typing import Any

from .faction import Faction
from .army import Army
from .unit import Unit


def ai_take_turn(faction: Faction, game) -> list[tuple[str, dict]]:
    """生成 AI 本回合的动作列表。"""
    actions: list[tuple[str, dict]] = []
    if not faction.alive:
        return actions

    capital = game.map.strongholds.get(faction.capital_id) if faction.capital_id else None

    # 1. 首都不受威胁时,在己方据点空槽建产出建筑
    for sid in list(faction.stronghold_ids):
        sh = game.map.strongholds.get(sid)
        if not sh or sh.free_slots() <= 0:
            continue
        # 选一个能造得起的产出建筑
        for bid, bdef in game.building_defs.items():
            if bdef.get("kind") != "produce":
                continue
            cost = bdef.get("cost", {})
            if faction.resources.can_afford(cost):
                actions.append(("build", {"stronghold": sid, "building": bid}))
                break

    # 2. 招英雄:若部队数 < 据点数 且 能招募
    for sid in list(faction.stronghold_ids):
        pool = faction.recruitment_pools.get(sid)
        if not pool or not pool.offerings or not any(h is not None for h in pool.offerings):
            continue
        # 找一个满足信念门槛且付得起的英雄（offerings 为固定 3 槽，含 None 空位）
        for hid in pool.offerings:
            if hid is None:
                continue
            hdef = game.hero_defs.get(hid)
            if not hdef:
                continue
            from .hero import meets_belief_req
            if not meets_belief_req(faction.belief, hdef.belief_req):
                continue
            if faction.resources.can_afford(hdef.recruit_cost):
                # 注意:不在此处改 pool.offerings;action_recruit_hero 会负责移除。
                actions.append(("recruit_hero", {"stronghold": sid, "hero": hid}))
                break

    # 2.5 重建兜底:无玩家编组部队但有待命·可用英雄 → 在己方据点新建部队
    player_armies = [game.armies.get(aid) for aid in faction.army_ids
                     if game.armies.get(aid) and not game.armies[aid].is_garrison]
    if not player_armies:
        # 找一个己方据点作为建队地点(优先首都)
        node_id = faction.capital_id
        if node_id and node_id in faction.stronghold_ids:
            # 待命·可用英雄
            hero = None
            for uid in faction.standby_available_ids():
                u = game.unit_index.get(uid)
                if u and u.is_hero and u.alive:
                    hero = u
                    break
            if hero is not None:
                actions.append(("new_army", {"stronghold": node_id,
                                             "hero": hero.id,
                                             "name": f"{hero.name}的部队"}))

    # 2.6 上场:把待命·可用单位派进停在己方据点的部队(ADR-0005:须在己方据点)
    avail_ids = faction.standby_available_ids()
    if avail_ids:
        for army in player_armies:
            if army.node_id not in faction.stronghold_ids:
                continue
            if None not in army.grid:
                continue  # 无空位
            # 按占用升序派低占用单位先上,便于塞更多
            cands = sorted(
                ((game.unit_index[uid], uid) for uid in avail_ids
                 if uid in game.unit_index and game.unit_index[uid].alive),
                key=lambda uu: uu[0].occupy())
            for u, uid in cands:
                if army.can_add(u, game.unit_index):
                    actions.append(("deploy", {"army": army.id, "unit": uid}))
                    break  # 一支部队本回合先派一个,避免超占

    # 3 & 5. 移动与进攻:遍历部队,向敌方首都推进。
    # 先算到敌方首都的距离图(BFS),让部队朝距离更小的邻接点走,避免来回反弹。
    enemy_capital = None
    for fid, f in game.factions.items():
        if fid == faction.id:
            continue
        if f.capital_id and f.alive:
            enemy_capital = f.capital_id
            break
    dist = _bfs_distances(game, enemy_capital) if enemy_capital else {}

    for aid in list(faction.army_ids):
        army = game.armies.get(aid)
        if not army or army.is_wiped(game.unit_index) or army.is_garrison:
            continue
        if army.has_acted_this_turn:
            continue
        node = army.node_id
        nbrs = game.map.neighbors(node)
        # 优先:邻接的敌方/中立据点直接进攻(首都最优先)
        target = None
        for n in nbrs:
            if n in game.map.strongholds:
                sh = game.map.strongholds[n]
                if sh.owner != faction.id:
                    target = n
                    if n == enemy_capital:
                        break
        if target:
            actions.append(("move_attack", {"army": aid, "to": target}))
            continue
        # 否则朝敌方首都方向移动:选距离最小的邻接点(不往回走)
        if not nbrs:
            continue
        cur_d = dist.get(node, 10 ** 9)
        best = None
        best_d = cur_d   # 只选比当前更近的
        for n in nbrs:
            nd = dist.get(n, 10 ** 9)
            if nd < best_d:
                best_d = nd
                best = n
        if best is None:
            # 没有更近的(可能已到敌首都邻接但被己方据点挡),随便选一个非己方据点
            for n in nbrs:
                sh = game.map.strongholds.get(n)
                if sh is None or sh.owner != faction.id:
                    best = n
                    break
            if best is None:
                best = nbrs[0]
        actions.append(("move_attack", {"army": aid, "to": best}))

    return actions


def _bfs_distances(game, target_node: str) -> dict[str, int]:
    """从 target_node 出发 BFS,返回各结点到它的最短跳数。"""
    from collections import deque
    dist: dict[str, int] = {target_node: 0}
    q = deque([target_node])
    while q:
        cur = q.popleft()
        for n in game.map.neighbors(cur):
            if n not in dist:
                dist[n] = dist[cur] + 1
                q.append(n)
    return dist
