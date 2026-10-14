"""Godot 回归共用的用户目录隔离、源码包安装与进程工具。"""
import json
import os
from pathlib import Path
import socket
import subprocess

REPO = Path(__file__).resolve().parents[1]
BASE = REPO / "mod_sdk/coop_mod/mods/etn_coop"


def environment(root):
    env = os.environ.copy()
    for key in ("APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME"):
        env[key] = str(root / key)
        Path(env[key]).mkdir(parents=True, exist_ok=True)
    return env


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def run(command, env, log, timeout=50):
    result = subprocess.run(command, env=env, capture_output=True, text=True,
                            encoding="utf-8", errors="replace", timeout=timeout,
                            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
    text = result.stdout + result.stderr
    log.write_text(text, encoding="utf-8")
    return result.returncode, text


def prepare(godot, root, packs):
    env = environment(root)
    probe = root / "probe"
    probe.mkdir()
    application = (REPO / "project.godot").read_text(encoding="utf-8-sig").split("[application]", 1)[1].split("\n[", 1)[0]
    (probe / "project.godot").write_text("config_version=5\n[application]" + application, encoding="utf-8")
    (probe / "probe.gd").write_text('extends SceneTree\nfunc _initialize():\n\tprint("USER_DIR=" + OS.get_user_data_dir())\n\tquit()\n', encoding="utf-8")
    result = subprocess.run([godot, "--headless", "--path", str(probe), "--script", "res://probe.gd"], env=env,
                            capture_output=True, text=True, encoding="utf-8", timeout=20)
    path = next((line.removeprefix("USER_DIR=") for line in result.stdout.splitlines() if line.startswith("USER_DIR=")), "")
    if result.returncode or not path or not Path(path).resolve().is_relative_to(root.resolve()):
        raise RuntimeError("真实 user:// 隔离校验失败")
    for source, pck in packs:
        manifest = json.loads((source / "mod.json").read_text(encoding="utf-8-sig"))
        dest = Path(path) / "mods" / manifest["id"]
        dest.mkdir(parents=True)
        if source == BASE:
            # 隔离测试覆盖编辑器镜像，玩家 manifest 保持原值。
            manifest["replace_files"] = True
        (dest / "mod.json").write_text(json.dumps(manifest), encoding="utf-8")
        (dest / (manifest["id"] + ".pck")).write_bytes(pck.read_bytes())
    return env
