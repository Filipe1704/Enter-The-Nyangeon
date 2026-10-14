"""Godot 回归的错误分类；仅精确豁免既有退出资源计数告警。"""
import re

ANSI = re.compile(r"\x1b\[[0-9;]*m")
EXIT_RESOURCE_COUNT = re.compile(r"ERROR: \d+ resources? still in use at exit \(run with --verbose for details\)\.")


def unexpected_errors(output):
    errors = []
    for raw in output.splitlines():
        line = ANSI.sub("", raw).strip()
        if ("SCRIPT ERROR:" in line or line.startswith("ERROR:")) and not EXIT_RESOURCE_COUNT.fullmatch(line):
            errors.append(line)
    return errors
