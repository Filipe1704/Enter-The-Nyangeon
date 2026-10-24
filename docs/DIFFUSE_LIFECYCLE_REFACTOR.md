# DOT Diffusion Refactoring / 火与毒扩散生命周期复用

> 日期：2026-10-20。基线：`9c36af6`。对应简化审查第四项 AUD-REF-004，验证范围如下。

## Implementation / 实现

- 新增 `script/dot_diffuse.gd`（`DotDiffuse`，继承 Node2D），集中公共导出字段、Timer/Area2D 引用、目标集合、reset 门控、进出回调、超时收尾与飘字池化。不增加 autoload。
- `scenes/debuff/fire_diffuse.gd` / `poison_diffuse.gd` 按路径继承基类。`_apply_diffusion()` 分别调用原公开 `fire_dot_add()` / `poison_dot_add()`；毒通过 `_targets_changed()` 调用原公开 `sort_enemy()`。场景信号仍使用原回调名。
- 两个 `.tscn`、Momoi/Midori 等角色 PS、Buff 资源与管理器、联机入口均不改。原字段和 is_end 信号继续可用，is_end 仍不发射。

## Compatibility / 保留的行为

- reset 在 `add_end=false` 时直接返回；允许重用时先置 false、清集合，再延迟开启 monitoring/monitorable 并启动 Timer。超时先置 `add_end=true`，调用各自结算，最后同步关闭探测；结算回调中再次 reset 的顺序也保留。
- 火的 Timer 为 one_shot，毒的 Timer 为重复模式，均保留场景原始 0.1 秒配置；超时没有新增 stop、clear 或“只结算一次”的门控。
- 火逆序遍历全部目标，逐个剔除无效项并施加燃烧；每轮共用一个 value 数组。毒先剔除无效项，按现有集合顺序取最多 enemy_num 个目标；只在目标实际进入/退出时按距离排序，不因结算或移动重新排序。
- 毒仅在目标没有 poison_diffuse 标签时写入 diffuse_num，既有标签不覆盖；value 仍在每目标施加前构造。两者继续直接调用 enemy_buff_manager.apply_buff，不迁移到其他路由。
- 两者只有进入结算时集合为空才跳过飘字；集合原本非空、但剔除后全失效，或毒的 enemy_num=0，仍显示飘字。池复用条件、16 号字、橙/绿色、随机偏移、翻译键与两次随机数调用顺序均保留。
- Momoi 的命中节流、Midori 的链式计数与生成节流、最多 31 个节点的轮转重用仍由角色脚本处理，本轮没有迁移。

## Validation / 验证

- 改代码前执行 `python tests/run_diffuse_lifecycle_checks.py before`，直接加载未改动的真实 fire_diffuse/poison_diffuse 场景采集基线。两个原版脚本与 `9c36af6` Git blob 核对一致，另存副本及 SHA-256；runner 拒绝覆盖已存在的 before.json，after 会核验备份校验值。
- 改后执行同一入口 `after`：**31 个场景、221 项断言、0 失败，317 条状态追踪与原版完全一致**。追踪包含 Buff 调用目标/顺序/参数、标签、value、add_end、探测开关、Timer 模式与停止状态、is_end 次数、飘字文本/颜色/字号/位置/池复用，以及下一个随机数。
- 覆盖空集合、正常顺序、部分/全部目标释放、重复/空/失效/非敌人进出事件、目标移动后结算、进行中 reset、完成后重用、直接调用公共结算方法、重复超时、空闲/忙碌飘字池、结算期间重入 reset，以及毒的 0/1/超额人数、既有标签与零链式次数。
- 真实物理场景使用原 Area2D/CircleShape2D 与 Rapier2D 接收 body_entered/body_exited，由实际 Timer 发射 timeout；验证火只触发一次、毒连续触发两次，以及关闭探测后移除目标。其余场景直接调用原公开方法与回调，以追踪同步/延迟操作顺序。
- 上一阶段回归仍通过：`run_refactor_reuse_checks.py after` 为 221 项断言、35 道具 105 组快照一致；`run_shop_purchase_flow_checks.py after` 为 48 场景、245 项断言、570 条追踪一致。
- Godot 4.7 stable headless，使用 `.godot/refactor_reuse_checks/source` 隔离工程目录联接；每次以 `etn-diffuse-*` 临时目录探测真实 user://，原 project.godot 与玩家存档不变。两轮无脚本错误，均有相同既有退出计数诊断：2 个 ObjectDB 实例、1 个仍在使用的资源。
- 原版备份：`.godot/refactor_reuse_checks/source/.godot/diffuse_original/`；基线提交/哈希：`.godot/diffuse_lifecycle_checks/baseline-sources.json`；快照/日志：同目录 `{before,after}.{json,log}`。测试只供本地验证，位于 tests/，不提交，未接入 CI。

## Limits / 边界

目标使用带真实 CharacterBody2D/碰撞形状的探针，Buff 管理器用记录器收集调用；飘字使用真实场景与 PoolManager。此次未重跑完整燃烧/中毒跳伤、角色整局战斗、真实联机或 Release 导出；没有把上述既有行为差异作为缺陷一并修正。
