"""本体 PCK 目录与独立 Mod 脚本可见性验证，不依赖本地审计工具状态。"""
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
from isolated_godot import REPO, environment, prepare
from godot_check_output import unexpected_errors


def export_base(args):
    protected = [REPO / "project.godot", *REPO.glob("*.translation")]
    original = {p: p.read_bytes() for p in protected}
    with tempfile.TemporaryDirectory(prefix="etn-audit-export-") as temporary:
        env = prepare(args.godot, Path(temporary) / "user", [])
        result = subprocess.run([args.godot, "--headless", "--path", str(REPO), "--export-pack", "Windows Desktop", str(args.output / "windows.pck")], env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=150, creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        log = result.stdout + result.stderr
        (args.output / "export.log").write_text(log, encoding="utf-8")
        print("EXPORT_EXIT=" + str(result.returncode))
        print("PROTECTED_FILES_CHANGED=" + json.dumps([str(p) for p, data in original.items() if p.read_bytes() != data]))
        print("EXPORT_ERRORS=" + json.dumps([s for s in log.splitlines() if "ERROR:" in s or "SCRIPT ERROR" in s]))
        changed = [str(p) for p, data in original.items() if p.read_bytes() != data]
        if result.returncode or unexpected_errors(log) or changed:
            raise RuntimeError("导出未通过严格检查：" + log)
    pck = args.output / "windows.pck"
    data = pck.read_bytes()
    assert data[:4] == b"GDPC" and struct.unpack_from("<I", data, 4)[0] == 4
    offset = struct.unpack_from("<Q", data, 32)[0]
    count = struct.unpack_from("<I", data, offset)[0]
    offset += 4
    paths = []
    for _ in range(count):
        size = struct.unpack_from("<I", data, offset)[0]
        offset += 4
        paths.append(data[offset:offset+size].rstrip(b"\0").decode())
        offset += size + 36
    mod_paths = [p for p in paths if p.startswith("mods/")]
    (args.output / "export_paths.json").write_text(json.dumps(mod_paths, indent=2), encoding="utf-8")
    print("PCK_MOD_PATHS=" + json.dumps(mod_paths))
    return pck


def export_shadow(args):
    pck = args.pck.resolve() if args.pck else export_base(args)
    with tempfile.TemporaryDirectory(prefix="etn-audit-shadow-") as temporary:
        task = Path(temporary)
        (task / "project.godot").write_text("config_version=5\n", encoding="utf-8")
        (task / "new.gd").write_text('extends RefCounted\nconst AUDIT_MARKER := "new_mod_build"\n', encoding="utf-8")
        source = """extends SceneTree
func _initialize():
    var p = PCKPacker.new()
    p.pck_start(%s)
    p.add_file("res://mods/etn_export_probe/entry.gd", %s)
    p.flush()
    print("MOUNT_BASE=",ProjectSettings.load_resource_pack(%s,true))
    print("MOUNT_MOD=",ProjectSettings.load_resource_pack(%s,false))
    var loaded = load("res://mods/etn_export_probe/entry.gd")
    print("ACTUAL_CONSTANTS=",loaded.get_script_constant_map())
    print("NEW_MOD_MARKER_VISIBLE=",loaded.get_script_constant_map().has("AUDIT_MARKER"))
    quit()
""" % tuple(json.dumps(p.as_posix()) for p in (task / "override.pck", task / "new.gd", pck, task / "override.pck"))
        (task / "probe.gd").write_text(source, encoding="utf-8")
        result = subprocess.run([args.godot, "--headless", "--path", str(task), "--script", "res://probe.gd"], env=environment(task / "user"), capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=30, creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        text = result.stdout + result.stderr
        (args.output / "export_shadow.log").write_text(text, encoding="utf-8")
        print(text)
        return result.returncode
