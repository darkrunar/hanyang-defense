extends SceneTree
## Fast focused runner for stage-map editor contracts.

const TestFramework := preload("res://tests/test_framework.gd")
const StageMapTests := preload("res://tests/test_stage_map_editor.gd")


func _initialize() -> void:
    var tests: TestFramework = TestFramework.new()
    tests.suite("Stage map editor focused checks")
    StageMapTests.new().run(tests)
    print(tests.summary())
    quit(1 if tests.failed > 0 else 0)
