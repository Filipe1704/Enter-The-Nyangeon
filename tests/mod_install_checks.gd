extends SceneTree

class FailCommit extends "res://script/mod_installer.gd":
	func _rename(source: String, destination: String) -> Error:
		if source.get_file().begins_with(".import_"):
			return ERR_CANT_CREATE
		return super._rename(source, destination)

var failures := 0
var manager
var old_manager: Node

func check(ok: bool, message: String):
	if not ok:
		failures += 1
		print("FAIL: " + message)

func _initialize(): _run.call_deferred()

func make_pack(value: String) -> PackedByteArray:
	var file := FileAccess.open("user://marker.txt", FileAccess.WRITE)
	file.store_string(value)
	file.close()
	var packer := PCKPacker.new()
	check(packer.pck_start("user://test.pck") == OK, "创建 PCK")
	check(packer.add_file("res://mods/audit_mod/marker.txt", "user://marker.txt") == OK, "PCK 加入资源")
	check(packer.flush() == OK, "PCK 写入完成")
	return FileAccess.get_file_as_bytes("user://test.pck")

func make_zip(entries: Dictionary) -> String:
	var path := "user://install.zip"
	var zip := ZIPPacker.new()
	check(zip.open(path) == OK, "创建 ZIP")
	for name in entries:
		check(zip.start_file(name) == OK, "创建 ZIP 条目")
		var data = entries[name]
		zip.write_file(data.to_utf8_buffer() if data is String else data)
		zip.close_file()
	zip.close()
	return path

func _run():
	manager = root.get_node("ModManager")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--legacy="):
			old_manager = load(arg.substr(9)).new()
			manager = old_manager
	var manifest := JSON.stringify({"id": "audit_mod"})
	var first := make_pack("first")
	var second := make_pack("second")
	var path := make_zip({"mod.json": manifest, "audit_mod.pck": first, "assets/": "", "assets/stale.txt": "old", ".hidden": "old"})
	check(manager.import_zip(path).ok, "含显式目录的正常安装成功")
	var installed := "user://mods/audit_mod/audit_mod.pck"
	check(FileAccess.get_file_as_bytes(installed) == first, "安装 PCK 字节完整")
	path = make_zip({"mod.json": manifest, "audit_mod.pck/": "", "audit_mod.pck": second})
	check(not manager.import_zip(path).ok, "拒绝 PCK 同路径目录/文件冲突")
	check(FileAccess.file_exists(installed) and FileAccess.get_file_as_bytes(installed) == first, "冲突包失败后保留旧 PCK")
	for entries in [
		{"mod.json": manifest, "audit_mod.pck": second, "a": "file", "a/b": "child"},
		{"mod.json": manifest, "audit_mod.pck": second, "a/b": "child", "a": "file"},
		{"mod.json": manifest, "audit_mod.pck": second, "../outside": "bad"},
		{"mod.json": manifest, "audit_mod.pck": second, "a//b": "one", "a/b": "two"},
		{"mod.json": manifest}]:
		path = make_zip(entries)
		check(not manager.import_zip(path).ok, "拒绝不完整或路径冲突归档")
		check(FileAccess.file_exists(installed) and FileAccess.get_file_as_bytes(installed) == first, "失败归档不改变旧安装")
	path = make_zip({"mod.json": manifest, "audit_mod.pck": second})
	if old_manager == null:
		check(not FailCommit.new().install(path, "user://mods", 2000, 1024 * 1024).ok, "替换失败明确返回失败")
		check(FileAccess.get_file_as_bytes(installed) == first, "替换失败回滚到原安装")
		check(not preload("res://script/mod_installer.gd").new().install(path, "user://mods", 2000, 32).ok, "体积超限明确失败")
		check(FileAccess.get_file_as_bytes(installed) == first, "体积超限保留原安装")
	check(manager.import_zip(path).ok, "正常重装成功")
	check(FileAccess.get_file_as_bytes(installed) == second, "重装采用新 PCK")
	check(not FileAccess.file_exists("user://mods/audit_mod/assets/stale.txt"), "正常重装不残留旧文件")
	var mods_dir := DirAccess.open("user://mods")
	mods_dir.include_hidden = true
	for child in mods_dir.get_directories():
		check(not child.begins_with(".import_") and not child.begins_with(".rollback_"), "成功/回滚后的隐藏暂存目录均已清理")
	check(ProjectSettings.load_resource_pack(installed, false), "安装 PCK 可实际挂载")
	path = make_zip({"mod.json": manifest, "audit_mod.pck": first})
	check(manager.import_zip(path).ok, "已挂载 PCK 的安装仍可重装")
	check(FileAccess.get_file_as_bytes(installed) == first, "已挂载包重装成功落盘")
	if old_manager != null: old_manager.free()
	print("MOD_INSTALL_RESULT failures=%d" % failures)
	quit(1 if failures else 0)
