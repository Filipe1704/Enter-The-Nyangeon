# Audit Fixes & Dedup Refactoring / 审计修复与去重重构

> 日期：2026-10-24。基线：`b0ef6d5`（上游同步后）+ 工作区在制品。对应 2026-10-24 全库 refactor 审计的前序可机械化项；暴击公式、腐化场口径、池化样板、DOT ticker、round_timer 状态机、GameEvents/ModManager 拆分等行为歧义或大型项未实施，见文末。

## Changes / 改动

### 功能性 bug（改变数值/显示行为）

- **AUD-BUG-001，已修复**：`script/PlayerData.gd` `_recompute_player_ability()` 内 11 处 `clamp(下界常量, 计算值, 上界)` 参数颠倒改回 `clamp(计算值, 下界, 上界)`（critical_luck/MAX_SPEED/max_hp/max_ammo/bullet_shoot_time/bullet_speed/bullet_damage/bullet_recoil/bullet_knockback/bullet_penetrate/bullet_arc/shake_mult）；满弧公式 `360 * (1 - 1/count)` 的 int/int 整除改 `1.0/count`。修复前上界全部不生效、多弹满弧恒 360°；修复后上限首次生效。
- **AUD-BUG-002，已修复**：同型 clamp 误用全局排查共 7 处一并修复：`script/EnemyStats.gd:168`、`scenes/bullet/mashiro_sniper_bullet.gd:193`、`scenes/enemies/tester_automaton_shield.gd:130`、`scenes/player/aris/GunOverheating.gd:47-48`、`scenes/update_item/spiked_shell.gd:51`、`ui/ability_upgrade_card.gd:56`。各处下界行为不变，仅上界开始生效。
- **AUD-BUG-003，已修复**：`ui/ability_shop_item_card.gd` 累计文案分支属性名 `"player_damage_daken"` 拼写改回 `"player_damage_taken"`（对照同文件单级分支与 `resources/equip/bag.tres`）；修复前装备累计文案永不渲染该属性。

### 死代码清理（零行为变化）

- 删除 `script/Game.gd`：无调用的 `get_window_size()`（活实现 `script/Window.gd`，注意其缺 `OS.has_feature("mobile")` 守卫，未改）、空壳 `_physics_process`、`size_x/size_y`、整段注释的 `get_files_by_extension`。
- 删除 `script/transition_manager.gd`（无任何引用）及 `script/GameEvents.gd` 的 `transition_start` 信号与 `emit_transition_start()`（无发射者）。
- 删除 `scenes/update_item/winnipesaukee_stone.gd` 无调用的 `bullet_damage_count()`、`scenes/field_mods/orbital_barrage.gd` 无调用的 `_clear_markers()`、`scenes/update_item/kitchen_knife.gd` `_on_equip` 中与成员默认值相同的冗余重设、`scenes/enemies/sandbag.gd` 注释旧状态机、`scenes/enemies/boss/goliath.gd` 注释行、整文件无引用的 `scenes/weapon/Supernova_The_Sword_of_Light/aris_bullet_draw.gd`。

### 重复代码去重（行为保持）

