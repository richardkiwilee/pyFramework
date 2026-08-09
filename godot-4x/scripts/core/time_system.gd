## 时间系统：Day / Moon Phase / Time of Day（对应 pydemo/game/time_system.py）。
## 1 Turn = 1 Day；月相 14 天周期；昼夜 5 段每段 7 天；两者独立运行不耦合。
class_name Calendar
extends RefCounted

const TIME_OF_DAY_STAGES: Array[String] = ["清晨", "白天", "黄昏", "夜晚", "深夜"]
const TIME_OF_DAY_DAYS_PER_STAGE := 7
const MOON_CYCLE_DAYS := 14
const MOON_FULL_INDEX := 7   # 满月在 index 7（第 8 天）

var day: int = 1   # 1-based

func _init(day_: int = 1) -> void:
	day = day_

func advance() -> void:
	day += 1

func moon_phase_index() -> int:
	return (day - 1) % MOON_CYCLE_DAYS

func moon_phase_name() -> String:
	var idx := moon_phase_index()
	if idx == 0:
		return "新月"
	if idx == MOON_FULL_INDEX:
		return "满月"
	if idx == MOON_CYCLE_DAYS - 1:
		return "残月"
	return "月相%d(%s)" % [idx + 1, "渐盈" if idx < MOON_FULL_INDEX else "渐亏"]

func mana_regen() -> int:
	var idx := moon_phase_index()
	var dist := mini(idx, MOON_CYCLE_DAYS - idx)
	return round(dist / float(MOON_FULL_INDEX) * 6) if MOON_FULL_INDEX else 0

func time_of_day_index() -> int:
	var raw := (day - 1) / TIME_OF_DAY_DAYS_PER_STAGE
	return raw % TIME_OF_DAY_STAGES.size()

func time_of_day_name() -> String:
	return TIME_OF_DAY_STAGES[time_of_day_index()]

func describe() -> String:
	return "第 %d 天 · %s · %s(魔力恢复 +%d)" % [
		day, time_of_day_name(), moon_phase_name(), mana_regen()]
