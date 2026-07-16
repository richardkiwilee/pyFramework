"""隐蔽式可逆卡背：在统一纹理里把点数 / 花色编码进几乎不可见的字符变体。

移植自仓库根的 ``stealth_marked_card_back.py``，并新增直接画进 ``FrameBuffer``
的渲染器，供 21 点 Tab 牌堆总览调用。

编码方案（解码可逆，见 :func:`decode_card_back`）：
- 花色：外框四角附近的竖边 ``│`` 改成 ``┆`` —— S=左上 / H=右上 / C=左下 / D=右下。
- 点数：顶边 13 个槽位之一 ``─`` 改成 ``┈``（1..13 → A,2..10,J,Q,K）。

注意：本模块的 ``SUITS`` 顺序是 ``["S","H","C","D"]``，与 :mod:`cards` 的
``("♠","♥","♦","♣")`` **不同**（后者把 ♦ 排在 ♣ 前），故花色↔编码用显式 dict
映射，不要用下标。
"""
from __future__ import annotations

from ..io.buffer import FrameBuffer
from ..io import theme
from .cards import Card, rank_label

RANKS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
SUITS = ["S", "H", "C", "D"]  # ♠ ♥ ♣ ♦ —— 注意与 cards.SUITS 顺序不同

# 卡牌花色字符 → 隐写编码（顺序无关，显式映射避免与 cards.SUITS 下标混淆）
SUIT_TO_CODE = {"♠": "S", "♥": "H", "♣": "C", "♦": "D"}
CODE_TO_SUIT = {v: k for k, v in SUIT_TO_CODE.items()}


def parse_card(card: str) -> tuple[str, str]:
    c = card.strip().upper()
    suit = c[-1]
    rank = c[:-1]
    if rank not in RANKS or suit not in SUITS:
        raise ValueError(f"非法牌面: {card}")
    return rank, suit


def make_base_back(width: int = 19, height: int = 11) -> list[list[str]]:
    """生成统一纹理的卡背网格（无编码）。"""
    if width < 15 or height < 9:
        raise ValueError("建议 width>=15, height>=9 以保证隐蔽编码")

    g = [[" " for _ in range(width)] for _ in range(height)]

    # 外框
    g[0][0], g[0][-1] = "┌", "┐"
    g[-1][0], g[-1][-1] = "└", "┘"
    for x in range(1, width - 1):
        g[0][x] = "─"
        g[-1][x] = "─"
    for y in range(1, height - 1):
        g[y][0] = "│"
        g[y][-1] = "│"

    # 统一纹理（低对比）
    tex = ("░", "▒")
    for y in range(1, height - 1):
        for x in range(1, width - 1):
            g[y][x] = tex[(x * 3 + y * 5) & 1]

    # 内部一圈细框，增强"背面感"
    y0, y1 = 2, height - 3
    x0, x1 = 2, width - 3
    g[y0][x0], g[y0][x1] = "╭", "╮"
    g[y1][x0], g[y1][x1] = "╰", "╯"
    for x in range(x0 + 1, x1):
        g[y0][x] = "┄"
        g[y1][x] = "┄"
    for y in range(y0 + 1, y1):
        g[y][x0] = "┆"
        g[y][x1] = "┆"

    return g


def embed_stealth(g: list[list[str]], rank: str, suit: str) -> list[list[str]]:
    """把点数 / 花色编码进卡背网格（原地修改并返回）。"""
    h, w = len(g), len(g[0])
    r_idx = RANKS.index(rank)   # 0..12
    s_idx = SUITS.index(suit)   # 0..3

    # ---------- 花色编码 ----------
    # 四角附近竖边 '│' → '┆'：S=左上, H=右上, C=左下, D=右下
    if s_idx == 0:        # S
        g[1][0] = "┆"
    elif s_idx == 1:      # H
        g[1][w - 1] = "┆"
    elif s_idx == 2:      # C
        g[h - 2][0] = "┆"
    elif s_idx == 3:      # D
        g[h - 2][w - 1] = "┆"

    # ---------- 点数编码 ----------
    # 顶边 13 个槽位：把对应位置 '─' 换成 '┈'（视觉极接近）
    slots = 13
    start = (w - slots) // 2
    if start < 1:
        start = 1
    if start + slots > w - 1:
        start = 1

    x = start + r_idx
    if not (1 <= x <= w - 2):
        raise ValueError("编码位置越界，请增大宽度")
    g[0][x] = "┈"

    return g


def render(g: list[list[str]]) -> str:
    return "\n".join("".join(row) for row in g)


def draw_card_back(card: str, width: int = 19, height: int = 11) -> str:
    rank, suit = parse_card(card)
    g = make_base_back(width, height)
    embed_stealth(g, rank, suit)
    return render(g)


def decode_card_back(art: str) -> str:
    """从卡背 ASCII 还原出牌面（如 ``'AS'``）。"""
    lines = art.splitlines()
    g = [list(row) for row in lines]
    h, w = len(g), len(g[0])

    # 解花色
    if g[1][0] == "┆":
        suit = "S"
    elif g[1][w - 1] == "┆":
        suit = "H"
    elif g[h - 2][0] == "┆":
        suit = "C"
    elif g[h - 2][w - 1] == "┆":
        suit = "D"
    else:
        raise ValueError("未检测到花色编码")

    # 解点数
    slots = 13
    start = (w - slots) // 2
    if start < 1:
        start = 1

    r_idx = None
    for i in range(13):
        x = start + i
        if 1 <= x <= w - 2 and g[0][x] == "┈":
            r_idx = i
            break
    if r_idx is None:
        raise ValueError("未检测到点数编码")

    rank = RANKS[r_idx]
    return f"{rank}{suit}"


# ---- FrameBuffer 渲染 ----

# 纹理字符用次要色，框线用边框色 —— 隐写标记 (┆ ┈) 与正常框线同色，更不突兀
_TEX_CHARS = ("░", "▒")


def blit_grid(buf: FrameBuffer, x: int, y: int, g: list[list[str]],
              border_fg: int = theme.BORDER, tex_fg: int = theme.DIM,
              bg: int = theme.BG) -> None:
    """把卡背网格画进缓冲 (x,y)，纹理与框线分色。空格透明（不覆盖底层）。"""
    for ry, row in enumerate(g):
        for cx, ch in enumerate(row):
            if ch == " ":
                continue
            fg = tex_fg if ch in _TEX_CHARS else border_fg
            buf.set_char(x + cx, y + ry, ch, fg, bg)


def draw_card_back_buf(buf: FrameBuffer, x: int, y: int, card: Card,
                       width: int = 19, height: int = 11,
                       border_fg: int = theme.BORDER, tex_fg: int = theme.DIM,
                       bg: int = theme.BG) -> None:
    """画一张带隐写编码的卡背进缓冲（牌面信息藏在纹理里，正面看是统一背面）。"""
    rank = rank_label(card.rank)          # "A".."K"
    code = SUIT_TO_CODE[card.suit]        # "S"/"H"/"C"/"D"
    g = make_base_back(width, height)
    embed_stealth(g, rank, code)
    blit_grid(buf, x, y, g, border_fg=border_fg, tex_fg=tex_fg, bg=bg)
