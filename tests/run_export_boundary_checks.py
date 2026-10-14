"""真实本体 PCK 不得含开发 Mod 镜像；独立包的新版脚本必须实际可见。"""
import argparse
import os
from pathlib import Path
import sys
from isolated_godot import REPO
from export_boundary_helpers import export_base, export_shadow

def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", str(REPO.parent / ".tools/godot/Godot_v4.7-stable_win64_console.exe")))
    parser.add_argument("--pck", type=Path, help="复核指定产物；默认从当前预设导出")
    args = parser.parse_args()
    args.output = REPO / ".godot/export_boundary_checks"
    args.output.mkdir(parents=True, exist_ok=True)
    if args.pck:
        data = args.pck.read_bytes()
        import struct
        assert data[:4] == b"GDPC" and struct.unpack_from("<I", data, 4)[0] == 4
        offset = struct.unpack_from("<Q", data, 32)[0]
        count = struct.unpack_from("<I", data, offset)[0]
        offset += 4
        paths = []
        for _ in range(count):
            size = struct.unpack_from("<I", data, offset)[0]
            offset += 4
            paths.append(data[offset:offset+size].rstrip(b"\0").decode())
            offset += size + 36
    else:
        args.pck = export_base(args)
        import json
        paths = json.loads((args.output / "export_paths.json").read_text(encoding="utf-8"))
    bad = [p for p in paths if p.startswith("mods/")]
    if bad:
        raise SystemExit("FAIL: 本体含开发镜像：" + str(bad))
    code = export_shadow(args)
    text = (args.output / "export_shadow.log").read_text(encoding="utf-8")
    if code or "NEW_MOD_MARKER_VISIBLE=true" not in text or "SCRIPT ERROR" in text or "ERROR:" in text:
        raise SystemExit("FAIL: 独立包新版脚本不可见")
    print("EXPORT_BOUNDARY_RESULT failures=0")

if __name__ == "__main__": main()
