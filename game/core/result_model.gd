extends RefCounted
## WP-004 §4 / D-041: the result summary, built ONCE from the battle's real
## ledgers at the moment the run ended and never touched again. Every field
## comes from RunState / EnemySim / WaveDirector counters, not from HUD
## values or HP back-calculation.

const Battle := preload("res://game/core/battle.gd")
const Placement := preload("res://game/core/placement.gd")
const TestMap := preload("res://game/maps/hanyang_test_map.gd")

const RECOVERY_NONE: String = "회수 없음"
const RECOVERY_WAITING: String = "회수 후 미배치"
const RECOVERY_PLACED: String = "재배치 완료"
const OUTER_HELD: String = "외곽 유지"


## mm:ss with the seconds floored (WP-004 §4).
static func format_mmss(seconds: float) -> String:
    var total: int = int(floor(maxf(seconds, 0.0)))
    return "%02d:%02d" % [int(total / 60), total % 60]


## Build the frozen model. The battle must have ended (run.ended()); if it has
## not, `valid` is false and the caller must not show a result.
static func build(b: Battle) -> Dictionary:
    var rs = b.run
    var ws: Dictionary = b.waves.snapshot()
    var play_seconds: float = rs.end_sim_time if rs.end_sim_time >= 0.0 else b.sim_time
    var collapsed: bool = rs.collapse_count > 0
    var recovery: String = RECOVERY_NONE
    var anchor: Variant = null
    var world: Variant = null
    if collapsed:
        if rs.recovery_placed:
            recovery = RECOVERY_PLACED
            anchor = [rs.recovery_anchor.x, rs.recovery_anchor.y]
            var st: Placement.Structure = b.placement.get_any(rs.recovery_target_id)
            if st != null:
                world = [st.center.x, st.center.y]
        else:
            recovery = RECOVERY_WAITING
    var wave_index: int = int(ws["wave_index"])
    return {
        "valid": rs.ended(),
        "outcome": rs.run_name(),                       # WON / LOST (RunState, lose priority kept)
        "won": rs.run == 1,
        "run_id": rs.run_id,
        "end_tick": rs.end_tick,
        "play_time_seconds": play_seconds,              # battle simulation time (pause excluded by construction)
        "play_time_text": format_mmss(play_seconds),
        "wave_reached": wave_index + 1,                 # 1-based display number
        "wave_name": str(ws["wave_name"]),
        "waves_total": (ws["spawned_by_wave"] as Array).size(),
        "kills": b.sim.killed_total,                    # arrivals are NOT kills
        "outer_arrivals": rs.outer_arrivals,            # real arrivals, not HP back-calculation
        "core_arrivals": rs.core_arrivals,
        "outer_collapsed": collapsed,
        "collapse_time_seconds": rs.collapse_sim_time,
        "outer_result": (("외곽 붕괴 · " + format_mmss(rs.collapse_sim_time)) if collapsed else OUTER_HELD),
        "recovery": recovery,
        "recovery_anchor": anchor,                      # [cx, cy] or null
        "recovery_world": world,                        # [x, y] centre or null
        "core_hp": rs.core_hp,
        "core_hp_max": rs.core_hp_max,
        "outer_hp": rs.outer_hp,
        "outer_hp_max": rs.outer_hp_max,
        "spawned_total": b.sim.spawned_total,
        "leaked_total": b.sim.leaked_total,
        "seed": b.config.get_int("seed"),
        "forced_hp_writes": rs.forced_hp_writes,        # > 0 only in verification scenarios
        # WP-008: the supply ledger (all zero / disabled in the classic run)
        "play_mode": b.play_mode,
        "economy": b.economy.snapshot(),
        "frozen": true,
    }


## Lines for the result panel, in display order.
static func lines(m: Dictionary) -> Array:
    var pos: String = "—"
    if m["recovery_anchor"] != null:
        var a: Array = m["recovery_anchor"]
        pos = "(%d, %d)" % [int(a[0]), int(a[1])]
    return [
        ["결과", "승리" if m["won"] else "패배"],
        ["플레이 시간", m["play_time_text"]],
        ["도달 웨이브", "%d / %d (%s)" % [int(m["wave_reached"]), int(m["waves_total"]), m["wave_name"]]],
        ["처치 수", str(int(m["kills"]))],
        ["거점 도달 수", "외곽 %d · 핵심 %d" % [int(m["outer_arrivals"]), int(m["core_arrivals"])]],
        ["외곽 방어 결과", m["outer_result"]],
        ["회수 화차", m["recovery"]],
        ["재배치 위치", pos],
        ["핵심 잔여 HP", "%d / %d" % [int(m["core_hp"]), int(m["core_hp_max"])]],
    ]


## WP-008 rows appended to the result panel in build mode only.
static func economy_lines(m: Dictionary) -> Array:
    if str(m.get("play_mode", "classic")) != "build":
        return []
    var e: Dictionary = m.get("economy", {})
    var by: Dictionary = e.get("purchases_by_kind", {})
    var parts: PackedStringArray = PackedStringArray()
    for kind: int in range(Placement.KIND_NAMES.size()):
        var n: int = int(by.get(Placement.KIND_NAMES[kind], 0))
        if n > 0:
            parts.append("%s %d" % [Placement.kind_label(kind), n])
    var builds: String = ("%s (총 %d)" % [" · ".join(parts), int(e.get("purchase_count", 0))]) if not parts.is_empty() else "없음"
    var inj: String = ("  [벤치마크 주입 %d]" % int(e.get("injected", 0))) if int(e.get("injected", 0)) > 0 else ""
    return [
        ["물자", "시작 %d + 처치 %d + 웨이브 %d − 소비 %d = 잔액 %d%s" % [int(e.get("start_supply", 0)), int(e.get("earned_kills", 0)),
            int(e.get("earned_waves", 0)), int(e.get("spent", 0)), int(e.get("supply", 0)), inj]],
        ["건설", builds],
    ]
