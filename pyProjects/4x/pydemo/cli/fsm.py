"""
有限状态机(FSM)驱动的控制台交互。

状态:EVENT -> MAIN -> BUILD -> RECRUIT -> MOVE -> END
按键逻辑调用 game 类的函数,界面只管显示。
"""
from __future__ import annotations
from ..game.game import Game
from ..game.ai import ai_take_turn
from .scenario import build_scenario
from . import render as R


class ConsoleFSM:
    def __init__(self) -> None:
        self.game = build_scenario()
        self.state = "EVENT"   # 每回合开始先处理事件
        # 临时选择上下文
        self._build_sh: str | None = None
        self._recruit_sh: str | None = None
        self._move_army: str | None = None

    # ---------- 主循环 ----------
    def run(self) -> None:
        print("TheGreatConquest - Python 原型")
        print("目标:攻破 AI 首都。输入 ? 查看命令,h 查看状态。")
        # 第一回合先触发事件
        self._begin_player_turn()
        while not self.game.is_over():
            self._step()
        self._print_winner()

    def _step(self) -> None:
        if self.state == "EVENT":
            self._handle_event()
        elif self.state == "MAIN":
            self._handle_main()
        elif self.state == "BUILD":
            self._handle_build()
        elif self.state == "RECRUIT":
            self._handle_recruit()
        elif self.state == "MOVE":
            self._handle_move()
        elif self.state == "END":
            self._end_turn()

    # ---------- 回合开始 ----------
    def _begin_player_turn(self) -> None:
        game = self.game
        p = game.factions[game.player_id]
        # 经济结算(产出+建造推进+补给)
        game.tick_economy(p)
        # 事件触发
        game.maybe_trigger_event(p)
        self.state = "EVENT"

    # ---------- 事件 ----------
    def _handle_event(self) -> None:
        ev = render_event_display(self.game)
        if ev:
            print(ev)
            try:
                choice = input("选择 > ").strip()
            except EOFError:
                choice = "0"
            idx = self._parse_int(choice, 0)
            result = self.game.resolve_event(idx)
            print(">>", result)
        self.state = "MAIN"

    # ---------- 主菜单 ----------
    def _handle_main(self) -> None:
        print("\n" + R.render_header(self.game))
        print(R.render_map(self.game))
        print(R.render_strongholds(self.game, self.game.player_id))
        print(R.render_armies(self.game, self.game.player_id))
        print("\n命令: b=建造 r=招募英雄 m=移动/攻击 n=下一回合 e=事件(若有) q=退出")
        try:
            cmd = input("> ").strip().lower()
        except EOFError:
            cmd = "q"
        if cmd == "q":
            print("退出游戏。")
            raise SystemExit(0)
        elif cmd == "b":
            self.state = "BUILD"
        elif cmd == "r":
            self.state = "RECRUIT"
        elif cmd == "m":
            self.state = "MOVE"
        elif cmd == "n":
            self.state = "END"
        elif cmd == "e":
            if self.game.pending_event:
                self.state = "EVENT"
            else:
                print("无待处理事件。")
        elif cmd == "?":
            print(self._help())
        else:
            print("未知命令。")

    def _help(self) -> str:
        return ("命令:\n"
                "  b - 在己方据点建造产出建筑\n"
                "  r - 在己方据点招募英雄(需资源+信念门槛)\n"
                "  m - 选择部队移动/攻击邻接结点\n"
                "  n - 结束本回合(AI 行动后进入下一回合)\n"
                "  e - 处理待定事件\n"
                "  q - 退出")

    # ---------- 建造 ----------
    def _handle_build(self) -> None:
        p = self.game.factions[self.game.player_id]
        shs = [sid for sid in p.stronghold_ids if self.game.map.strongholds[sid].free_slots() > 0]
        if not shs:
            print("无空槽据点。")
            self.state = "MAIN"
            return
        print("选择据点:")
        for i, sid in enumerate(shs):
            print(f"  [{i}] {self.game.map.strongholds[sid].name} (空槽 {self.game.map.strongholds[sid].free_slots()})")
        try:
            ci = input("据点 > ").strip()
        except EOFError:
            self.state = "MAIN"; return
        idx = self._parse_int(ci, -1)
        if idx < 0 or idx >= len(shs):
            print("取消。")
            self.state = "MAIN"; return
        self._build_sh = shs[idx]
        print(R.render_buildable(self.game, self._build_sh))
        try:
            bi = input("建筑序号(取消-1) > ").strip()
        except EOFError:
            self.state = "MAIN"; return
        bidx = self._parse_int(bi, -1)
        if bidx < 0:
            self.state = "MAIN"; return
        bids = list(self.game.building_defs.keys())
        if bidx >= len(bids):
            print("无效。")
            self.state = "MAIN"; return
        msg = self.game.action_build(self.game.player_id, self._build_sh, bids[bidx])
        print(">>", msg)
        self.state = "MAIN"

    # ---------- 招募 ----------
    def _handle_recruit(self) -> None:
        p = self.game.factions[self.game.player_id]
        shs = [sid for sid in p.stronghold_ids
               if p.recruitment_pools.get(sid)
               and any(h is not None for h in p.recruitment_pools[sid].offerings)]
        if not shs:
            print("无可招募英雄的据点。")
            self.state = "MAIN"; return
        print("选择据点:")
        for i, sid in enumerate(shs):
            print(f"  [{i}] {self.game.map.strongholds[sid].name}")
        try:
            ci = input("据点 > ").strip()
        except EOFError:
            self.state = "MAIN"; return
        idx = self._parse_int(ci, -1)
        if idx < 0 or idx >= len(shs):
            self.state = "MAIN"; return
        self._recruit_sh = shs[idx]
        print(R.render_recruits(self.game, self._recruit_sh))
        try:
            hi = input("英雄序号(取消-1) > ").strip()
        except EOFError:
            self.state = "MAIN"; return
        hidx = self._parse_int(hi, -1)
        if hidx < 0:
            self.state = "MAIN"; return
        pool = p.recruitment_pools[self._recruit_sh]
        if hidx >= len(pool.offerings) or pool.offerings[hidx] is None:
            print("无效。")
            self.state = "MAIN"; return
        hid = pool.offerings[hidx]
        msg = self.game.action_recruit_hero(self.game.player_id, self._recruit_sh, hid)
        print(">>", msg)
        self.state = "MAIN"

    # ---------- 移动/攻击 ----------
    def _handle_move(self) -> None:
        p = self.game.factions[self.game.player_id]
        armies = [(aid, a) for aid in p.army_ids
                  if (a := self.game.armies.get(aid)) and not a.has_acted_this_turn]
        if not armies:
            print("无可用部队(都已行动)。")
            self.state = "MAIN"; return
        print("选择部队:")
        for i, (aid, a) in enumerate(armies):
            print(f"  [{i}] {a.name} @ {self.game.map.node_name(a.node_id)}")
        try:
            ai_in = input("部队 > ").strip()
        except EOFError:
            self.state = "MAIN"; return
        idx = self._parse_int(ai_in, -1)
        if idx < 0 or idx >= len(armies):
            self.state = "MAIN"; return
        army = armies[idx][1]
        nbrs = self.game.map.neighbors(army.node_id)
        print("可移动到:")
        for i, n in enumerate(nbrs):
            tag = ""
            if n in self.game.map.strongholds:
                sh = self.game.map.strongholds[n]
                tag = f"[据点:{'中立' if sh.owner is None else sh.owner}]"
            else:
                tag = f"[小地点:{self.game.map.minors[n].terrain}]"
            print(f"  [{i}] {self.game.map.node_name(n)} {tag}")
        try:
            ni = input("目标 > ").strip()
        except EOFError:
            self.state = "MAIN"; return
        nidx = self._parse_int(ni, -1)
        if nidx < 0 or nidx >= len(nbrs):
            self.state = "MAIN"; return
        target = nbrs[nidx]
        msg = self.game.action_move_attack(self.game.player_id, army.id, target)
        print(">>", msg)
        if self.game.is_over():
            self._print_winner()
            raise SystemExit(0)
        self.state = "MAIN"

    # ---------- 结束回合 ----------
    def _end_turn(self) -> None:
        game = self.game
        # AI 行动
        for fid, f in game.factions.items():
            if fid == game.player_id or not f.alive:
                continue
            print(f"\n--- {f.name} 行动 ---")
            actions = ai_take_turn(f, game)
            for kind, payload in actions:
                self._exec_ai_action(fid, kind, payload)
                if game.is_over():
                    self._print_winner()
                    raise SystemExit(0)
        # 回合结束推进
        game.end_turn_advance()
        # 复位部队行动标记
        for a in game.armies.values():
            a.has_acted_this_turn = False
        game.check_winner()
        if game.is_over():
            self._print_winner()
            raise SystemExit(0)
        # 下一回合玩家开始
        self._begin_player_turn()

    def _exec_ai_action(self, fid: str, kind: str, payload: dict) -> None:
        if kind == "build":
            msg = self.game.action_build(fid, payload["stronghold"], payload["building"])
            print(f"  AI 建造:{msg}")
        elif kind == "recruit_hero":
            msg = self.game.action_recruit_hero(fid, payload["stronghold"], payload["hero"])
            print(f"  AI 招募:{msg}")
        elif kind == "move_attack":
            msg = self.game.action_move_attack(fid, payload["army"], payload["to"])
            print(f"  AI 行动:{msg}")

    # ---------- 工具 ----------
    def _parse_int(self, s: str, default: int) -> int:
        try:
            return int(s)
        except ValueError:
            return default

    def _print_winner(self) -> None:
        w = self.game.winner
        if w:
            name = self.game.factions[w].name
            print(f"\n===== 游戏结束 =====")
            print(f"胜者:{name}")
        else:
            print("\n游戏结束(无胜者)")
        # 打印日志尾部
        print("\n--- 最近事件 ---")
        for line in self.game.log[-8:]:
            print("  " + line)


def render_event_display(game: Game) -> str | None:
    return R.render_event(game)