- **新增 `script/fire_field_base.gd`（`FireFieldBase`）**：`scenes/debuff/fire_field.gd` 与 `scenes/update_item/renge_fire_field.gd` 的公共生命周期（idle/active/time_count/hitbox 跟踪/DamageData 填充）上提；差异经钩子保留——`_field_lifetime()`（30 vs `life_ticks`）、`_damage_source()`（PS_DAMAGE vs EQUIP）、`_on_field_ready()`（fire_field 连 `round_end` 并立即激活）、`_on_field_expired()`（fire_field 到期先复位 `time_length=30`）、`_on_field_activated()`（fire_field 复位 `damage_count`）、`add_damage_data()` 各自实现。删除两边均无使用的 `signal is_end` 与 fire_field 无使用的 `add_end`。
- **`script/equip_item.gd` 的 `attach_follow_icon()` 返回类型 bool → Node（icon 或 null）**：现有调用者（mint_chocolate_parfait/tnt）不使用返回值。7 个手写挂点循环的道具改调基类入口：kikyou/renge/nagusa/yukari_doll（保留 `doll` 引用）、black/red_ninpero、cherino_matryoshka。手写版由此补上基类的联机 `is_ancestor_of` 守卫，且 kikyou/black/red/cherino 原缺 `break` 导致的重复挂载一并消除；各文件残留的 `group` 变量删除。
- **新增 `ui/ability_shop_card_base.gd`（`AbilityShopCardBase`，仿 ShopPurchaseCard 模式）**：`ui/ability_shop_item_card.gd` 与 `ui/ability_shop_ps_card.gd` 的公共 `_ready` 接线、mouse_in/out、touch_out、touch_button、mouse_selected、购买判定（`_attempt_purchase`：上限→coin_lack→扣款→`item_upgrade()`→`_on_purchased()`）与 smoke_anim/preview_from_navigation 上提；子类提供 `_upgrade_cap()`（20/3）、`_on_purchased()`（add_ability / emit_player_ps_upgrade）、`_tooltip_content()`、`reset_data()`、`_on_ready_extra()`。item 卡内 `text_show/text_hide` 与 mouse_in/out 逐行相同，直接复用。基类对 `item_upgrade()`/`reset_data()` 声明空桩（GDScript 硬错误要求，见 LEARNINGS）。
- **`ui/pause_screen.gd`**：`yes_mouse_selected` 触屏/shoot 两份逐行重复的退出判定合并为 `_confirm_quit()`；`on_endless` 两分支仅差 `player_dead`，合并为 `_game_over_close(player_dead)`；BGM/鼠标/hide/button_close/set_input_as_handled 关闭序列 4 处合并为 `_pause_close()`（`hide_pause_screen` 因升级页鼠标归属不同保持原样）。
- **新增 `script/hurtbox_measure.gd`（`HurtBoxMeasure.measure(body, fallback)` 静态工具）**：`scenes/debuff/shield_effect.gd` 与 `frenzy_effect.gd` 两份逐行重复的 `_hurt_box_bounds()` 收敛（采用 frenzy 侧多出的 `is_instance_valid` 防御）。
- **`scenes/manager/chip_manager.gd`**：`_load_selected_chip_modes()` 内嵌的 game_modes 查表循环改为复用 `_chip_mode_lookup()`。

## Validation / 验证

- 引擎：本地 Godot 4.7 stable Windows console，headless。
- `--headless --import` 全量重导入成功；随后探针脚本（`--script` 模式 `load()`）逐个加载本轮 33 个改动/相关脚本：0 失败；`AbilityShopCardBase` 两个子类 `new()` 实例化并验证 `_upgrade_cap()` 分派正确（20/3）。
- 改动前基线对比：`--headless --quit` 的 script/parse 错误数改动前后一致（13=13，均为缺 wav 与 MapChunk 全局类缓存的环境问题）；import 后同一检查归零。
- `git stash` 前后对比确认以上错误数与本轮改动无关。
- 本工作区不存在 `tests/run_refactor_reuse_checks.py` 等本地回归 runner 及其 `.godot` 基线，未运行数值快照回归；clamp 修复对属性数值的 observable 变化未做快照对比（见 Limits）。

## Limits / 边界

- clamp/上限修复**有意改变数值行为**（超上限属性首次被钳制、满弧多弹不再全圆），建议实机观察暴击率、速度/HP/弹速上限与多弹散射表现。
- 本轮未实施（需行为裁定或独立验证基建）：暴击判定+伤害公式 helper（各处乘数组合不同，需逐一甄别是否有意）；腐化场 `min_corruption` vs 硬编码 1 的口径统一；PoolManager `get_or_create`/飘字 helper；`enemy_buff_manager` 三个 DOT ticker 合并（火/毒/寒首跳时机 `<`/`>` 差异需先确认）；`round_timer.gd` 状态机收敛；GameEvents/ModManager 拆分（沿用既有关闭决定）；`Window.gd` 是否补 mobile 守卫；hujiu 残留分支清理。
- `attach_follow_icon` 的联机守卫对手写版是新增行为（单机无差异）； Follow 组遍历从"全部槽位"变为"拥有者第一个空闲槽位"，与 mint_chocolate_parfait/tnt 现行行为一致。
- `--import` 重导出了 4 个 `ETN_localization.*.translation`（旧二进制与当前 CSV 不同步，5631→11138 字节），属合法重导入产物，是否随本次提交由用户决定。
