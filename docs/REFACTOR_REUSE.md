# Refactoring Validation / 道具与立绘复用验证

> 日期：2026-10-20。基线：`6145341` 工作区。仅落实简化审查的前两项，验证范围如下。

## Changes / 改动

- **AUD-REF-001，已解决**：35 个纯属性脚本移除重复的 `_on_equip()`，每次固定效果只在 `_apply_effect(_quantity)` 实现。包括弹鼓、弹药箱、哑铃、同时包含乘法的 wooden_hammer，以及复查补齐的 samuela_the_beyond；表达式、执行顺序和叠加方式保持原样。未改基类调用流程，也未迁移首次/后续效果不同或带额外行为的道具。
- **AUD-REF-002，已解决**：新增 `script/lazy_texture_binding.gd`，集中管理当前路径、LazyTexture 引用、多个显示节点和退出场景树时释放。`ui/player_card.gd`、`ui/character_shop_card.gd`、`ui/support_ui/support_shop_card.gd` 改用绑定；保留公开 reveal/conceal、玩家分支更新与外部滚动控制。继承玩家卡的 `mod_player_card` 同样验证。
- `show_path(path)` 保持“路径相同且主显示节点已有纹理则返回”；clear 释放并清空全部目标。离开场景树只释放引用，保留原纹理值，重新入树后可重新显示。没有改变 LazyTexture 本身的缓存策略。

## Validation / 验证

- 引擎：本地 Godot 4.7 stable Windows console，headless。
- 工程：`.godot/refactor_reuse_checks/source` 使用源码目录联接与独立 project.godot；只在隔离配置中去掉 godot_ai 插件/辅助 autoload。原 project.godot 未修改。
- 用户目录：每轮新建 `etn-refactor-*` 临时目录，通过共用 `isolated_godot.prepare` 探测真实 user:// 确认隔离，不读写玩家存档。
- 初轮基线：`python tests/run_refactor_reuse_checks.py before`，34 个道具，208 项断言、0 失败；初轮改后为 211 项断言、0 失败，102 组快照一致。此结果未覆盖 samuela_the_beyond，后续复查发现其说明注释使旧整文件模板扫描漏选；下述补录与完整复验取代原先的覆盖范围结论。
- 补录基线：在 samuela_the_beyond 尚未修改时运行 `python tests/run_refactor_reuse_checks.py before --extend-baseline samuela_the_beyond`，86 项断言、0 失败。仅采集该道具，与原 34 个道具快照合并；原始 34 项基线另存为 `before-original-34.json`，没有用重构后数值覆盖原基线。
- 最新完整验证：`python tests/run_refactor_reuse_checks.py after`，221 项断言、0 失败；35 个道具首次/第二份/第三份共 105 组 PlayerData 和玩家 Stats 数值快照与基线一致。samuela_the_beyond 额外断言每份 `summoned_damage_add += 0.6`、`bullet_damage_mult -= 0.2`。
- diff 守卫：对照固定基线 `6145341` 验证 35 个道具的属性表达式和顺序一致；再按函数体（忽略空行、说明注释）扫描 `scenes/update_item/*.gd`，剩余同型纯属性重复为 0，防止脚本头部注释造成漏选。首次/叠加不同的 s_bullet 等不纳入机械去重。
- 道具夹具使用真实 momoi 场景导出的 Stats，在精简的玩家宿主上运行真实 EquipItem `_ready()` 和 GameEvents 叠加事件；包含首次事件去重、其他道具事件忽略。没有宣称覆盖完整升级选择界面、战斗通关或孤立道具的资源可达性。
- 四类真实卡片验证：加载、同路径重复显示、主显示纹理被清空后恢复、所有目标共享纹理、换图、重复隐藏、空路径、离树释放、原纹理保留、重新入树、多卡共享及直接销毁。新绑定额外验证 Sprite2D 与 TextureRect 混合目标。
- 初轮与最新完整运行都没有脚本错误；有相同的既有退出诊断：2 个 ObjectDB 实例及 1 个仍在使用的资源。运行器沿用仓库对“退出资源计数”错误的精确豁免，不宣称进程完全没有诊断。
- 快照与完整日志位于 `.godot/refactor_reuse_checks/{before,after}.{json,log}`，追加基线位于 `before-samuela_the_beyond.{json,log}`；before.json 当前是 35 项合并基线，before.log 保留初轮 34 项采集日志。均为本地临时文件；测试仅供本地验证，不提交，不代表已经接入 CI。重跑需要保留该隔离工程、35 项 items.json 与重构前快照。

## Limits / 边界

前两项重构没有导出真实 Release，也没有执行全角色战斗或多端联机回归；该阶段未实施商店购买提取。2026-10-20 第三项已另行完成并验证，见 `docs/SHOP_PURCHASE_REFACTOR.md`；第四项火/毒扩散生命周期已实现并验证，见 `docs/DIFFUSE_LIFECYCLE_REFACTOR.md`；第五项旧升级抽取清理已完成并验证，见 `docs/UPGRADE_LEGACY_CLEANUP.md`。GameEvents 和 ModManager 拆分仍未实施。工作区已有内容在 08:53:40 发生本轮操作之外的 Git reset；干净基线和改后验证均在这之后完成，没有恢复已被撤销的设置/本地化内容。
