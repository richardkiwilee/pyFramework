"""招募场景：3 窗口 = 当前据点招募池的 3 名英雄，回车招募。

按 操作逻辑.md（招募界面）：
- 左右分成 3 个窗口，分别是 3 个单位（招募池的 3 个 offerings）。
- 每个窗口显示单位详情和招募费用，回车招募。
- 招募成功后**留在本场景**：被招募的窗口置空显示"（空位）/已被招募"，
  其余英雄原位保留；3 个都招满即 3 个空栏位。不再跳转聚贤庄——业务层
  action_recruit_hero 现在把英雄送入聚贤庄（hall_of_worthies）待命，不自动
  编入部队；玩家可后续在据点界面将其指派为领主，或新建部队时任队长
  （见 §8）。聚贤庄场景暂未挂接入口（待业务层扩展召唤/登场/冷却机制）。

交互：
- ↑↓ 切换己方据点（每个据点有独立招募池，每 14 天刷新 3 个）。
- ←→ 在 3 个窗口间移动焦点。
- 回车招募焦点窗口的英雄：走 Game.action_recruit_hero（资源/信念校验），
  成功则 log + 留在本场景（该格置空）；失败则 log 警告并留在本场景。
- ESC 返回枢纽。

业务层 RecruitmentPool.offerings 为**固定 3 槽**列表：每槽为 hero_def id 或
None（已招募/未刷新出的空位）。招募把对应槽位置 None，不压缩，故三窗口与槽
位一一对应——被招募的窗口才空，其余英雄原位保留。pool 由 tick_economy 每 14
天自动刷新（重填 3 槽）；此处只读 pool.offerings。
"""
from __future__ import annotations

from typing import Any

from pyconsole.core import actions
from pyconsole.core.scene import Scene, SceneResult, PUSH, POP, NONE
from pyconsole.io.buffer import FrameBuffer
from pyconsole.io import theme
from pyconsole.io.widgets import draw_box, fill_rect
from pyconsole.io.width import text_width

from .. import controller as ctrl_mod
from .. import log
from pydemo.game.economy import RESOURCE_CN
from pydemo.game.hero import meets_belief_req, describe_req
from pydemo.game.unit import ATTR_CN, TAG_CN

# 3 个窗口矩形（x, y, w, h）。外框 (0,0,100,30)，y=3..27 给窗口。
W1 = (1, 3, 33, 25)
W2 = (34, 3, 32, 25)
W3 = (66, 3, 33, 25)
WINDOWS = [W1, W2, W3]

# 详情里展示的基础属性（按重要性排列，窗口高度有限）
DETAIL_ATTRS = ["hp", "p_atk", "m_atk", "p_def", "m_def", "speed", "acc", "eva", "block", "crit", "will"]


