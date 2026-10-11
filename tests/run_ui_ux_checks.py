"""在独立的 Godot 用户目录中运行 UI 回归检查，不接触玩家存档。"""

import argparse
import json
import os
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    # Godot 输出 UTF-8，避免 Windows 默认代码页误解码中文日志。
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, help="Godot 4.7 可执行文件路径")
    parser.add_argument("--screenshots", action="store_true", help="使用渲染窗口输出场景截图到 .godot/ui_ux_checks")
    parser.add_argument("--character-focus-only", action="store_true", help="只检查选角连续左右导航与确认")
    parser.add_argument("--main-menu-focus-only", action="store_true", help="只检查主菜单焦点交接与 MOD 菜单顺序（需 --screenshots）")
    parser.add_argument("--installed-mods", action="store_true", help="复制本机已安装 MOD 到隔离目录后检查")
    parser.add_argument("--test-item-input-only", action="store_true", help="只检查测试房道具列表的鼠标点击与拖动（需 --screenshots）")
    parser.add_argument("--scroll-input-only", action="store_true", help="只检查列表滚动的鼠标拖动状态（需 --screenshots）")
    parser.add_argument("--level-focus-only", action="store_true", help="只检查难度页支援、难度、模式及返回的键盘导航")
    args = parser.parse_args()
    if args.main_menu_focus_only and not args.screenshots:
        parser.error("--main-menu-focus-only 需要 --screenshots，以验证真实鼠标命中")
    if args.test_item_input_only and not args.screenshots:
        parser.error("--test-item-input-only 需要 --screenshots，以验证真实 GUI 事件路由")
    if args.scroll_input_only and not args.screenshots:
        parser.error("--scroll-input-only 需要 --screenshots，以验证真实 GUI 事件路由")
    repo = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="etn-ui-ux-") as directory:
        temporary = Path(directory)
        environment = os.environ.copy()
        environment["APPDATA"] = str(temporary / "roaming")
        environment["LOCALAPPDATA"] = str(temporary / "local")
        environment["XDG_DATA_HOME"] = str(temporary / "data")
        for key in ("APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME"):
            Path(environment[key]).mkdir()
        # 先在无 autoload 项目验证隔离确实生效，再加载真实项目。
        probe = temporary / "probe"
        probe.mkdir()
        (probe / "project.godot").write_text(
            'config_version=5\n[application]\nconfig/name="ETN UI probe"\n',
            encoding="utf-8",
        )
        (probe / "probe.gd").write_text(
            'extends SceneTree\nfunc _initialize():\n'
            '\tprint("USER_DIR=" + OS.get_user_data_dir())\n\tquit()\n',
            encoding="utf-8",
        )
        command = [args.godot, "--headless", "--path", str(probe), "--script", "res://probe.gd"]
        result = subprocess.run(command, env=environment, capture_output=True, text=True, encoding="utf-8", timeout=30)
        user_directory = next(
            (line.removeprefix("USER_DIR=") for line in result.stdout.splitlines() if line.startswith("USER_DIR=")),
            "",
        )
        if result.returncode or not user_directory or not Path(user_directory).resolve().is_relative_to(temporary.resolve()):
            raise RuntimeError("Godot 用户目录隔离验证失败，未启动项目测试")
        save_directory = Path(user_directory).parent / "Enter The Nyangeon"
        save_directory.mkdir(parents=True, exist_ok=True)
        if args.installed_mods:
            installed = Path(os.environ["APPDATA"]) / "Godot/app_userdata/Enter The Nyangeon/mods"
            if installed.exists():
                shutil.copytree(installed, save_directory / "mods")
        (probe / "probe.gd").write_text(
            'extends SceneTree\nfunc _initialize():\n'
            '\tquit(ResourceSaver.save(Resource.new(), '
            + json.dumps(str(save_directory / "PlayerData.res")) + '))\n',
            encoding="utf-8",
        )
        subprocess.run(command, env=environment, capture_output=True, text=True, encoding="utf-8", timeout=30, check=True)
        display = [] if args.screenshots else ["--headless"]
        command = [args.godot, *display, "--path", str(repo), "--script", "res://tests/test_ui_ux_regressions.gd"]
        game_args = []
        if args.screenshots:
            game_args.append("--ui-ux-screenshots")
        if args.character_focus_only:
            game_args.append("--ui-ux-character-focus-only")
        if args.main_menu_focus_only:
            game_args.append("--ui-ux-main-menu-focus-only")
        if args.test_item_input_only:
            game_args.append("--ui-ux-test-item-input-only")
        if args.scroll_input_only:
            game_args.append("--ui-ux-scroll-input-only")
        if args.level_focus_only:
            game_args.append("--ui-ux-level-focus-only")
        if game_args:
            command += ["--", *game_args]
        result = subprocess.run(command, env=environment, capture_output=True, text=True, encoding="utf-8", timeout=90)
        print(result.stdout, end="")
        print(result.stderr, end="")
        # 函数中断不一定使引擎非零退出，同时检查日志和完成标记。
        return result.returncode or int("SCRIPT ERROR:" in result.stderr or "UI_UX_RESULT" not in result.stdout)


if __name__ == "__main__":
    raise SystemExit(main())
