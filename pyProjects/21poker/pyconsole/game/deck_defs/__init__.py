"""套牌定义（每套一文件）。

- 基础：标准 13 张，A=1|11 多值，无效果。
- 剥削：点数分布同基础，2/3/4/5 带「打出效果:剥削1」。
- 损坏：点数分布同基础，6/7/8/9 带「终局效果:损坏」。

每文件导出一个 Suit；__init__.py 汇总为 DECK_DEF。
"""
from .base import SUIT_BASE
from .exploit import SUIT_EXPLOIT
from .broken import SUIT_BROKEN
from ..cards import DeckDef

# 全部已定义套牌。2 人局 sample_for(2) 抽 2 套合并。
DECK_DEF = DeckDef((SUIT_BASE, SUIT_EXPLOIT, SUIT_BROKEN))

__all__ = ["DECK_DEF", "SUIT_BASE", "SUIT_EXPLOIT", "SUIT_BROKEN"]
