class_name LazyTextureBinding
extends RefCounted

## 一份路径引用驱动多个显示节点；拥有者退出场景树时自动释放引用。
var _path: String = ""
var _targets: Array[CanvasItem] = []

func _init(owner: Node, targets: Array) -> void:
	_targets.assign(targets)
	owner.tree_exiting.connect(_release)

func show_path(path: String) -> void:
	if _path == path and not _targets.is_empty() \
			and is_instance_valid(_targets[0]) and _targets[0].get("texture") != null:
		return
	_release()
	var texture := LazyTexture.acquire(path)
	for target in _targets:
		if is_instance_valid(target):
			target.set("texture", texture)
	_path = path

func clear() -> void:
	_release()
	for target in _targets:
		if is_instance_valid(target):
			LazyTexture.clear(target)

func _release() -> void:
	if _path != "":
		LazyTexture.release(_path)
		_path = ""
