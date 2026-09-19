extends SceneTree
const H=preload("res://tests/test_play_flow.gd")
var rows=[]
func _initialize(): call_deferred("run")
func key(k,down): root.push_input(H._key_event(k,down))
func mouse(pos,down): root.push_input(H._lmb_event(down,pos),true)
func run():
    for mode in ["enter","mouse"]:
        var s=H._collapsed_at_b(self)
        key(KEY_ESCAPE,true)
        H._frame(s)
        key(KEY_ESCAPE,false)
        await process_frame
        await process_frame
        var b=s.menu.button("pause_continue")
        b.grab_focus()
        var a0=s.battle.commands_accepted
        var center=b.get_global_rect().get_center()
        if mode=="enter": key(KEY_ENTER,true)
        else: mouse(center,true)
        H._frame(s)
        var press_state=s.flow.state_name()
        if mode=="enter": key(KEY_ENTER,false)
        else: mouse(center,false)
        H._frame(s)
        await process_frame
        var closed=s.flow.state_name()
        var closing_delta=s.battle.commands_accepted-a0
        mouse(Vector2(900,280),true)
        var fresh_delta=s.battle.commands_accepted-a0
        mouse(Vector2(900,280),false)
        rows.append({"mode":mode,"button_center":[center.x,center.y],"press_state":press_state,"release_state":closed,"closing_delta":closing_delta,"new_press_delta":fresh_delta,"pass":closed=="PLAYING" and closing_delta==0 and fresh_delta==1})
        H._drop(s)
    print(JSON.stringify(rows))
    var f=FileAccess.open("res://results/evidence/wp-004/gpt-review/2026-09-20/gui_review.json",FileAccess.WRITE)
    f.store_string(JSON.stringify(rows,"  ")+"\n")
    quit(0 if rows.all(func(r):return r.pass) else 1)
