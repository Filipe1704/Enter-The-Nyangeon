"""隔离真实 ModManager.import_zip，验证失败回滚、路径冲突及已挂载包更新。"""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
import sys
from isolated_godot import REPO, prepare
from godot_check_output import unexpected_errors


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", str(REPO.parent / ".tools/godot/Godot_v4.7-stable_win64_console.exe")))
    parser.add_argument("--legacy", action="store_true", help="验证 HEAD 中旧导入实现能使回归失败")
    args = parser.parse_args()
    logs = REPO / ".godot/mod_install_checks"
    logs.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="etn-mod-install-") as directory:
        root = Path(directory)
        env = prepare(args.godot, root / "user", [])
        command = [args.godot, "--headless", "--path", str(REPO), "--script", "res://tests/mod_install_checks.gd"]
        if args.legacy:
            old = root / "old_mod_manager.gd"
            old.write_bytes(subprocess.check_output(["git", "show", "HEAD:script/mod_manager.gd"], cwd=REPO))
            command += ["--", "--legacy=" + old.as_posix()]
        result = subprocess.run(command, env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=30,
                                creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        text = result.stdout + result.stderr
        (logs / ("legacy.log" if args.legacy else "current.log")).write_text(text, encoding="utf-8")
        print(text)
        if result.returncode or unexpected_errors(text) or "MOD_INSTALL_RESULT failures=0" not in text:
            raise SystemExit(1)


if __name__ == "__main__":
    main()
