"""
控制台渲染:把游戏状态渲染成文本供 FSM 显示。

界面只管图形(文本)资源的组合,不承担逻辑。
"""
from __future__ import annotations
from ..game.game import Game
from ..game.economy import RESOURCE_CN, BELIEF_CN
from ..game.unit import TAG_CN


def render_header(game: Game) -> str:
    p = game.factions[game.player_id]
    return (f"=== {game.calendar.describe()} ===\n"
            f"玩家: {p.name}  资源:{p.resources.describe()}\n"
            f"信念:{p.belief.describe()}")


def render_map(game: Game) -> str:
    return game.map.describe()


def render_armies(game: Game, faction_id: str) -> str:
    f = game.factions[faction_id]
    lines = [f"--- {f.name} 的部队 ---"]
    for aid in f.army_ids:
        a = game.armies.get(aid)
        if a:
            lines.append(a.describe(game.unit_index))
            lines.append(f"  位置:{game.map.node_name(a.node_id)}  本回合已动:{'是' if a.has_acted_this_turn else '否'}")
    return "\n".join(lines) if len(lines) > 1 else f"{f.name} 无部队"


def render_strongholds(game: Game, faction_id: str) -> str:
    f = game.factions[faction_id]
    lines = [f"--- {f.name} 的据点 ---"]
    for sid in f.stronghold_ids:
        sh = game.map.strongholds.get(sid)
        if sh:
            lines.append("  " + sh.describe())
            # 招募池
            pool = f.recruitment_pools.get(sid)
            if pool and pool.offerings:
                offs = []
                for hid in pool.offerings:
                    if hid is None:
                        continue
                    hdef = game.hero_defs.get(hid)
                    if hdef:
                        from ..game.hero import describe_req
                        offs.append(f"{hdef.name}(需{hdef.recruit_cost} 信念:{describe_req(hdef.belief_req)})")
                if offs:
                    lines.append("    可招募:" + " | ".join(offs))
            # 驻军信息
            g = game._find_garrison(sid)
            if g:
                lines.append(f"    驻军:存活{len(g.alive_units(game.unit_index))}人")
            # 领主
            lord = f.lords.get(sid)
            if lord and lord in game.unit_index:
                lines.append(f"    领主:{game.unit_index[lord].name}")
    return "\n".join(lines) if len(lines) > 1 else f"{f.name} 无据点"


def render_buildable(game: Game, stronghold_id: str) -> str:
    sh = game.map.strongholds.get(stronghold_id)
    if not sh:
        return "无此据点"
    lines = [f"{sh.name} 可建造(空槽 {sh.free_slots()}):"]
    idx = 0
    for bid, bdef in game.building_defs.items():
        cost = bdef.get("cost", {})
        coststr = "、".join(f"{RESOURCE_CN.get(k,k)}{v}" for k, v in cost.items())
        lines.append(f"  [{idx}] {bdef['name']} 费:{coststr} 回合:{bdef.get('build_turns',1)} -> {bid}")
        idx += 1
    return "\n".join(lines)


def render_recruits(game: Game, stronghold_id: str) -> str:
    f = game.factions[game.player_id]
    pool = f.recruitment_pools.get(stronghold_id)
    if not pool or not pool.offerings or not any(h is not None for h in pool.offerings):
        return "无可招募英雄"
    from ..game.hero import describe_req
    lines = [f"{game.map.strongholds[stronghold_id].name} 可招募英雄:"]
    for i, hid in enumerate(pool.offerings):
        if hid is None:
            lines.append(f"  [{i}] （空位）")
            continue
        hdef = game.hero_defs.get(hid)
        if hdef:
            coststr = "、".join(f"{RESOURCE_CN.get(k,k)}{v}" for k, v in hdef.recruit_cost.items())
            lines.append(f"  [{i}] {hdef.name}({'/'.join(TAG_CN.get(t,t) for t in sorted(hdef.tags))}) "
                          f"费:{coststr} 信念:{describe_req(hdef.belief_req)}")
    return "\n".join(lines)


def render_event(game: Game) -> str | None:
    if not game.pending_event:
        return None
    ev = game.pending_event
    lines = [f"【事件】{ev.title}", ev.text]
    for i, opt in enumerate(ev.options):
        lines.append(f"  [{i}] {opt.label}")
    return "\n".join(lines)
