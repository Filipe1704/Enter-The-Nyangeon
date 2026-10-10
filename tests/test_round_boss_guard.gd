@tool
extends McpTestSuite

## 回归：boss 回合结束守卫 + 拾取物视觉副本 inert。
## 背景：联机无尽模式第 15 关 boss 后不断跳关——coop 广播的 pyroxenes 纯视觉副本
## 仍保留 10s autostart Timer 并自动 add_pyroxenes → on_pyroxenes_gain → host 补发
## pyroxenes_pick_up → round_timer.end_boss_round 在非 boss 回合误触发 round_end。
## 不变式：
##  - round_timer.end_boss_round 仅在 boss_round_pending_end 为真时才结束本回合。
##  - round_end 后标志清零，避免泄漏到后续非 boss 回合。
##  - pyroxenes 的 remote_visual 视觉副本立即 inert（is_pick、Timer 停用、不广播）。

const ROUND_TIMER_SCRIPT := "res://ui/round_timer.gd"
const PYROXENES_SCENE := "res://scenes/item/pyroxenes.tscn"


func suite_name() -> String:
	return "round_boss_guard"


func _new_round_timer() -> Node:
	var rt = ResourceLoader.load(ROUND_TIMER_SCRIPT, "", ResourceLoader.CACHE_MODE_IGNORE).new()
	track(rt)
	return rt


# 非 boss 回合：pending 为假时 end_boss_round 必须直接返回（不进入 await、不结束回合）。
func test_end_boss_round_noop_when_not_pending() -> void:
	var rt := _new_round_timer()
	rt.boss_round_pending_end = false
	rt.end_boss_round()
	assert_false(rt.boss_round_pending_end, "非 boss 回合调用后标志应保持 false")


# 消费语义：pending 为真时被消费（置假）。
func test_clear_pending_resets_flag() -> void:
	var rt := _new_round_timer()
	rt.boss_round_pending_end = true
	rt._clear_boss_round_pending_end()
	assert_false(rt.boss_round_pending_end, "round_end 后标志应清零")


func test_default_pending_is_false() -> void:
	var rt := _new_round_timer()
	assert_false(rt.boss_round_pending_end, "默认应为 false，避免泄露")


# 视觉副本：设 remote_visual 后 _ready 立即 inert。
func test_pyroxenes_remote_visual_inert() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		skip("无 SceneTree.root")
		return
	var px: Node = load(PYROXENES_SCENE).instantiate()
	track(px)
	px.set_meta("remote_visual", true)
	tree.root.add_child(px)
	assert_true(px.get("is_pick") == true, "remote_visual 青辉石应立即 is_pick")
	var tmr := px.get_node_or_null("Timer") as Timer
	assert_true(tmr != null, "应存在 Timer")
	if tmr != null:
		assert_true(tmr.is_stopped(), "remote_visual Timer 应停止")
		assert_false(tmr.autostart, "remote_visual Timer autostart 应关闭")
