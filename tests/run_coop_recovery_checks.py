"""真实源码 PCK、多进程 LAN/Relay 检查阶段准入、三端恢复、升级屏障、金币和取消。"""
import argparse
from pathlib import Path
import subprocess
import tempfile
import uuid
import os
import sys
import socket
import time

from isolated_godot import BASE, REPO, free_port, prepare, run
from godot_check_output import unexpected_errors


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=str(REPO.parent / ".tools/godot/Godot_v4.7-stable_win64_console.exe"))
    parser.add_argument("--pack", type=Path, help="仅用于验证回归能捕获旧构建；默认每次从当前源码打包")
    parser.add_argument("--log-dir", type=Path, default=REPO / ".godot/coop_recovery_checks")
    parser.add_argument("--cases", nargs="+", default=["relay_queue", "simultaneous_leave", "cancel_lobby", "cancel_battle", "cancel_new_session", "cancel_client_scene", "late_select", "late_ready", "rejoin3", "relay_rejoin3", "upgrade", "coins", "damage"])
    args = parser.parse_args()
    logs = args.log_dir.resolve()
    logs.mkdir(parents=True, exist_ok=True)
    failures = []
    with tempfile.TemporaryDirectory(prefix="etn-coop-recovery-", ignore_cleanup_errors=True) as directory:
        root = Path(directory)
        pack = args.pack.resolve() if args.pack else root / "etn_coop.pck"
        if not args.pack:
            code, text = run(["pwsh", "-NoProfile", "-File", str(REPO / "mod_sdk/pack_mod_source.ps1"), "-Source", str(BASE),
                              "-ModId", "etn_coop", "-Godot", args.godot, "-Output", str(pack), "-BuildId", uuid.uuid4().hex],
                             os.environ.copy(), logs / "pack.log", 60)
            if code or not pack.is_file():
                raise RuntimeError(text)
        for case in args.cases:
            shared = root / case
            shared.mkdir()
            port = free_port()
            roles = ("host",) if case == "relay_queue" or (case.startswith("cancel") and case != "cancel_client_scene") else (("host", "client", "survivor") if case in ("rejoin3", "relay_rejoin3", "simultaneous_leave") else ("host", "client"))
            processes = []
            relay_process = None
            relay_log = None
            try:
                relay_url = ""
                if case == "relay_rejoin3":
                    with socket.socket() as listener:
                        listener.bind(("127.0.0.1", 0))
                        relay_port = listener.getsockname()[1]
                    relay_env = os.environ.copy()
                    relay_env.update(PORT=str(relay_port), RELAY_BIND_ADDRESS="127.0.0.1")
                    relay_log = (logs / "relay_rejoin3_server.log").open("w", encoding="utf-8")
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
                    command = [args.godot, "--headless", "--path", str(REPO), "--script", "res://tests/coop_recovery_checks.gd", "--",
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
                    marker = f"COOP_RECOVERY mode={case} role={role} failures=0"
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
