"""
时间系统:Day / Moon Phase / Time of Day / Turn。

- 1 Turn = 1 Day。顺序回合制。
- 月相:14 天周期,14 个连续阶段。魔力恢复从新月 +0 到满月 +6 线性插值。
- 昼夜:5 段(清晨/白天/黄昏/夜晚/深夜),每段固定 7 天,永不复位。
- 两者独立运行,不耦合。

月相魔力恢复插值:把 14 阶段看成 0..13 的索引,新月=0、满月=7(第 8 天),
恢复值 = min(index, 14-index) 的线性映射到 0..6。
"""
from __future__ import annotations

# 昼夜阶段名(5 段,每段 7 天,永不复位循环)
TIME_OF_DAY_STAGES = ["清晨", "白天", "黄昏", "夜晚", "深夜"]
TIME_OF_DAY_DAYS_PER_STAGE = 7

# 月相阶段数(14),满月在第 8 天(index 7)
MOON_CYCLE_DAYS = 14
MOON_FULL_INDEX = 7  # 满月


class Calendar:
    """游戏日历,记录第几天,派生月相与昼夜阶段。"""

    def __init__(self, day: int = 1) -> None:
        self.day = day  # 1-based: 第 1 天是开局

    def advance(self) -> None:
        self.day += 1

    # --- 月相 ---
    def moon_phase_index(self) -> int:
        """0..13,第 (day-1) % 14。"""
        return (self.day - 1) % MOON_CYCLE_DAYS

    def moon_phase_name(self) -> str:
        idx = self.moon_phase_index()
        # 给几个关键阶段命名,其余用"渐盈/渐亏"描述
        if idx == 0:
            return "新月"
        if idx == MOON_FULL_INDEX:
            return "满月"
        if idx == MOON_CYCLE_DAYS - 1:
            return "残月"
        return f"月相{idx + 1}({('渐盈' if idx < MOON_FULL_INDEX else '渐亏')})"

    def mana_regen(self) -> int:
        """当前月相的魔力恢复加成,新月 +0 到满月 +6 线性。"""
        idx = self.moon_phase_index()
        # 距新月或满月的距离取较小,映射到 0..6
        # 新月(0)->0, 满月(7)->6, 残月(13)->0
        dist = min(idx, MOON_CYCLE_DAYS - idx)
        # dist 范围 0..7,映射到 0..6
        return round(dist / MOON_FULL_INDEX * 6) if MOON_FULL_INDEX else 0

    # --- 昼夜 ---
    def time_of_day_index(self) -> int:
        """0..4,永不复位循环(每段 7 天)。"""
        raw = (self.day - 1) // TIME_OF_DAY_DAYS_PER_STAGE
        return raw % len(TIME_OF_DAY_STAGES)

    def time_of_day_name(self) -> str:
        return TIME_OF_DAY_STAGES[self.time_of_day_index()]

    def describe(self) -> str:
        return (f"第 {self.day} 天 · {self.time_of_day_name()} · "
                f"{self.moon_phase_name()}(魔力恢复 +{self.mana_regen()})")
