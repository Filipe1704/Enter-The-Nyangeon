"""真实 PCK 支援存档跨进程启停、旧格式迁移及缺失备份恢复；隔离 user://。"""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from godot_check_output import unexpected_errors
from isolated_godot import REPO, prepare

SCRIPT = r'''extends SceneTree
var failures := 0
const SUPPORT_ID := "audit_support_selected"
const OTHER_ID := "audit_support_owned"
func _initialize(): _run.call_deferred()
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        print("FAIL: " + message)
func _run():
    var mode := OS.get_environment("ETN_SUPPORT_MODE")
    var game = root.get_node("Game")
    var pd = root.get_node("PlayerData")
    var support = root.get_node("SupportData")
    if mode.begins_with("seed"):
        DirAccess.make_dir_recursive_absolute("user://mods/audit_support")
        var pack := PCKPacker.new()
        check(pack.pck_start("user://mods/audit_support/audit_support.pck") == OK, "创建 PCK")
        for pair in [[SUPPORT_ID, "different_file_name"], [OTHER_ID, "other_card"]]:
            var card := SupportCard.new()
            card.support_id = pair[0]
            var source: String = "user://" + str(pair[1]) + ".tres"
            check(ResourceSaver.save(card, source) == OK, "准备支援资源")
            check(pack.add_file("res://mods/audit_support/defs/supports/" + pair[1] + ".tres", source) == OK, "资源加入 PCK")
        check(pack.flush() == OK, "完成 PCK")
        var manifest := FileAccess.open("user://mods/audit_support/mod.json", FileAccess.WRITE)
        manifest.store_string('{"id":"audit_support","version":"1.0.0","pck":"audit_support.pck"}')
        manifest.close()
        check(ProjectSettings.load_resource_pack("user://mods/audit_support/audit_support.pck"), "挂载 PCK")
        var selected = load("res://mods/audit_support/defs/supports/different_file_name.tres")
        var owned = load("res://mods/audit_support/defs/supports/other_card.tres")
        support.support_data = {SUPPORT_ID: {"resource": selected, "LV": 10, "exp": 9000}, OTHER_ID: {"resource": owned, "LV": 5, "exp": 4000}}
        support.game_support = selected
        pd.character = ["momoi", "audit_unlocked"]
        pd.player_pyroxenes = 4321
        if mode == "seed_legacy":
            var legacy := SceneData.new()
            legacy.save_version = 2
            legacy.player_pyroxenes = 4321
            legacy.character = pd.character
            legacy.support_savedata = support.support_data
            legacy.game_support = selected
            check(ResourceSaver.save(legacy, "user://PlayerData.res") == OK, "写入旧 v2")
            check(DirAccess.copy_absolute("user://PlayerData.res", "user://PlayerData.res.bak") == OK, "准备旧备份")
        else:
            check(game.save_playerdata(), "保存新格式")
    else:
        check(pd.player_pyroxenes == 4321, "启动阶段已恢复本体货币")
        check(pd.character.has("audit_unlocked"), "角色解锁保留")
        for pair in [[SUPPORT_ID, 10, 9000], [OTHER_ID, 5, 4000]]:
            var entry = support.support_data.get(pair[0], {})
            check(entry.get("LV", -1) == pair[1] and entry.get("exp", -1) == pair[2], "支援等级经验保留：" + pair[0])
        if mode == "disabled":
            check(support.game_support != null and support.game_support.support_id == "null", "停用后使用安全空支援")
            check(support.get("selected_support_id") == SUPPORT_ID, "停用时保留所选 ID，不能由文件名猜 ID")
            check(not ResourceLoader.exists("res://mods/audit_support/defs/supports/different_file_name.tres"), "临时加载器已撤销且占位未留在全局缓存")
            var panel = load("res://ui/support_ui/support_select_ui.tscn").instantiate()
            root.add_child(panel)
            panel.add_cards()
            check(panel.support_box.get_child_count() == 1, "未启用支援不进入选择列表")
            panel.queue_free()
            await process_frame
        else:
            check(support.game_support != null and support.game_support.support_id == SUPPORT_ID, "重新启用恢复所选支援")
        check(game.save_playerdata(), "仍可继续保存")
        for path in ["user://PlayerData.res", "user://PlayerData.res.bak"]:
            var read_path = "user://inspect.res"
            check(DirAccess.copy_absolute(path, read_path) == OK, "复制检查")
            var current = ResourceLoader.load(read_path, "", ResourceLoader.CACHE_MODE_IGNORE)
            check(current != null and current.save_version == SceneData.SAVE_VERSION, "当前格式有效")
            if current != null:
                check(current.game_support == null, "不序列化当前支援 Resource")
                for entry in current.support_savedata.values(): check(not entry.has("resource"), "不序列化已购买支援 Resource")
            for dep in ResourceLoader.get_dependencies(read_path): check(not str(dep).contains("res://mods/"), "新档没有外部 Mod 依赖")
    print("SUPPORT_PERSISTENCE_RESULT mode=%s failures=%d" % [mode, failures])
    quit(1 if failures else 0)
'''


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=str(REPO.parent / ".tools/godot/Godot_v4.7-stable_win64_console.exe"))
    args = parser.parse_args()
    logs = REPO / ".godot/support_persistence_checks"
    logs.mkdir(parents=True, exist_ok=True)
    failures = []
    for case in ("new", "legacy_enabled", "legacy_disabled", "legacy_backup"):
        with tempfile.TemporaryDirectory(prefix="etn-support-save-", ignore_cleanup_errors=True) as directory:
            root = Path(directory)
            env = prepare(args.godot, root / "user", [])
            user = next((root / "user/APPDATA/Godot/app_userdata").iterdir()) if os.name == "nt" else next((root / "user/XDG_DATA_HOME/godot/app_userdata").iterdir())
            script = root / "check.gd"
            script.write_text(SCRIPT, encoding="utf-8")
            stages = ["seed_new" if case == "new" else "seed_legacy"]
            if case == "legacy_enabled": stages.append("enabled")
            stages += ["disabled", "enabled"]
            for index, mode in enumerate(stages):
                if mode in ("disabled", "enabled"):
                    (user / "mods/mods_state.json").write_text('{"audit_support": ' + ("false" if mode == "disabled" else "true") + '}', encoding="utf-8")
                if case == "legacy_backup" and mode == "disabled":
                    (user / "PlayerData.res").unlink()
                env["ETN_SUPPORT_MODE"] = mode
                result = subprocess.run([args.godot, "--headless", "--path", str(REPO), "--script", str(script)], env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=30,
                                        creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
                text = result.stdout + result.stderr
                (logs / f"{case}_{index}_{mode}.log").write_text(text, encoding="utf-8")
                if result.returncode or unexpected_errors(text) or f"SUPPORT_PERSISTENCE_RESULT mode={mode} failures=0" not in text:
                    failures.append(case + "/" + mode)
                    print(case + "/" + mode + ": FAIL\n" + "\n".join(line for line in text.splitlines() if "FAIL:" in line or "ERROR:" in line), flush=True)
                    break
            else:
                print(case + ": PASS", flush=True)
    if failures: raise SystemExit("失败：" + ", ".join(failures))


if __name__ == "__main__": main()
