# Shop Purchase Refactoring / 商店确认与购买流程重构

> 日期：2026-10-20。基线：`e04c48d`。对应简化审查第三项 AUD-REF-003，验证范围如下。

## Implementation / 实现

- 新增 `ui/shop_purchase_card.gd`（`ShopPurchaseCard`，继承 PanelContainer）。共享 yes/no 控件及四个 AnimationPlayer 的解析、输入接线、悬停、确认打开/关闭、余额判断、扣款和成功动画。
- `ui/character_shop_card.gd` 与 `ui/item_shop_card.gd` 继承该基类，`_ready()` 先调用 super 再填充商品展示；只通过 `_get_purchase_cost()` 和 `_grant_purchase()` 提供当前价格与商品解锁操作。
- 原有 `get_card/check_data/add_character/add_item/reveal/conceal` 等商品专属入口保留；共用方法由基类继承，名称、节点路径与场景资源不变。角色卡继续使用 LazyTextureBinding。
- 角色解锁仍依次添加角色、添加非空社团，各自按需存档，随后 emit_check_data；服装解锁仍按 id_name 分组添加服装并按需存档，不新增 check_data 通知。

## Compatibility / 保留的行为

- 触屏确认购买：播放按钮音效、关闭 yes/no、播放 yes 选中动画并等待，之后才检查当时的余额与价格；余额不足会倒放按钮动画并重新开放 yes/no。
- 鼠标/`shoot`：立即检查余额，成功时先解锁和扣款、播放金币音效，再关闭 yes/no；不足时只通知 Arona。未增加 ui_accept 输入支持。
- 两种输入的成功动画都按倒放 confirm_anim→主动画 RESET→倒放 select_anim→deal_anim 执行；打开/取消的等待点、按钮门控与 is_confirm 状态保留。
- 不缓存购买价格：余额比较读取一次价格，解锁回调结束后扣款再读取一次，保留原来的可观察顺序。先解锁存档/通知，再修改 player_pyroxenes；货币 setter 先发 pyroxenes_changed，再存档。
- 已拥有检查仍由各卡片 check_data 处理；没有在公共购买入口添加新的去重锁或已拥有拦截。专项包含程序直接重复派发购买事件的原行为，不将其解释为新的用户交互规则。

## Validation / 验证

- 入口：`python tests/run_shop_purchase_flow_checks.py before` / `after`，本地 Godot 4.7 stable headless；源码运行使用上一阶段的隔离工程目录联接，原 project.godot 未修改，每次探测独立 `etn-shop-flow-*` user://，不接触玩家存档。
- 改前脚本在改动前原样备份到隔离工程的 `.godot/shop_flow_original/`，与 `e04c48d` 对照；before 使用真实两类场景，并在入树前换为备份脚本。after 使用当前脚本，两轮使用同一组场景与输入。
- 改前/改后均为 **48 个场景、245 项断言、0 失败**；逐项对比 **570 条状态追踪完全一致**。追踪包括动画开始/结束、动画名/播放方向、确认状态、三个鼠标过滤状态、余额、角色/社团/服装集合、check_data/pyroxenes_changed/余额不足通知顺序、主档及备份内容。
- 覆盖鼠标、shoot、触屏的打开、成功、不足、取消；触屏等待期间余额减少或价格改变；零价、恰好足额、已拥有、空社团、已有社团、缺失服装分组、空商品、公共解锁方法、重复事件、释放/未支持输入、悬停和重复打开。
- 另覆盖 `shop_menu.gd` 的实际装配顺序：卡片先入树，再填 shop_card、get_card、check_data，验证继承后初始化和价格展示不变。
- 上一阶段回归 `python tests/run_refactor_reuse_checks.py after` 仍通过：221 项断言、35 个道具的 105 组属性快照一致，四类立绘卡片生命周期及共享引用检查通过。
- 两轮均无脚本错误；仍有相同的既有退出诊断：2 个 ObjectDB 实例、1 个仍在使用的资源。仅沿用仓库对退出资源计数的精确豁免，不宣称进程完全没有诊断。
- 原版备份、快照和日志分别位于 `.godot/refactor_reuse_checks/source/.godot/shop_flow_original/`、`.godot/shop_purchase_flow_checks/{before,after}.{json,log}`。测试脚本只供本地验证，不提交，不代表已接入 CI。

## Limits / 边界

动画用真实 AnimationPlayer 手动推进，输入直接派发真实卡片的 GUI 信号；未覆盖真实鼠标命中路由、逐像素画面或导出的 Release EXE。此次不调整购买规则、持久化格式、支援商店或 .tscn 布局。
