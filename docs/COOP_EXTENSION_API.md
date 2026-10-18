# Coop Extension API / 官方联机通用拓展接口

> 2026-10-14。本文描述官方 `etn_coop` 的通用接入契约；提供者独立实现，官方包不依赖任何附属包。

## Responsibility / 职责

- `mod_sdk/coop_mod/mods/etn_coop/net/coop_extensions.gd` 管理提供者注册、准备结果与生命周期，接口版本为 1。
- `coop_net.gd` 持有注册表，继续负责 ENet、版本握手、准备房、玩法同步、断线重连与退出；拓展仅交付连接端点，不接管玩法 RPC。
- `ui/coop_menu.gd` 按页面描述创建页签、登记交互控件并维护状态栏。没有提供者时，LAN / Relay / OPTION 保持原流程。

## Provider Contract / 提供者契约

独立 Mod 声明 `dependencies: ["etn_coop"]`，从组 `CoopExtensionHost` 找到注册表，核对 `get_api_version()` 后调用 `register_backend(id, provider)`。提供者资源位于自己的命名空间，不复制官方 `CoopNet`，不替换官方资源。

| 成员 | 要求 |
|---|---|
| `prepared(endpoint: Dictionary)` | 准备完成；endpoint 包含 `port: int`、`host: bool`，可选 `share_text: String` |
| `failed(message: String)` | 准备或在线连接设施失败 |
| `start(plan: Dictionary, hosting: bool) -> bool` | 接受准备返回 true，可异步发出 prepared / failed；同步拒绝返回 false |
| `stop()` | 幂等释放本次资源，并撤销旧异步任务 |
| `diagnostics() -> Dictionary` | 返回不含凭据的状态，至少可提供 state |
| `menu_title: String`、`open_menu()` | 可选；提供独立按钮入口 |
| `create_menu_button() -> Button` | 可选；自定义入口按钮，标题及激活回调由官方菜单设置 |
| `create_menu_page() -> Control` | 可选；返回未挂载的页面，并实现 `get_interactive_controls() -> Array[Control]` |

端口须为 1–65535，host 必须为 bool。房主端点交给 `host_game(port)`；客机端点固定连接 `127.0.0.1:port`。

## Session Lifecycle / 会话生命周期

1. `start_backend(id, plan, hosting)` 先结束旧会话，再启动提供者；准备中拒绝重复启动。
2. `prepared` 后由官方安装 ENet。安装过程不会关闭刚准备好的提供者；ready 表示端点已安装，客机仍需通过游戏握手。
3. 自动重连保留提供者及端点；`close_session()`、F12 或 `cancel(id)` 才结束会话并停止提供者。
4. 提供者故障延迟处理并校验会话代次；旧失败通知不能关闭新会话。在线故障由官方流程返回菜单。
5. 提供者退树自动注销，官方会话退树停止活动提供者。提供者必须自行撤销 stop 前的旧准备任务。

`state_changed(id, state, message)` 的状态为 preparing / ready / idle / failed。拓展会话关闭物理 LAN 广播，房间显示及复制使用提供者的 share_text。

## Menu Pages / 通用页面与状态栏

- 官方通过 `ModAPI.create_option_tab()` 创建页签并放在 OPTION 前，与内置页面互斥；页面自身由官方菜单持有。
- 2026-10-18 起页面插入 `Panel/RootHBox/ContentRoot/PageScroll/PageContent`，高度由内容决定并随外层滚动；不要再假设固定 322px 面板高度。
- 交互名单包含按钮、输入框、滚动容器及滚动条。关闭菜单撤销鼠标及键盘焦点，重开恢复原始 mouse_filter / focus_mode；导航只纳入可见且未禁用的控件。
- 切页或释放菜单不结束提供者会话。菜单缓存每个提供者的准备、失败及游戏连接状态，切页或切换语言后恢复显示；迟到的 offline 通知不覆盖准备或失败结果。

## Damage Contract / 伤害契约

联机伤害由**攻击归属端求值**：客机用命中时自身构筑与目标快照计算 `resolved_damage` 交给房主，房主只做存活/无敌/阵营门控与真实扣血。因此**任何修改敌人受击者 `global_hurt_damage` / `damage_multiplier` 的来源（debuff、道具、光环等）必须经 buff 镜像同步到客机**，否则客机求值将与房主权威结算不一致。新增此类来源时须确认其已通过官方 buff 镜像通道（`_remote_apply_enemy_buff` 等）复制到客机。

## Validation / 验证

`python tests/run_coop_extension_contract_checks.py` 使用临时最小工程验证注册表，再只安装官方源码 PCK，用通用测试提供者验证实际菜单。覆盖 21 项生命周期契约和 17 项菜单/状态检查，不安装任何附属 Mod。

官方会话回归继续使用 `tests/run_coop_recovery_checks.py`；公共隔离工具位于 `tests/isolated_godot.py`。
