extends RefCounted
## Minimal assert-based test harness for the headless WP-001 suite.

var _suite: String = ""
var _case: String = ""
var passed: int = 0
var failed: int = 0
var failures: Array[String] = []
var lines: Array[String] = []


func suite(name: String) -> void:
    _suite = name
    _emit("")
    _emit("== %s ==" % name)


func case(name: String) -> void:
    _case = name
    _emit("  -- %s" % name)


func _emit(s: String) -> void:
    lines.append(s)
    print(s)


func _pass(msg: String) -> void:
    passed += 1
    _emit("     PASS  %s" % msg)


func _fail(msg: String) -> void:
    failed += 1
    var where: String = "%s / %s" % [_suite, _case]
    failures.append("%s: %s" % [where, msg])
    _emit("     FAIL  %s" % msg)


func check(condition: bool, msg: String) -> bool:
    if condition:
        _pass(msg)
    else:
        _fail(msg)
    return condition


func eq(actual: Variant, expected: Variant, msg: String) -> bool:
    if actual == expected:
        _pass("%s (= %s)" % [msg, str(expected)])
        return true
    _fail("%s: expected %s, got %s" % [msg, str(expected), str(actual)])
    return false


func ne(actual: Variant, unexpected: Variant, msg: String) -> bool:
    if actual != unexpected:
        _pass("%s (%s != %s)" % [msg, str(actual), str(unexpected)])
        return true
    _fail("%s: expected anything but %s" % [msg, str(unexpected)])
    return false


func gt(actual: float, threshold: float, msg: String) -> bool:
    if actual > threshold:
        _pass("%s (%s > %s)" % [msg, str(actual), str(threshold)])
        return true
    _fail("%s: expected > %s, got %s" % [msg, str(threshold), str(actual)])
    return false


func ge(actual: float, threshold: float, msg: String) -> bool:
    if actual >= threshold:
        _pass("%s (%s >= %s)" % [msg, str(actual), str(threshold)])
        return true
    _fail("%s: expected >= %s, got %s" % [msg, str(threshold), str(actual)])
    return false


func note(msg: String) -> void:
    _emit("     ....  %s" % msg)


func summary() -> String:
    var s: String = "TOTAL passed=%d failed=%d" % [passed, failed]
    _emit("")
    _emit(s)
    for f: String in failures:
        _emit("  FAILED: %s" % f)
    return s
