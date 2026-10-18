"""独立验证官方联机拓展契约与菜单，不安装任何附属 Mod。"""
import argparse
import os
from pathlib import Path
import shutil
import sys
import tempfile

from godot_check_output import unexpected_errors
from isolated_godot import BASE, REPO, environment, prepare, run


def check(code, text, marker):
    if code or unexpected_errors(text) or marker not in text or "FAIL:" in text:
        raise RuntimeError(text)


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", str(REPO.parent / ".tools/godot/Godot_v4.7-stable_win64_console.exe")))
    args = parser.parse_args()
    logs = REPO / ".godot/coop_official_extension_checks"
    logs.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="etn-official-extension-") as directory:
        task = Path(directory)
        minimal = task / "contract"
        minimal.mkdir()
        (minimal / "project.godot").write_text("config_version=5\n", encoding="utf-8")
        shutil.copy2(BASE / "net/coop_extensions.gd", minimal / "registry.gd")
        shutil.copy2(REPO / "tests/coop_extension_contract_checks.gd", minimal / "check.gd")
        code, text = run([args.godot, "--headless", "--path", str(minimal), "--script", "res://check.gd"],
                         environment(minimal / "user"), logs / "contract.log")
        check(code, text, "failures=0")
        print(text, flush=True)
        pack = task / "etn_coop.pck"
        code, text = run(["pwsh", "-NoProfile", "-File", str(REPO / "mod_sdk/pack_mod_source.ps1"),
                          "-Source", str(BASE), "-ModId", "etn_coop", "-Godot", args.godot, "-Output", str(pack)],
                         os.environ.copy(), logs / "pack.log", 60)
        if code or not pack.is_file():
            raise RuntimeError(text)
        env = prepare(args.godot, task / "session", [(BASE, pack)])
        code, text = run([args.godot, "--headless", "--path", str(REPO),
                          "--script", "res://tests/coop_official_extension_checks.gd"], env, logs / "menu.log", 40)
        check(code, text, "OFFICIAL_EXTENSION_RESULT checks=17 failures=0")
        print(text, flush=True)


if __name__ == "__main__":
    main()
