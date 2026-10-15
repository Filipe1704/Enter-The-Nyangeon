extends RefCounted

## 只读解析 Godot PCK 目录表（当前 4.7 导出/PCKPacker 产物为 v4），供 ModManager
## 在挂载 replace_files 包前核对「它实际覆盖了哪些本体文件」。
##
## `list_paths()` 成功返回资源路径数组（**不含 `res://` 前缀**）；凡无法可靠校验的情形
## （非 PCK / 版本不支持 / 目录加密 / 越界损坏）一律返回 `null`，由调用方视为「跳过守卫」，
## 不做任何拦截——避免在取证失败时误伤正常包。
##
## v4 头布局（与 tests/export_boundary_helpers.py 的解析一致）：
##   magic@0 (u32 "GDPC") / version@4 / ver_major@8 / ver_minor@12 / ver_patch@16
##   flags@20 (u32) / file_base@24 (i64) / dir_offset@32 (i64) / reserved… / 目录 @dir_offset
##   目录：count(u32) 然后每条 [ path_len(u32) + path(path_len, 4 字节对齐) + 36 字节 ]
##         其中 36 = offset(8) + size(8) + md5(16) + flags(4)。

const MAGIC := 0x43504447  # "GDPC"
const SUPPORTED_VERSION := 4
const FLAG_DIR_ENCRYPTED := 1  # 1 << 0
const HEADER_SIZE := 40
const ENTRY_TAIL := 36  # offset(8)+size(8)+md5(16)+flags(4)
const MAX_ENTRIES := 100000  # 防越界/损坏导致的超长循环


# 返回 PackedStringArray（路径无 res:// 前缀）；无法校验返回 null。
func list_paths(pck_path: String):
	var f := FileAccess.open(pck_path, FileAccess.READ)
	if f == null:
		return null
	var total := f.get_length()
	if total < HEADER_SIZE:
		return null
	if f.get_32() != MAGIC:
		return null
	if f.get_32() != SUPPORTED_VERSION:
		return null
	f.seek(20)
	var flags := f.get_32()
	if flags & FLAG_DIR_ENCRYPTED:
		return null
	f.seek(32)
	var dir_offset := f.get_64()
	if dir_offset <= 0 or dir_offset + 4 > total:
		return null
	f.seek(dir_offset)
	var count := f.get_32()
	if count <= 0 or count > MAX_ENTRIES:
		return null
	var out := PackedStringArray()
	for i in count:
		if f.get_position() + 4 > total:
			return null
		var path_len := f.get_32()
		if path_len <= 0 or f.get_position() + path_len + ENTRY_TAIL > total:
			return null
		var raw := f.get_buffer(path_len)
		var path := raw.get_string_from_utf8()
		while path.length() > 0 and path.ends_with("\u0000"):
			path = path.substr(0, path.length() - 1)
		out.append(path)
		f.seek(f.get_position() + ENTRY_TAIL)
	return out
