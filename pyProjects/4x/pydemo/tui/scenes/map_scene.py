"""地图场景：ASCII 拓扑图 + 各据点驻军数量。

按 操作逻辑.md：用简单 ASCII 画出据点拓扑，在据点旁标明该据点内的驻军数量。

实现要点：
- 据/小地点按 scenario 的固定 (x,y) 坐标做紧凑缩放（x 拉满宽度、y 用小刻度），
  避免纵向过疏导致连线拉得过长。
- 节点用 ◆ 据点 / · 小地点 + 名称；据点名称后内联 [驻军数]，颜色按归属。
- 边用 Bresenham 画 ─│╲╱ + 拐角，相邻节点间连一条线。
- ESC 返回，只读视图。

`render_topology(buf, rect, g)` 把拓扑图画进任意矩形，供本场景与游戏主场景（地图作
主场景）复用。
"""
from __future__ import annotations

from typing import Any

from pyconsole.core import actions
from pyconsole.core.scene import Scene, SceneResult, NONE, POP
from pyconsole.io.buffer import FrameBuffer
from pyconsole.io import theme
from pyconsole.io.widgets import draw_box
from pyconsole.io.width import text_width

from .. import controller as ctrl_mod
from .. import log

# 归属颜色
C_OWN = 41       # 绿
C_ENEMY = 196    # 红
C_NEUTRAL = 254  # 白
C_MINOR = 245    # 暗灰白


def _field_unit_counts(g, nid: str) -> tuple[int, int]:
    """该节点的野战部队存活单位数：(我方, 敌方)。

    仅计非驻军、未全灭、且 node_id==nid 的部队。每帧从 g 现算，故部队
    创建/移动后即时反映（action_move_attack 直接改 army.node_id）。
    """
    n_own = 0
    n_enemy = 0
    pid = g.player_id
    for a in g.armies.values():
        if a.is_garrison or a.node_id != nid:
            continue
        if a.is_wiped(g.unit_index):
            continue
        cnt = len(a.alive_units(g.unit_index))
        if a.owner == pid:
            n_own += cnt
        elif a.owner is not None:
            n_enemy += cnt
    return n_own, n_enemy


def _field_color(n_own: int, n_enemy: int) -> int:
    """据 [N] 显示色：仅我方=绿、仅敌方=红、双方接触=黄(WARN)。"""
    if n_own > 0 and n_enemy > 0:
        return theme.WARN
    if n_own > 0:
        return C_OWN
    if n_enemy > 0:
        return C_ENEMY
    return theme.DIM


