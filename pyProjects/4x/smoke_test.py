"""自动对局冒烟测试:双方都用贪心 AI 逻辑行动,验证整局能跑完并产生胜者。

绕过控制台输入,直接驱动 Game + ai_take_turn,覆盖:
经济/移动/战斗/占领/首都陷落/胜负判定/mod 覆盖。
"""
from __future__ import annotations
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from pydemo.cli.scenario import build_scenario
from pydemo.game.ai import ai_take_turn


def run(max_turns: int = 200) -> int:
    game = build_scenario()
    turn = 0
    while not game.is_over() and turn < max_turns:
        turn += 1
        for fid, f in list(game.factions.items()):
            if not f.alive:
                continue
            game.start_turn(f)   # 规范入口:经济结算(含维护费/回血)+ 招募池刷新
            if not f.is_ai:
                game.maybe_trigger_event(f)
                if game.pending_event:
                    game.resolve_event(0)   # 玩家永远选 0
            actions = ai_take_turn(f, game)
            for kind, payload in actions:
                if kind == "build":
                    game.action_build(fid, payload["stronghold"], payload["building"])
                elif kind == "recruit_hero":
                    game.action_recruit_hero(fid, payload["stronghold"], payload["hero"])
                elif kind == "move_attack":
                    game.action_move_attack(fid, payload["army"], payload["to"])
                elif kind == "deploy":
                    game.action_deploy(fid, payload["army"], payload["unit"], payload.get("slot"))
                elif kind == "new_army":
                    node_id = payload["stronghold"]
                    name = payload.get("name", "AI 部队")
                    army = game.create_army(fid, node_id, name)
                    hero = game.unit_index.get(payload["hero"])
                    if not hero or not game.set_captain(army, hero):
                        game.disband_army(army)
                if game.is_over():
                    break
            if game.is_over():
                break
        if game.is_over():
            break
        game.end_turn_advance()
        for a in game.armies.values():
            a.has_acted_this_turn = False
        game.check_winner()

    print(f"跑了 {turn} 回合")
    print("胜者:", game.winner)
    for fid, f in game.factions.items():
        print(f"  {f.name}: alive={f.alive} 据点={len(f.stronghold_ids)} 部队={len(f.army_ids)}")
    print("--- 日志尾部 ---")
    for line in game.log[-12:]:
        print(" ", line)
    return 0 if game.winner else 1


if __name__ == "__main__":
    sys.exit(run())
