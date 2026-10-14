extends SceneTree

var failures := 0

func _initialize(): _run.call_deferred()

func check(ok: bool, message: String):
	if not ok:
		failures += 1
		print("FAIL: " + message)

func _run():
	var manager = load("res://script/mod_manager.gd").new()
	for user_order in [[], ["b", "a", "c", "d"]]:
		manager._mods = {
			"a": {"enabled": true, "mounted": false, "error": "", "manifest": {"conflicts": ["b"]}},
			"b": {"enabled": true, "mounted": false, "error": "", "manifest": {}},
			"c": {"enabled": true, "mounted": false, "error": "", "manifest": {"dependencies": ["b"]}},
			"d": {"enabled": true, "mounted": false, "error": "", "manifest": {"dependencies": ["c"]}}
		}
		manager._user_order = user_order
		var order: Array = manager._resolve_order()
		check(order == (["a"] if user_order.is_empty() else ["b", "c", "d"]), "冲突过滤后的直接及传递依赖闭包")
		for id in manager._mods:
			check(manager._mods[id].enabled, "失败不改写用户启用意图")
		if user_order.is_empty():
			check(not manager._mods.c.error.is_empty() and not manager._mods.d.error.is_empty(), "依赖者显示运行期错误")
	var experiment := OS.get_environment("ETN_LIFECYCLE_ROOT")
	check(not experiment.is_empty(), "实验根已设置")
	for id in ["nested", "root_link", "hidden"]:
		check(manager._delete_dir_recursive("user://mods/" + id), "删除自身安装目录：" + id)
	for id in ["nested", "root_link"]:
		check(FileAccess.file_exists(experiment.path_join(id + "/keep.txt")), "链接目标哨兵保留：" + id)
	check(not DirAccess.dir_exists_absolute("user://mods/hidden"), "隐藏文件不会令卸载永久失败")
	manager.free()
	print("MOD_LIFECYCLE_RESULT failures=", failures)
	quit(1 if failures else 0)