def render_topology(buf: FrameBuffer, rect: tuple[int, int, int, int], g) -> None:
    """把据点拓扑图（节点 + 连线 + 驻军数）画进矩形 rect=(x, y, w, h)。

    节点标签会被夹在 [x, x+w-1] 内，避免越出给定区域。
    """
    x, y, w, h = rect
    if w < 4 or h < 4:
        return
    m = g.map

    # 收集节点坐标
    nodes: dict[str, tuple[int, int, str]] = {}
    for sid, sh in m.strongholds.items():
        nodes[sid] = (sh.x, sh.y, "stronghold")
    for mid, mi in m.minors.items():
        nodes[mid] = (mi.x, mi.y, "minor")
    if not nodes:
        return

    xs = [n[0] for n in nodes.values()]
    ys = [n[1] for n in nodes.values()]
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)
    span_x = max(1, max_x - min_x)
    span_y = max(1, max_y - min_y)

    # 紧凑映射：x 拉满内部宽度，y 用自适应刻度（避免纵向过疏）
    pad = 3
    inner_left = x + pad
    inner_right = x + w - pad
    iw = max(1, inner_right - inner_left)
    inner_top = y + 1
    y_scale = max(1, min(5, (h - 2) // span_y))

    screen: dict[str, tuple[int, int]] = {}
    for nid, (nx, ny, _k) in nodes.items():
        sx = inner_left + (nx - min_x) * iw // span_x if span_x else inner_left + iw // 2
        sy = inner_top + (ny - min_y) * y_scale
        screen[nid] = (sx, sy)

    # 先画边，再画节点（节点覆盖端点）
    seen = set()
    for a, nbrs in m.adj.items():
        for b in nbrs:
            key = tuple(sorted((a, b)))
            if key in seen:
                continue
            seen.add(key)
            _draw_edge(buf, screen.get(a), screen.get(b))
    for nid, (sx, sy) in screen.items():
        _draw_node(buf, nid, sx, sy, m, g, x, w)


def _draw_edge(buf: FrameBuffer, a: tuple[int, int] | None,
               b: tuple[int, int] | None) -> None:
    if not a or not b:
        return
    ax, ay = a
    bx, by = b
    fg = theme.BORDER
    points = _bresenham(ax, ay, bx, by)
    prev = (ax, ay)
    prev_dir = None
    for (px, py) in points[1:-1]:
        dx = _sign(px - prev[0])
        dy = _sign(py - prev[1])
        ch = _dir_char(prev_dir, (dx, dy))
        buf.set_char(px, py, ch, fg, theme.BG)
        prev_dir = (dx, dy)
        prev = (px, py)


def _draw_node(buf: FrameBuffer, nid: str, sx: int, sy: int, m, g,
               clip_x: int, clip_w: int) -> None:
    is_sh = nid in m.strongholds
    label = m.node_name(nid)
    # 野战部队存活单位数（每帧现算：部队创建/移动后即时反映）
    n_own, n_enemy = _field_unit_counts(g, nid)
    n_field = n_own + n_enemy
    if is_sh:
        sh = m.strongholds[nid]
        if sh.owner == g.player_id:
            fg = C_OWN; tag = "我"
        elif sh.owner is None:
            fg = C_NEUTRAL; tag = "中"
        else:
            fg = C_ENEMY; tag = "敌"
        text = f"◆{label}"
        if n_field > 0:
            gtxt = f"[{n_field}]"
            full = f"{text} {gtxt}({tag})"
        else:
            gtxt = ""
            full = f"{text}({tag})"
    else:
        fg = C_MINOR
        if n_field > 0:
            text = f"·{label}"
            gtxt = f"[{n_field}]"
            full = f"{text} {gtxt}"
        else:
            full = f"·{label}"
            gtxt = ""
    tw = text_width(full)
    # 居中锚点，但夹在区域内 [clip_x, clip_x+clip_w-1-tw]
    tx = max(clip_x, sx - tw // 2)
    tx = min(tx, clip_x + clip_w - 1 - tw)
    if is_sh:
        tx = buf.put_text(tx, sy, text, fg, theme.BG)
        if gtxt:
            field_fg = _field_color(n_own, n_enemy)
            tx = buf.put_text(tx, sy, " ", fg, theme.BG)
            buf.put_text(tx, sy, gtxt, field_fg, theme.BG)
            tx += text_width(gtxt)
        buf.put_text(tx, sy, f"({tag})", fg, theme.BG)
    else:
        buf.put_text(tx, sy, f"·{label}", fg, theme.BG)
        if n_field > 0:
            field_fg = _field_color(n_own, n_enemy)
            tx = buf.put_text(tx, sy, " ", fg, theme.BG)
            buf.put_text(tx, sy, gtxt, field_fg, theme.BG)


def _render_legend(buf: FrameBuffer, x: int, y: int, w: int) -> None:
    parts = [("◆我方", C_OWN), ("  ◆敌方", C_ENEMY), ("  ◆中立", C_NEUTRAL),
             ("  ·小地点", C_MINOR)]
    cx = x
    for txt, fg in parts:
        cx = buf.put_text(cx, y, txt, fg, theme.BG)
    buf.put_text(cx + 2, y, "[N]=该节点野战部队存活单位数(绿我红敌黄接触)", theme.DIM, theme.BG)


class MapScene(Scene):
    """独立地图场景：全屏拓扑图。游戏主场景亦内嵌地图（见 game_scene.py）。"""
    allow_status_overlay = True

    def __init__(self) -> None:
        super().__init__()
        self._positions: dict[str, tuple[int, int]] = {}

    def on_enter(self, params: Any = None) -> None:
        self.params = params

    def handle_action(self, event) -> SceneResult:
        if event.action == actions.BACK:
            return POP()
        return NONE()

    # ---- 渲染 ----
    def render(self, buf: FrameBuffer) -> None:
        w, h = buf.w, buf.h
        draw_box(buf, 0, 0, w, h, title="地图一览")
        g = ctrl_mod.ctrl.g
        render_topology(buf, (1, 1, w - 2, h - 3), g)
        _render_legend(buf, 2, h - 3, w)
        # §6 底部日志栏 y=h-2（键提示由框架在 h-1 绘制）
        log.render_log_bar(buf, 0, h - 2, w)

    def get_hints(self) -> list[str]:
        return ["ESC 返回"]


def _sign(v: int) -> int:
    return (v > 0) - (v < 0)


def _bresenham(x0: int, y0: int, x1: int, y1: int) -> list[tuple[int, int]]:
    """整数 Bresenham 线（含端点）。"""
    pts: list[tuple[int, int]] = []
    dx = abs(x1 - x0)
    dy = -abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx + dy
    x, y = x0, y0
    while True:
        pts.append((x, y))
        if x == x1 and y == y1:
            break
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x += sx
        if e2 <= dx:
            err += dx
            y += sy
    return pts


def _dir_char(prev_dir: tuple[int, int] | None, cur: tuple[int, int]) -> str:
    """根据当前步方向（与前一步方向）选字符。"""
    dx, dy = cur
    if dx == 0 and dy != 0:
        ch = "│"
    elif dy == 0 and dx != 0:
        ch = "─"
    elif (dx, dy) in ((1, 1), (-1, -1)):
        ch = "╲"
    else:
        ch = "╱"
    # 拐角修正：前一步与本步一个水平一个垂直时，本格应为拐角
    if prev_dir is not None:
        pdx, pdy = prev_dir
        prev_h = pdy == 0 and pdx != 0
        prev_v = pdx == 0 and pdy != 0
        cur_h = dy == 0 and dx != 0
        cur_v = dx == 0 and dy != 0
        if (prev_h and cur_v) or (prev_v and cur_h):
            if prev_dir[0] > 0 and cur[1] > 0:   # → 再 ↓ : ┐
                ch = "┐"
            elif prev_dir[0] > 0 and cur[1] < 0:  # → 再 ↑ : ┘
                ch = "┘"
            elif prev_dir[0] < 0 and cur[1] > 0:  # ← 再 ↓ : ┌
                ch = "┌"
            elif prev_dir[0] < 0 and cur[1] < 0:  # ← 再 ↑ : └
                ch = "└"
            elif prev_dir[1] > 0 and cur[0] > 0:  # ↓ 再 → : ┌
                ch = "┌"
            elif prev_dir[1] > 0 and cur[0] < 0:  # ↓ 再 ← : ┐
                ch = "┐"
            elif prev_dir[1] < 0 and cur[0] > 0:  # ↑ 再 → : └
                ch = "└"
            elif prev_dir[1] < 0 and cur[0] < 0:  # ↑ 再 ← : ┘
                ch = "┘"
    return ch
