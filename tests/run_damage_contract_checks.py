"""从 SDK 构建实际 PCK，隔离验证角色/藏品前置修饰跨协议的数值等价。"""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from isolated_godot import BASE, REPO, prepare, run
from godot_check_output import unexpected_errors

def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=str(REPO.parent / ".tools/godot/Godot_v4.7-stable_win64_console.exe"))
    args = parser.parse_args()
    logs = REPO / ".godot/damage_contract_checks"
    logs.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="etn-damage-contract-") as directory:
        task = Path(directory)
        pack = task / "etn_coop.pck"
        code, text = run(["pwsh", "-NoProfile", "-File", str(REPO / "mod_sdk/pack_mod_source.ps1"), "-Source", str(BASE), "-ModId", "etn_coop", "-Godot", args.godot, "-Output", str(pack)], os.environ.copy(), logs / "pack.log", 60)
        if code or not pack.is_file(): raise RuntimeError(text)
        env = prepare(args.godot, task / "user", [(BASE, pack)])
        code, text = run([args.godot, "--headless", "--path", str(REPO), "--script", "res://tests/damage_contract_checks.gd"], env, logs / "current.log", 30)
        print(text)
        if code or unexpected_errors(text) or "DAMAGE_CONTRACT_RESULT failures=0" not in text:
            raise SystemExit(1)

if __name__ == "__main__": main()
