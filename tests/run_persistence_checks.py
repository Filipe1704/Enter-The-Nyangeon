"""在隔离 user:// 验证存档恢复、坏档保护及写入失败；不读取玩家存档。"""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
import sys
from godot_check_output import unexpected_errors

REPO = Path(__file__).resolve().parents[1]

SCRIPT = '''extends SceneTree
class FailingStore extends "res://script/scene_data_store.gd":
    var target := ""
    func _replace(source: String, destination: String) -> Error:
        if destination == target: return ERR_CANT_CREATE
        return super._replace(source, destination)
var failures := 0
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        print("FAIL: " + message)
func _initialize(): _run.call_deferred()
func _run():
    var pd = root.get_node("PlayerData")
    var game = root.get_node("Game")
    var mode = OS.get_cmdline_user_args()[0]
    if mode == "seed":
        pd.character = ["momoi", "midori", "aris", "yuzu", "audit_unlocked"]
        pd.player_pyroxenes = 4321
        game.save_playerdata()
    elif mode == "recover":
        check(pd.player_pyroxenes == 4321, "恢复备份货币")
        check(pd.character.has("audit_unlocked"), "恢复解锁角色")
        pd.player_pyroxenes += 1
        var current = ResourceLoader.load("user://PlayerData.res", "", ResourceLoader.CACHE_MODE_IGNORE)
        check(current is SceneData and current.player_pyroxenes == 4322, "恢复后可继续保存")
        DirAccess.copy_absolute("user://PlayerData.res.bak", "user://check_backup.res")
        var backup = ResourceLoader.load("user://check_backup.res", "", ResourceLoader.CACHE_MODE_IGNORE)
        check(backup is SceneData and backup.player_pyroxenes == 4321, "首次自动保存保留有效备份")
    elif mode == "blocked":
        var old_main = FileAccess.get_file_as_bytes("user://PlayerData.res")
        var old_backup = FileAccess.get_file_as_bytes("user://PlayerData.res.bak")
        pd.player_pyroxenes = 1
        game.save_playerdata()
        check(FileAccess.get_file_as_bytes("user://PlayerData.res") == old_main, "双坏档不覆盖主档")
        check(FileAccess.get_file_as_bytes("user://PlayerData.res.bak") == old_backup, "双坏档不覆盖备份")
    elif mode == "fresh":
        check(pd.player_pyroxenes == 0, "首次启动为默认进度")
        pd.player_pyroxenes = 7
        check(FileAccess.file_exists("user://PlayerData.res"), "首次启动可保存")
    elif mode == "future_seed":
        var future = SceneData.new()
        future.save_version = SceneData.SAVE_VERSION + 1
        future.player_pyroxenes = 5432
        check(ResourceSaver.save(future, "user://PlayerData.res") == OK, "准备未来版本存档")
    elif mode in ["replace_main", "replace_backup"]:
        var store = FailingStore.new()
        var next = store.load_data()
        next.player_pyroxenes = 5432
        var old_main = FileAccess.get_file_as_bytes("user://PlayerData.res")
        var old_backup = FileAccess.get_file_as_bytes("user://PlayerData.res.bak")
        store.target = store.PRIMARY if mode == "replace_main" else store.BACKUP
        check(not store.save_data(next), "替换失败明确返回失败")
        check(FileAccess.get_file_as_bytes("user://PlayerData.res") == old_main, "替换失败主档保持原字节")
        check(FileAccess.get_file_as_bytes("user://PlayerData.res.bak") == old_backup, "替换失败备份保持原字节")
    print("PERSISTENCE_RESULT mode=%s failures=%d" % [mode, failures])
    quit(1 if failures else 0)
'''


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", str(REPO.parent / ".tools/godot/Godot_v4.7-stable_win64_console.exe")))
    args = parser.parse_args()
    logs = REPO / ".godot/persistence_checks"
    logs.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="etn-persistence-check-") as directory:
        root = Path(directory)
        probe = root / "probe"
        probe.mkdir()
        (probe / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Enter The Nyangeon"\n', encoding="utf-8")
        (probe / "probe.gd").write_text('extends SceneTree\nfunc _initialize():\n    print("USER_DIR=" + OS.get_user_data_dir())\n    quit()\n', encoding="utf-8")
        script = root / "check.gd"
        script.write_text(SCRIPT, encoding="utf-8")
        for case in ("corrupt", "missing", "both_corrupt", "fresh", "future", "replace_main", "replace_backup"):
            env = os.environ.copy()
            for key in ("APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME"):
                env[key] = str(root / case / key)
                Path(env[key]).mkdir(parents=True)
            result = subprocess.run([args.godot, "--headless", "--path", str(probe), "--script", "res://probe.gd"], env=env,
                                    capture_output=True, text=True, encoding="utf-8", timeout=20)
            path = next((line.removeprefix("USER_DIR=") for line in result.stdout.splitlines() if line.startswith("USER_DIR=")), "")
            if result.returncode or not path or not Path(path).resolve().is_relative_to(root.resolve()):
                raise RuntimeError("user:// 隔离失败")
            user = Path(path)
            user.mkdir(parents=True, exist_ok=True)

            def run(mode):
                result = subprocess.run([args.godot, "--headless", "--path", str(REPO), "--script", str(script), "--", mode],
                                        env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=25,
                                        creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
                text = result.stdout + result.stderr
                (logs / f"{case}_{mode}.log").write_text(text, encoding="utf-8")
                if result.returncode or unexpected_errors(text) or f"PERSISTENCE_RESULT mode={mode} failures=0" not in text:
                    raise RuntimeError(text)
                return text

            if case == "fresh":
                run("fresh")
            else:
                run("seed")
                if case.startswith("replace_"):
                    run(case)
                    print(case + ": PASS", flush=True)
                    continue
                if case == "future":
                    run("future_seed")
                    run("blocked")
                    print(case + ": PASS", flush=True)
                    continue
                if case == "missing":
                    (user / "PlayerData.res").unlink()
                else:
                    (user / "PlayerData.res").write_bytes(b"corrupt resource")
                if case == "both_corrupt":
                    (user / "PlayerData.res.bak").write_bytes(b"corrupt backup")
                run("blocked" if case == "both_corrupt" else "recover")
            print(case + ": PASS", flush=True)


if __name__ == "__main__":
    main()
