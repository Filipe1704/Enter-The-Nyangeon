"""隔离验证冲突依赖闭包与卸载链接边界；只删除本次临时实验目录。"""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from godot_check_output import unexpected_errors
from isolated_godot import REPO, prepare


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", str(REPO.parent / ".tools/godot/Godot_v4.7-stable_win64_console.exe")))
    args = parser.parse_args()
    logs = REPO / ".godot/mod_lifecycle_checks"
    logs.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="etn-mod-lifecycle-", ignore_cleanup_errors=True) as directory:
        root = Path(directory).resolve()
        env = prepare(args.godot, root / "user", [])
        user = next((root / "user/APPDATA/Godot/app_userdata").iterdir()) if os.name == "nt" else next((root / "user/XDG_DATA_HOME/godot/app_userdata").iterdir())
        mods = user / "mods"
        for name in ("nested", "root_link"):
            target = root / name
            target.mkdir()
            (target / "keep.txt").write_text("outside sentinel", encoding="utf-8")
            link = mods / name / "linked" if name == "nested" else mods / name
            link.parent.mkdir(parents=True, exist_ok=True)
            assert target.resolve().is_relative_to(root) and link.parent.resolve().is_relative_to(root)
            if os.name == "nt":
                command = "New-Item -ItemType Junction -Path '" + str(link).replace("'", "''") + "' -Target '" + str(target).replace("'", "''") + "' | Out-Null"
                subprocess.run(["pwsh", "-NoProfile", "-Command", command], check=True, capture_output=True)
            else:
                link.symlink_to(target, target_is_directory=True)
        hidden = mods / "hidden/.child"
        hidden.mkdir(parents=True)
        (hidden / ".keep").write_text("hidden sentinel", encoding="utf-8")
        env["ETN_LIFECYCLE_ROOT"] = root.as_posix()
        result = subprocess.run([args.godot, "--headless", "--path", str(REPO), "--script", "res://tests/mod_lifecycle_checks.gd"], env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=25,
                                creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        text = result.stdout + result.stderr
        (logs / "current.log").write_text(text, encoding="utf-8")
        print(text)
        if result.returncode or unexpected_errors(text) or "MOD_LIFECYCLE_RESULT failures=0" not in text:
            raise SystemExit(1)


if __name__ == "__main__": main()
