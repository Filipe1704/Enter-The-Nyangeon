"""隔离验证升级刷新与联机外推数学不变量。"""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from isolated_godot import REPO, prepare
from godot_check_output import unexpected_errors

def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=str(REPO.parent / ".tools/godot/Godot_v4.7-stable_win64_console.exe"))
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="etn-upgrade-snapshot-") as directory:
        env = prepare(args.godot, Path(directory) / "user", [])
        result = subprocess.run([args.godot, "--headless", "--path", str(REPO), "--script", "res://tests/upgrade_snapshot_checks.gd"], env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=30, creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        text = result.stdout + result.stderr
        logs = REPO / ".godot/upgrade_snapshot_checks"
        logs.mkdir(parents=True, exist_ok=True)
        (logs / "current.log").write_text(text, encoding="utf-8")
        print(text)
        if result.returncode or unexpected_errors(text) or "UPGRADE_SNAPSHOT_RESULT failures=0" not in text:
            raise SystemExit(1)

if __name__ == "__main__": main()
