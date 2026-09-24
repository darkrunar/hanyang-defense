extends SceneTree
## Core-loop ladder report (D-056): runs every playable stage's headless
## check and writes the numbers as JSON; prints the planned stages too.
##
##   godot --headless --path . --script res://game/tools/stage_report.gd [-- --out=<abs>.json --stage=N]
##
## Exit 1 when any stage check fails.

const StageLadder := preload("res://game/core/stage_ladder.gd")
const StageChecks := preload("res://game/tools/stage_checks.gd")


func _initialize() -> void:
    var out_path: String = ""
    var only: int = -1
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--out="):
            out_path = arg.substr("--out=".length())
        elif arg.begins_with("--stage="):
            only = StageLadder.parse(arg.substr("--stage=".length()))
    var rows: Array = []
    var all_ok: bool = true
    for st: Dictionary in StageLadder.STAGES:
        var id: int = int(st["id"])
        if only > 0 and id != only:
            continue
        var r: Dictionary = StageChecks.run(id)
        rows.append(r)
        all_ok = all_ok and bool(r["pass"])
        print("stage %d %-10s %-4s %s | %s" % [id, st["key"], "PASS" if r["pass"] else "FAIL", JSON.stringify(r["metrics"]), ", ".join(r["failed"])])
    for p: Dictionary in StageLadder.PLANNED:
        print("stage %d %-10s PLANNED %s — %s" % [p["id"], p["key"], p["wp"], p["title"]])
    var report: Dictionary = {"seed": StageLadder.config_for(1).get_int("seed"), "engine": Engine.get_version_info().string,
        "all_pass": all_ok, "stages": rows, "planned": StageLadder.PLANNED}
    if out_path != "":
        var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
        if f != null:
            f.store_string(JSON.stringify(report, "  "))
            f.close()
            print("written: %s" % out_path)
    quit(0 if all_ok else 1)