class RecruitScene(Scene):
    allow_status_overlay = True

    def __init__(self) -> None:
        super().__init__()
        self.sh_index = 0        # 当前据点在己方据点列表中的下标
        self.focus = 0           # 3 窗口焦点（0..2）
        self._sh_ids: list[str] = []

    def on_enter(self, params: Any = None) -> None:
        self.params = params
        self._sh_ids = self._stronghold_ids()
        if not self._sh_ids:
            # 无己方据点：退回首都占位（理论上不会发生）
            cap = ctrl_mod.ctrl.player().capital_id
            self._sh_ids = [cap] if cap else []
        # 可由 params 指定初始据点
        if isinstance(params, dict) and params.get("stronghold_id"):
            sid = params["stronghold_id"]
            if sid in self._sh_ids:
                self.sh_index = self._sh_ids.index(sid)
        self.focus = 0

    # ---- 数据 ----
    def _stronghold_ids(self) -> list[str]:
        return list(ctrl_mod.ctrl.player().stronghold_ids)

    def _current_sh(self):
        if not self._sh_ids:
            return None
        sid = self._sh_ids[self.sh_index % len(self._sh_ids)]
        return ctrl_mod.ctrl.g.map.strongholds.get(sid)

    def _pool(self):
        sh = self._current_sh()
        if sh is None:
            return None
        return ctrl_mod.ctrl.player().recruitment_pools.get(sh.id)

    def _offerings(self) -> list:
        """当前据点招募池的 offerings（固定 3 槽：hero_def id 或 None）。"""
        pool = self._pool()
        return list(pool.offerings) if pool else []

    def _focused_hero_id(self) -> str | None:
        offs = self._offerings()
        if not offs:
            return None
        idx = self.focus % len(offs)
        return offs[idx] if idx < len(offs) else None

    # ---- 输入 ----
    def handle_action(self, event) -> SceneResult:
        a = event.action
        if a == actions.BACK:
            return POP()
        if a == actions.UP:
            self._cycle_stronghold(-1)
            self.focus = 0
            return NONE()
        if a == actions.DOWN:
            self._cycle_stronghold(1)
            self.focus = 0
            return NONE()
        if a == actions.LEFT:
            self._move_focus(-1)
            return NONE()
        if a == actions.RIGHT:
            self._move_focus(1)
            return NONE()
        if a in (actions.CONFIRM, actions.SELECT):
            return self._recruit()
        return NONE()

    def _cycle_stronghold(self, delta: int) -> None:
        if len(self._sh_ids) > 1:
            self.sh_index = (self.sh_index + delta) % len(self._sh_ids)

    def _move_focus(self, delta: int) -> None:
        offs = self._offerings()
        if not offs:
            self.focus = 0
            return
        # 焦点在固定 3 窗口间循环移动（含已空槽），窗口与槽位一一对应
        n = len(offs)
        self.focus = (self.focus + delta) % n

    def _recruit(self) -> SceneResult:
        g = ctrl_mod.ctrl.g
        sh = self._current_sh()
        if sh is None:
            log.push("无可招募据点", warn=True)
            return NONE()
        hid = self._focused_hero_id()
        if hid is None:
            log.push("该窗口无英雄可招募", warn=True)
            return NONE()
        msg = g.action_recruit_hero(g.player_id, sh.id, hid)
        ok = not msg.startswith("失败")
        log.push(msg, warn=not ok)
        if not ok:
            return NONE()
        # 招募成功：留在本场景，被招募的窗口置空（见 _render_window 的 None 分支）
        return NONE()

    # ---- 渲染 ----
    def render(self, buf: FrameBuffer) -> None:
        w, h = buf.w, buf.h
        draw_box(buf, 0, 0, w, h, title="招募一览")
        self._render_header(buf, w)
        for cx in range(1, w - 1):
            buf.set_char(cx, 2, "─", theme.BORDER, theme.BG)
        # 3 窗口
        offs = self._offerings()
        for i, rect in enumerate(WINDOWS):
            self._render_window(buf, rect, i, offs)
        # 图例 y=28
        buf.put_text(2, 28, "↑↓ 切换据点  ←→ 选择英雄  回车 招募  ESC 返回",
                     theme.DIM, theme.BG)

    def _render_header(self, buf: FrameBuffer, w: int) -> None:
        sh = self._current_sh()
        if sh is None:
            buf.put_text(2, 1, "（无己方据点）", theme.WARN, theme.BG)
            return
        pool = self._pool()
        refresh = pool.refresh_day if pool else "?"
        offs = self._offerings()
        # 池中剩余可招募英雄数（None 槽位不计入）
        remaining = sum(1 for o in offs if o is not None)
        head = f"据点: {sh.name}  (池中 {remaining}/3 · 下次刷新 第{refresh}天)"
        buf.put_text(2, 1, head, theme.HEADING, theme.BG)
        if len(self._sh_ids) > 1:
            buf.put_text(2 + text_width(head) + 2, 1,
                         f"  [{self.sh_index + 1}/{len(self._sh_ids)}] ↑↓切换",
                         theme.DIM, theme.BG)

    def _render_window(self, buf: FrameBuffer, rect: tuple, idx: int, offs: list) -> None:
        x, y, ww, hh = rect
        active = (idx == self.focus)
        border = theme.ACCENT if active else theme.BORDER
        draw_box(buf, x, y, ww, hh, title=f"英雄 {idx + 1}", fg=border)
        # 空场景：无池或窗口下标越界
        if not offs or idx >= len(offs):
            buf.put_text(x + 1, y + 1, "（空位）", theme.DIM, theme.BG)
            buf.put_text(x + 1, y + 3, "等待下次刷新", theme.DIM, theme.BG)
            return
        hid = offs[idx]
        # 该槽位已被招募（None）：显示空位，其余英雄原位保留
        if hid is None:
            buf.put_text(x + 1, y + 1, "（空位）", theme.DIM, theme.BG)
            buf.put_text(x + 1, y + 3, "已被招募", theme.DIM, theme.BG)
            return
        g = ctrl_mod.ctrl.g
        hdef = g.hero_defs.get(hid)
        if hdef is None:
            buf.put_text(x + 1, y + 1, f"未知英雄 {hid}", theme.WARN, theme.BG)
            return
        player = ctrl_mod.ctrl.player()
        ry = y + 1
        # 名称
        buf.put_text(x + 1, ry, hdef.name, theme.HEADING, theme.BG); ry += 1
        # 词条
        tagstr = "/".join(TAG_CN.get(t, t) for t in sorted(hdef.tags))
        buf.put_text(x + 1, ry, f"词条 {tagstr}", theme.DIM, theme.BG); ry += 1
        ry += 1
        # 招募费用
        buf.put_text(x + 1, ry, "招募费用", theme.ACCENT, theme.BG); ry += 1
        ok_cost = player.resources.can_afford(hdef.recruit_cost)
        if hdef.recruit_cost:
            cost_txt = "  ".join(f"{RESOURCE_CN.get(k, k)}:{v}" for k, v in hdef.recruit_cost.items())
        else:
            cost_txt = "免费"
        buf.put_text(x + 1, ry, cost_txt, theme.GOLD if ok_cost else theme.WARN, theme.BG); ry += 1
        ry += 1
        # 信念要求
        buf.put_text(x + 1, ry, "信念要求", theme.ACCENT, theme.BG); ry += 1
        ok_belief = meets_belief_req(player.belief, hdef.belief_req)
        buf.put_text(x + 1, ry, describe_req(hdef.belief_req),
                     theme.GOLD if ok_belief else theme.WARN, theme.BG); ry += 1
        ry += 1
        # 基础属性
        buf.put_text(x + 1, ry, "基础属性", theme.ACCENT, theme.BG); ry += 1
        for attr in DETAIL_ATTRS:
            if ry >= y + hh - 1:
                break
            val = hdef.base.get(attr, 0)
            buf.put_text(x + 1, ry, f"{ATTR_CN.get(attr, attr)}: {int(val)}", theme.FG, theme.BG)
            ry += 1
        # 技能
        if hdef.skills and ry < y + hh - 1:
            buf.put_text(x + 1, ry, "技能 " + "/".join(hdef.skills), theme.ACCENT2, theme.BG)

    def get_hints(self) -> list[str]:
        return ["↑↓ 切换据点", "←→ 选择英雄", "回车 招募", "ESC 返回"]
