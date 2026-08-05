"""MessageScene：居中显示一段提示文本，按任意键弹回上层。"""
from __future__ import annotations

from typing import Any

from ..core import actions
from ..core.scene import Scene, SceneResult, POP, NONE
from ..io.buffer import FrameBuffer
from ..io import theme
from ..io.widgets import draw_box, put_centered


class MessageScene(Scene):
    allow_status_overlay = False

    def __init__(self, text: str) -> None:
        super().__init__()
        self.text = text

    def on_enter(self, params: Any = None) -> None:
        self.params = params

    def handle_action(self, event) -> SceneResult:
        # 任意键弹回
        return POP()

    def render(self, buf: FrameBuffer) -> None:
        w, h = buf.w, buf.h
        lines = self.text.split("\n")
        box_h = len(lines) + 4
        box_w = max(max(len(l) for l in lines), 20) + 8
        # CJK 双宽：用 text_width 算实际宽度
        from ..io.width import text_width
        box_w = max(max(text_width(l) for l in lines), 24) + 8
        bx = (w - box_w) // 2
        by = (h - box_h) // 2
        buf.fill_rect(bx - 1, by - 1, box_w + 2, box_h + 2, " ", theme.FG, theme.OVERLAY_BG)
        draw_box(buf, bx, by, box_w, box_h, title="提示", fg=theme.OVERLAY_BORDER, bg=theme.OVERLAY_BG)
        for i, line in enumerate(lines):
            tx = bx + (box_w - text_width(line)) // 2
            buf.put_text(tx, by + 2 + i, line, theme.FG, theme.OVERLAY_BG)
        put_centered(buf, by + box_h - 1, "按任意键返回", theme.DIM, theme.OVERLAY_BG)

    def get_hints(self) -> list[str]:
        return ["任意键 返回"]
