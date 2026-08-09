"""控制器：持有 Game 单例 + 回合编排。

框架 pyconsole 的 App 是框架持有的，我们不打算改框架；也不打算通过
on_enter(params) 把 Game 逐层传递（兄弟场景懒导入时还要传参会很繁琐）。
模块级单例是最轻的解耦方式：场景 import controller 读/写同一个实例，
仍可单测（直接构造/替换模块内 ctrl）。

回合编排复制自 python-demo/pydemo/cli/fsm.py::_end_turn / _begin_player_turn：
业务层没有"下一回合"入口，故由控制器拼装（AI 行动 → 日历推进 → 复位部队
行动标记 → 胜负判定）。

科技/文化学习记录(B7)已移入 Faction(tech_learned/culture_learned);
控制器不再持有 TUI 侧学习集合,学习走业务层 Game.action_learn_tech/culture。
"""
from __future__ import annotations

from typing import Any

from pydemo.cli.scenario import build_scenario
from pydemo.game.game import Game
from pydemo.game.ai import ai_take_turn

from . import log


class _Controller:
    def __init__(self) -> None:
        self.game: Game | None = None

    # ---- 生命周期 ----
    def new_game(self) -> Game:
        """开新局：重建场景。"""
        self.game = build_scenario()
        log.clear()
        log.push("新游戏开始：攻破 AI 首都即获胜")
        # 玩家第 1 回合开始结算
        self.begin_player_turn()
        return self.game

    @property
    def g(self) -> Game:
        if self.game is None:
            self.new_game()
        assert self.game is not None
        return self.game

    def player(self):
        return self.g.factions[self.g.player_id]

    # ---- 回合编排（镜像 cli/fsm.py）----
    def begin_player_turn(self) -> None:
        """玩家回合开始：经济结算(含维护费/回血) + 招募池刷新 + 事件触发。"""
        g = self.g
        p = g.factions[g.player_id]
        g.start_turn(p)
        g.maybe_trigger_event(p)

    def run_ai_and_advance(self) -> None:
        """结束玩家回合：AI 行动 → 日历推进 → 复位部队行动标记 → 胜负判定。

        若有待处理事件尚未选择，自动按选项 0 处理，避免卡住。
        """
        g = self.g
        # 玩家未处理的事件自动选 0
        if g.pending_event:
            msg = g.resolve_event(0)
            log.push(f"事件:{msg}")
        # AI 行动
        for fid, f in g.factions.items():
            if fid == g.player_id or not f.alive:
                continue
            for kind, payload in ai_take_turn(f, g):
                self._exec_ai_action(fid, kind, payload)
                if g.is_over():
                    break
            if g.is_over():
                break
        # 日历推进 + 部队标记复位 + 胜负
        g.end_turn_advance()
        for a in g.armies.values():
            a.has_acted_this_turn = False
        g.check_winner()
        if g.is_over():
            self._log_winner()
            return
        # 下一回合玩家开始
        self.begin_player_turn()

    def _exec_ai_action(self, fid: str, kind: str, payload: dict) -> None:
        g = self.g
        if kind == "build":
            msg = g.action_build(fid, payload["stronghold"], payload["building"])
            log.push(f"AI 建造:{msg}")
        elif kind == "recruit_hero":
            msg = g.action_recruit_hero(fid, payload["stronghold"], payload["hero"])
            log.push(f"AI 招募:{msg}")
        elif kind == "move_attack":
            msg = g.action_move_attack(fid, payload["army"], payload["to"])
            log.push(f"AI 行动:{msg}")
        elif kind == "deploy":
            msg = g.action_deploy(fid, payload["army"], payload["unit"], payload.get("slot"))
            log.push(f"AI 上场:{msg}")
        elif kind == "new_army":
            node_id = payload["stronghold"]
            name = payload.get("name", "AI 部队")
            army = g.create_army(fid, node_id, name)
            hero = g.unit_index.get(payload["hero"])
            if not hero or not g.set_captain(army, hero):
                g.disband_army(army)
                log.push(f"AI 新建部队:失败({payload.get('hero')})")
            else:
                log.push(f"AI 新建部队:{army.name}(队长 {hero.name})")
        elif kind == "learn_tech":
            msg = g.action_learn_tech(fid, payload["tech"])
            log.push(f"AI 研究科技:{msg}")
        elif kind == "learn_culture":
            msg = g.action_learn_culture(fid, payload["culture"])
            log.push(f"AI 研究文化:{msg}")
        elif kind == "recruit_unit":
            msg = g.action_recruit_unit(fid, payload["unit"])
            log.push(f"AI 招兵:{msg}")

    def _log_winner(self) -> None:
        w = self.g.winner
        if w and w in self.g.factions:
            log.push(f"游戏结束！胜者：{self.g.factions[w].name}")
        else:
            log.push("游戏结束（无胜者）")

    # ---- 存档读档(B5) ----
    # 完整 JSON 序列化到 pydemo/saves/save001.dat(单存档);Game.snapshot/restore 重建对象图。
    # 路径相对 pydemo 包根(随 __file__ 定位),确保任意 cwd 可用。
    def _save_path(self) -> str:
        import os
        pkg_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        return os.path.join(pkg_root, "saves", "save001.dat")

    def save(self) -> str:
        import json
        import os
        path = self._save_path()
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            data = self.g.snapshot()
            with open(path, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
            return f"已保存(第 {self.g.calendar.day} 天)"
        except (OSError, ValueError) as e:
            return f"保存失败：{e}"

    def load(self) -> str:
        import json
        import os
        from pydemo.game.game import Game
        path = self._save_path()
        if not os.path.isfile(path):
            return "无存档（开始新游戏）"
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            self.game = Game.restore(data)
            return f"已读取(第 {self.game.calendar.day} 天)"
        except (OSError, ValueError, KeyError) as e:
            return f"读取失败：{e}"


ctrl = _Controller()
