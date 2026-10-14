"""从当前官方 Mod 源码打包，在隔离 user:// 中检查 LAN/Relay 双端道具显示或菜刀伤害一致性。"""
import argparse
from pathlib import Path
import subprocess
import tempfile
import os
import sys
import socket
import time

import json
import re
import shutil

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
    # 主线会直接读取存档；沿用 UI 回归的空 Resource，避免首次启动的缺档日志。
    (probe / "probe.gd").write_text(
        'extends SceneTree\nfunc _initialize():\n\tquit(ResourceSaver.save(Resource.new(), '
        + json.dumps(str(Path(path) / "PlayerData.res")) + '))\n', encoding="utf-8")
    subprocess.run([godot, "--headless", "--path", str(probe), "--script", "res://probe.gd"],
                   env=env, capture_output=True, text=True, encoding="utf-8", timeout=20, check=True)
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


ANSI = re.compile(r"\x1b\[[0-9;]*m")
EXIT_RESOURCE_COUNT = re.compile(r"ERROR: \d+ resources? still in use at exit \(run with --verbose for details\)\.")
# 主线保留本地编辑器 autoload，源码 checkout 可能没有该插件；不修改 project.godot。
MISSING_EDITOR_HELPER = {
    "ERROR: Attempt to open script 'res://addons/godot_ai/runtime/game_helper.gd' resulted in error 'File not found'.",
    "ERROR: Failed loading resource: res://addons/godot_ai/runtime/game_helper.gd.",
    "ERROR: Failed to instantiate an autoload, can't load from path: res://addons/godot_ai/runtime/game_helper.gd.",
}


def unexpected_errors(output):
    errors = []
    for raw in output.splitlines():
        line = ANSI.sub("", raw).strip()
        missing_helper = not (REPO / "addons/godot_ai/runtime/game_helper.gd").is_file() and line in MISSING_EDITOR_HELPER
        if ("SCRIPT ERROR:" in line or line.startswith("ERROR:")) and not EXIT_RESOURCE_COUNT.fullmatch(line) and not missing_helper:
            errors.append(line)
    return errors



def main():
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=str(REPO.parent / ".tools/godot/Godot_v4.7-stable_win64_console.exe"))
    parser.add_argument("--pack", type=Path, help="仅用于验证回归能捕获旧构建；默认每次从当前源码打包")
    parser.add_argument("--damage", action="store_true", help="检查客机菜刀同次命中的双端伤害数字与权威扣血")
    parser.add_argument("--log-dir", type=Path, default=REPO / ".godot/coop_item_visual_checks")
    parser.add_argument("--cases", nargs="+", choices=["items", "relay_items"], default=["items", "relay_items"])
    args = parser.parse_args()
    logs = args.log_dir.resolve()
    logs.mkdir(parents=True, exist_ok=True)
    failures = []
    with tempfile.TemporaryDirectory(prefix="etn-coop-items-", ignore_cleanup_errors=True) as directory:
        root = Path(directory)
        pack = args.pack.resolve() if args.pack else root / "etn_coop.pck"
        if not args.pack:
            pack_project = root / "pack_project"
            pack_project.mkdir()
            (pack_project / "project.godot").write_text("config_version=5\n", encoding="utf-8")
            shutil.copy2(REPO / "mod_sdk/pack_mod.gd", pack_project / "pack_mod.gd")
            code, text = run([args.godot, "--headless", "--path", str(pack_project), "--script", "res://pack_mod.gd", "--",
                              f"--mod-source={BASE.as_posix()}", f"--out={pack.as_posix()}", "--mod-id=etn_coop"],
                             environment(root / "pack_user"), logs / "pack.log", 60)
            if code or not pack.is_file():
                raise RuntimeError(text)
        for case in args.cases:
            shared = root / case
            shared.mkdir()
            port = free_port()
            roles = ("host", "client")
            processes = []
            relay_process = None
            relay_log = None
            try:
                relay_url = ""
                if case == "relay_items":
                    with socket.socket() as listener:
                        listener.bind(("127.0.0.1", 0))
                        relay_port = listener.getsockname()[1]
                    relay_env = os.environ.copy()
                    relay_env.update(PORT=str(relay_port), RELAY_BIND_ADDRESS="127.0.0.1")
                    relay_log = (logs / f"{case}_server.log").open("w", encoding="utf-8")
                    relay_process = subprocess.Popen([sys.executable, str(REPO / "mod_sdk/coop_mod/server/relay_server.py")], env=relay_env,
                                                      stdout=relay_log, stderr=subprocess.STDOUT,
                                                      creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
                    deadline = time.monotonic() + 5
                    while True:
                        try:
                            with socket.create_connection(("127.0.0.1", relay_port), timeout=0.1):
                                break
                        except OSError:
                            if relay_process.poll() is not None or time.monotonic() >= deadline:
                                raise RuntimeError("本地中继未启动")
                            time.sleep(0.02)
                    relay_url = f"ws://127.0.0.1:{relay_port}"
                for role in roles:
                    env = prepare(args.godot, shared / role, [(BASE, pack)])
                    log = logs / f"{case}_{role}.log"
                    handle = log.open("w", encoding="utf-8")
                    script = "coop_knife_damage_checks.gd" if args.damage else "coop_item_visual_checks.gd"
                    command = [args.godot, "--headless", "--path", str(REPO), "--script", "res://tests/" + script, "--",
                               f"--role={role}", f"--mode={case}", f"--directory={shared.as_posix()}", f"--port={port}"]
                    if relay_url:
                        command.append("--relay-url=" + relay_url)
                    process = subprocess.Popen(command, env=env, stdout=handle, stderr=subprocess.STDOUT,
                                               creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
                    processes.append((process, handle, log, role))
                for process, handle, log, role in processes:
                    process.wait(timeout=65)
                    handle.flush()
                    text = log.read_text(encoding="utf-8")
                    marker = f"COOP_ITEMS mode={case} role={role} failures=0"
                    if process.returncode or unexpected_errors(text) or marker not in text or "FAIL:" in text:
                        failures.append(case + "/" + role)
                        print(case + "/" + role + ": FAIL\n" + "\n".join(line for line in text.splitlines() if "FAIL:" in line or "ERROR:" in line), flush=True)
                if not any(f.startswith(case + "/") for f in failures):
                    print(case + ": PASS", flush=True)
            finally:
                for process, handle, _, _ in processes:
                    if process.poll() is None:
                        process.terminate()
                        process.wait(timeout=10)
                    handle.close()
                if relay_process is not None:
                    relay_process.terminate()
                    relay_process.wait(timeout=10)
                if relay_log is not None:
                    relay_log.close()
    if failures:
        raise SystemExit("失败场景：" + ", ".join(failures))


if __name__ == "__main__":
    main()
