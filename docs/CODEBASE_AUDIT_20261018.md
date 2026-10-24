# Release Compatibility Audit / 发行版兼容性检查

## Audit Metadata / 审计范围

- 日期：2026-10-18（Asia/Singapore）。
- 基线：`2c8bf49` + 本次 Tooltip `queue_free()` 修复。
- 模式：`release`，仅检查“源码/Debug 正常，但 Windows Release 失效”的兼容性风险，不代表一次完整工程健康审计。
- 平台：Godot 4.7 stable 官方 Windows x86_64 Debug / Release 模板。
- 对象：484 个本体 GDScript、37 个官方联机 GDScript，以及 844 个本体 `.tscn` / `.tres`。
- 构建隔离：使用 `.godot/tooltip_export_debug/game-source` 临时副本；用户数据使用临时目录；本地 godot_ai 项只从临时副本移除。官方联机资源仅作为审计夹具临时打入验证包；不改变正式包排除 `mods/*` 的边界。
- 先前完整审计：`docs/PROJECT_MAP.md` 引用了 2026-10-14 的历史审计，本次未找到对应现存报告/状态文件；不对其范围外的历史结论作重新裁定。

## Executive Summary / 结论

本轮未发现第二处与 Tooltip 相同的 Release 脚本解析故障。已知 Tooltip 故障已修复，真实 Release 的 6 项行为检查已通过。

| 检查环境 | 脚本加载 | 本体场景/资源加载 | 退出码 |
|---|---:|---:|---:|
| 编辑器引擎运行源码 | 521 / 521 | 844 / 844 | 0 |
| 导出的 Windows Debug EXE | 521 / 521 | 844 / 844 | 0 |
| 导出的 Windows Release EXE | 521 / 521 | 844 / 844 | 0 |

本次范围内新增已验证问题：0。不能据此断言所有战斗、联机或移动平台路径均无问题。

## Resolved Findings / 已修复的已知问题

### AUD-REL-001 — Tooltip 宿主在 Release 中解析失败

- 类别：发行版兼容性。
- 严重度：High；置信度：100；状态：resolved；处置：Fix。
- 证据：`ui/hover_tooltip.gd:39-43`。原 Windows EXE 报 `Function "free()" not found in base self.`，导致整脚本加载失败；最小独立 Release 工程可复现 `free()` / `self.free()` 失败。
- 影响：共用宿主的 Tooltip 全部无法显示，即使从未执行到释放分支也会失败。
- 修复：该分支改用 `queue_free()`，帧末释放未挂载节点。
- 建议验证状态：Experimentally Verified。最小 Release 工程、完整游戏 Release 行为检查均通过。
- 行为检查：宿主加载、16 个 Label 初始化、真实道具卡键盘焦点、鼠标悬停、本地化正负效果、失效父节点释放，`checks=6 failures=0`。
- 防回归建议：发行前保留真实 Release EXE 的脚本加载检查与关键 UI 行为检查；编辑器引擎挂载导出包不能替代此项。

## Verified Checks / 已验证的相关风险

### 其余对象上的 free() 不属于同一种解析故障

剩余 7 处调用位于：`scenes/enemies/enemies_spawn/path_spawn.gd:62`、`ui/society_card.gd:43`、`script/mod_manager.gd:542`、`:736`、`:966`、`mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd:8279`、`mod_sdk/coop_mod/mods/etn_coop/net/coop_item_visuals.gd:106`。

这些脚本均通过真实 Release 加载。另用最小 Release EXE 分别执行 `Node` 显式类型、`Node2D` 推导类型、动态变量上的 `对象.free()`，三种情况均确认对象被释放。该实验验证调用方式，不等同于执行上述 7 处业务分支。不建议把所有 `对象.free()` 机械替换为延迟删除。

### 调试开关与资源发现

- `script/damage_data.gd:216-232` 的 `OS.is_debug_build()` 只控制 `check()` 的调试警告，未发现依赖该方法副作用的业务调用；不认定为缺陷。
- `script/mod_manager.gd:192-214` 的目录枚举用于 `user://mods` 和发行版 EXE 旁的松散目录，属于外部文件系统，不是对打包后的 `res://` 资源作 `.tres` 后缀扫描。
- 本体脚本和官方联机源码未检出 `assert()` 承载业务副作用或未保护的编辑器 API 依赖。
- 844 个本体场景/资源在 Debug、Release 均可加载；未发现由打包路径或资源重映射导致的加载失败。

## Automated Guards / 本地复现入口

- 本次三环境对照：`python .godot/release_compat_20261018/run.py`。
- 已知 Tooltip 原包复现：`python .godot/tooltip_export_debug/release_loop.py`。
- Tooltip 行为专项：`.godot/tooltip_export_debug/game-regression-runtime.log`。
- 结果：`.godot/release_compat_20261018/editor.json`、`debug.json`、`release.json` 及对应 `*-runtime.log`。
- 其他 free 调用形式验证：`.godot/release_compat_20261018/free-calls-runtime.log`。
- 上述为本地临时验证，未接入 CI；不宣称已形成长期发布门禁。

## Method and Limitations / 方法与边界

1. 静态检查 `free()`、调试条件、断言、编辑器 API、文件/目录访问及资源加载路径。
2. 在相同临时工程和隔离用户目录中，运行源码、真实 Debug EXE、真实 Release EXE，逐个加载清单中的脚本、场景与资源。
3. 对怀疑的对象释放形式另建最小 Release 工程实际执行，区分静态调用与动态接收者调用。

本轮不包含完整战斗通关、多端联机、全部角色与 Mod 的业务分支、原生图形渲染差异、Android/iOS/Linux Release。官方联机以当前源码夹具验证，未逐一验证用户历史安装的 PCK。场景加载不等于实例化全部场景或执行所有方法。既有 Rapier 编辑器退出资源计数告警不作为新增的 Release 专属故障。
