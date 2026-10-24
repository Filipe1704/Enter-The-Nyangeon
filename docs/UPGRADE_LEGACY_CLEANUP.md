# Legacy Upgrade Cleanup / 旧升级抽取代码清理

> 日期：2026-10-20。基线：`1e84934`。对应简化审查第五项 AUD-REF-005，验证范围如下。

## Scope / 范围

- 只修改 `scenes/manager/upgrade_manager.gd`：删除无仓库内调用的 `pick_upgrades()`、仅服务该算法的 `tag_sort()`、调用已注释的 `tag_count()`，以及 `round_bouns`、`tag_1/2/3` 四个旧字段、`round_bouns += 3` 与已注释的 `tag_count(upgrade)`。合计删除 86 行。
- 保留当前链路 `add_upgrade_card()` → `get_triple_choice()` → `get_random_options()` → `get_random_item_from_pool()`，以及 `build_pool()` / AliasMethod。`get_random_options()` 的“备用”注释不是判断可删除的依据，它仍是正式调用链的一部分。
- 保留 `tags_group` 字段和 `get_current_context()` 中的 `player_tags` 键、字典内容及共享引用；不把它替换为新空字典，也不恢复旧标签计数行为。
- 保留 `round_bouns_upgrade()`，仅去掉上述旧字段增量；回合计数上限、权重曲线、防御加成、test_mode 与移动端鼠标分支均保持。所有导出字段、当前抽取/刷新规则、物品应用与叠加、信号连接不变。
- 两个权重脚本、管理器场景、UpgradeScreen、道具资源/脚本、SDK 与联机入口均不改。另三项看似闲置的池配置导出字段不纳入本次清理。

## References / 引用核实

清理前对本体、测试、SDK、官方 coop 和文本场景/资源（含忽略目录）扫描：pick_upgrades 无直接调用或方法名字符串调用，tag_sort 仅由旧 pick_upgrades 调用，tag_count 仅有已注释调用；四个旧字段的读取仅属于旧算法。当前 UI 的选卡和刷新分别继续连接 on_upgrade_selected 与 add_upgrade_card；主关卡和测试房继续实例化原 UpgradeManager 场景。核实阶段的源码证据以基线 `1e84934` 为准，清理后入口位置见 `upgrade_manager.gd:33-89,145-220`。

## Validation / 验证

- 改代码前执行 `python tests/run_upgrade_cleanup_checks.py before`，直接运行未修改的真实管理器场景。种子为 `0`、`1`、`42`、`20261020`、`2147483647`；原脚本与 Git blob 核对一致，保存原始副本与 SHA-256。runner 拒绝覆盖已有 before.json，改后还核验管理器场景、ItemWeightManager、weight_system 和 UpgradeScreen 源码校验值未变。
- 改后运行同入口 `after`：**50 个场景、966 项断言、0 失败；520 条追踪与改前完全一致**。追踪包括选项及顺序、池内容、AliasMethod 概率/别名表、稀有度权重、刷新参数、防御加成、当前升级及 PlayerData 镜像、标签上下文、选择历史的道具/标签、玩家状态、装备实例与叠加数量、真实升级页选项，以及每步后继随机数。后继随机数存为字符串以精确比较；仅忽略历史记录中的墙钟 time，不改运行代码。
- 每个种子覆盖：完整本体池首次抽取/缓存池重用、真实升级页创建/连续三次刷新/选卡连接、木锤三次选择及次数上限、23 次回合结束（含第 20 回合封顶、test_mode 两分支）、非空标签与上下文共享引用、公共抽样入口、池中仅有一种/两种资源时 100 次尝试后的原返回方式、get_player 信号触发 reset_data。
- 源码核对保留的 **14 个方法**：除 round_bouns_upgrade 删除已废弃增量外，可执行内容及顺序与原版一致；没有新增方法。四个旧字段与三个旧方法均已移除，tags_group 和全部导出字段保留。
- 既有 `tests/upgrade_snapshot_checks.gd` 在改前/改后均通过（`UPGRADE_SNAPSHOT_RESULT failures=0`），验证刷新权重递增、选择后复位、非满血比例与原联机快照外推不变量。执行时使用同一隔离工程，未修改既有测试脚本。
- Godot 4.7 stable headless；使用 `.godot/refactor_reuse_checks/source` 的源码目录联接，每轮真实 user:// 由独立 `etn-upgrade-cleanup-*` 临时目录探测；原 project.godot 与用户存档不变。专项两轮无脚本错误，均保留相同既有退出诊断：2 个 ObjectDB 实例、1 个仍在使用的资源。
- 证据位于 `.godot/upgrade_cleanup_checks/`：`upgrade_manager.original.gd`、`baseline-sources.json`、`{before,after}.{json,log}`、`existing-{before,after}.log`。测试入口 `tests/run_upgrade_cleanup_checks.py` / `upgrade_cleanup_checks.gd` 仅本地使用，不提交，未接入 CI。

## Limits / 边界

测试使用真实管理器、权重、UI 与安全道具场景；玩家采用真实 Momoi Stats 的轻量替身，不运行完整角色控制/战斗。UI 验证直接调用其刷新/选卡方法，不覆盖真实点击命中或刷新扣金币；headless 不验证桌面鼠标实际隐藏，鼠标分支由源码一致性核对约束。未重跑完整战斗、真实联机、移动端或 Release 导出。

本次保证范围是保留的当前抽取流程。删除旧方法/字段本身会影响直接使用它们的扩展；它们没有列入 ModAPI 稳定接口，但静态扫描无法保证仓库外已打包 Mod 或动态拼接方法名的兼容性。
