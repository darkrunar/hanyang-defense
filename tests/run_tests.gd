extends SceneTree
## Headless WP-001 test suite.
##
##   godot --headless --path . --script res://tests/run_tests.gd
##
## Exits 0 when every check passes, 1 otherwise. Optional:
##   --report=<path>   also write the full transcript to a file

const TestFramework := preload("res://tests/test_framework.gd")

const SUITES: Array = [
    ["path + placement (AC-02, AC-03)", "res://tests/test_path_and_placement.gd"],
    ["density + hwacha (AC-04, AC-05)", "res://tests/test_density_and_hwacha.gd"],
    ["flow + determinism (AC-01, AC-06)", "res://tests/test_flow_and_determinism.gd"],
    ["WP-002 bongsu network (AC-01..05, AC-07)", "res://tests/test_bongsu_network.gd"],
]


func _initialize() -> void:
    var t: TestFramework = TestFramework.new()
    var started: int = Time.get_ticks_msec()
    print("Hanyang Defense WP-001 test suite")
    print("Godot %s" % Engine.get_version_info().string)

    for entry: Array in SUITES:
        t.suite(entry[0])
        var script: GDScript = load(entry[1])
        var suite: RefCounted = script.new()
        suite.run(t)

    var elapsed: float = float(Time.get_ticks_msec() - started) / 1000.0
    var summary: String = t.summary()
    t.lines.append("elapsed %.1f s" % elapsed)
    print("elapsed %.1f s" % elapsed)

    var report_path: String = ""
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--report="):
            report_path = arg.substr("--report=".length())
    if report_path != "":
        var f: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
        if f != null:
            f.store_string("\n".join(t.lines) + "\n")
            f.close()
            print("report written: %s" % report_path)
        else:
            printerr("could not write report: %s" % report_path)

    print(summary)
    quit(1 if t.failed > 0 else 0)
