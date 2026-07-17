# 文件名：DeployPreview.gd
# 作用：卡牌选中后，在鼠标位置显示部署预览。
#       非法位置（出界/贴近建筑）自动吸附到最近的合法格，预览始终跟随合法位置。
#       单位卡：根据 spawn_offsets 显式偏移或确定性圆形分布，显示每个单位的精确落点。
#       法术卡：显示法术半径圆（全图含河道均可施放）。
#       绿色 = 可部署，红色 = 不可部署（仅在极端无合法格时出现）。
# 挂载位置：BattleScene/World/DeployPreview
# 初学者阅读建议：先看 show_preview() 了解偏移怎么算，再看 _draw() 了解怎么画。

extends Node2D

## 是否处于激活状态（有卡牌被选中）
var _active: bool = false

## 每个单位相对于部署中心的偏移（World 本地游戏空间，像素）
var _offsets: Array = []

## 当前吸附后的格中心位置（World 本地游戏空间）
var _snapped_pos: Vector2 = Vector2.ZERO

## 当前位置是否在可部署区域内
var _valid: bool = false

## 是否是法术卡牌预览
var _is_spell: bool = false

## 法术半径（像素，仅法术卡有效）
var _spell_radius: float = 0.0

## 单位虚影帧纹理（仅单位卡有效，null 时退化为方块）
var _frame_texture: Texture2D = null
## 纹理缩放（含 Y_COMPRESS 反向补偿，与 SpriteAnimator 一致）
var _tex_scale: Vector2 = Vector2.ONE
## 纹理偏移（visual_offset，像素）
var _tex_offset: Vector2 = Vector2.ZERO

## 建筑攻击范围（像素，>0 时绘制射程预览圆）
var _attack_range: float = 0.0
## 建筑最小射程盲区（像素，>0 时射程圆中心掏空成环形，如迫击炮）
var _min_attack_range: float = 0.0

## 觉醒狙击弹扫描条带半宽（像素，>0 时绘制紫色扫描条，仅觉醒女枪用）
var _sniper_scan_half_width: float = 0.0

## 预览方块半边长（匹配 UnitBase body size 16px → 半边 8）
const PREVIEW_HALF := 8.0

## 法术中心十字瞄准标记颜色（范围圆样式统一由 RangeVfx.draw_gradient_ring 提供）
const RANGE_BORDER_COLOR := Color(1.0, 1.0, 1.0, 0.85)

## Arena 引用，用于校验部署位置
@onready var _arena: Node2D = get_node_or_null("../Arena")


## 设置当前选中的卡牌数据，计算预览内容并显示。
func show_preview(card_data: Dictionary, awakening_effects: Dictionary = {}) -> void:
	_is_spell = (card_data.get("card_type") == "spell")
	_attack_range = 0.0
	_min_attack_range = 0.0
	if _is_spell:
		_spell_radius = BattleConstants.px(float(card_data.get("spell_radius", 0)))
		_offsets = []
		_frame_texture = null
	else:
		var count := int(card_data.get("spawn_count", 1))
		var spread_px := BattleConstants.px(float(card_data.get("spawn_spread", 0.0)))
		var offsets_data = card_data.get("spawn_offsets", null)
		_offsets = SpawnManager.get_spawn_offsets(count, spread_px, offsets_data)
		_load_unit_texture(card_data)
		_load_building_range(card_data)
		_load_sniper_strip(card_data, awakening_effects)
	_active = true
	queue_redraw()


## 隐藏预览（取消选中或部署完成后调用）。
func hide_preview() -> void:
	_active = false
	_is_spell = false
	_frame_texture = null
	_attack_range = 0.0
	_min_attack_range = 0.0
	_sniper_scan_half_width = 0.0
	queue_redraw()


## 加载单位模型帧纹理用于拖动虚影显示。
## player 方部署朝向 back（向上走），降级查找 walk → idle 第一帧。
func _load_unit_texture(card_data: Dictionary) -> void:
	_frame_texture = null
	_tex_scale = Vector2.ONE
	_tex_offset = Vector2.ZERO
	var unit_id: String = card_data.get("unit_id", "")
	if unit_id.is_empty():
		return
	var unit_data: Dictionary = DataRegistry.get_unit_data(unit_id)
	var anim_cfg: Dictionary = unit_data.get("animation", {})
	if anim_cfg.is_empty():
		return
	var vs := SpriteRegistry.get_render_scale(float(anim_cfg.get("visual_scale", 1.0)))
	_tex_scale = Vector2(vs, vs / BattleConstants.Y_COMPRESS)
	_tex_offset = Vector2(
		float(anim_cfg.get("visual_offset_x", 0.0)),
		float(anim_cfg.get("visual_offset_y", 0.0))
	)
	# 预览始终以 player 方视角（自己部署），团队色单位取 player 帧绘制虚影
	var frames: SpriteFrames = SpriteRegistry.get_sprite_frames(unit_id, "player")
	if frames == null:
		return
	# player 方向上推进，优先 walk_back 第一帧
	for anim_name in ["walk_back", "walk_front", "walk", "idle_back", "idle_front", "idle"]:
		if frames.has_animation(anim_name) and frames.get_frame_count(anim_name) > 0:
			_frame_texture = frames.get_frame_texture(anim_name, 0)
			return


## 读取建筑单位（mass==0）的攻击范围，用于拖动预览显示射程圆。
## 迫击炮等带 min_attack_range 的单位会绘制中心掏空的环形。
func _load_building_range(card_data: Dictionary) -> void:
	var unit_id: String = card_data.get("unit_id", "")
	if unit_id.is_empty():
		return
	var u_data: Dictionary = DataRegistry.get_unit_data(unit_id)
	if int(u_data.get("mass", 1)) != 0:
		return  # 非建筑单位（可移动）不显示射程预览
	var attacks: Array = u_data.get("attacks", [])
	if attacks.is_empty():
		return
	_attack_range = BattleConstants.px(float(attacks[0].get("attack_range", 0.0)))
	_min_attack_range = BattleConstants.px(float(attacks[0].get("min_attack_range", 0.0)))


## 检测当前这次部署是否为觉醒狙击版，设置扫描条带宽度。
## awakening_effects 由 AwakeningTracker.peek_next_effects() 提供；保留 trigger_count=0
## 的数据回退，兼容其他直接调用 show_preview() 的场景。
func _load_sniper_strip(card_data: Dictionary, awakening_effects: Dictionary = {}) -> void:
	_sniper_scan_half_width = 0.0
	var effects: Dictionary = awakening_effects
	if effects.is_empty():
		var aw: Dictionary = card_data.get("awakening", {})
		if aw.is_empty() or int(aw.get("trigger_count", 1)) > 0:
			return
		effects = aw.get("effects", {})
	if not effects.has("sniper_shots"):
		return
	_sniper_scan_half_width = BattleConstants.px(
		float(effects["sniper_shots"].get("scan_half_width", 1.0))
	)


func _process(_delta: float) -> void:
	if not _active:
		return
	if _arena == null:
		return
	# 鼠标位置吸附到最近合法格中心。
	# 遇到非法位置（出界 / 贴近建筑）时自动锁定到最近的可释放格，预览始终跟随合法位置。
	# Client 端画面 180 度镜像：视觉坐标先逆镜像成逻辑坐标做部署校验，
	# 再镜像回视觉坐标显示，让预览出现在玩家点击的屏幕位置。
	var raw_pos := get_local_mouse_position()
	var team: String = NetworkManager.local_team() if NetworkManager.is_networked() else "player"
	if NetworkManager.should_mirror_view():
		var logic_pos := BattleConstants.mirror(raw_pos)
		var logic_snapped: Vector2 = _arena.find_nearest_valid_deploy(logic_pos, _is_spell, team)
		_snapped_pos = BattleConstants.mirror(logic_snapped)
		_valid = _arena.is_cell_deployable(logic_snapped, _is_spell, team)
	else:
		_snapped_pos = _arena.find_nearest_valid_deploy(raw_pos, _is_spell, team)
		_valid = _arena.is_cell_deployable(_snapped_pos, _is_spell, team)
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	var border_color := Color(0.3, 0.85, 0.3) if _valid else Color(0.9, 0.25, 0.2)

	if _is_spell:
		# 法术范围圆：白圈边框 + 浅白填充（与建筑射程预览统一样式）
		_draw_range_circle(_snapped_pos, _spell_radius, 0.0)
		# 中心十字瞄准标记
		draw_line(_snapped_pos - Vector2(6, 0), _snapped_pos + Vector2(6, 0), RANGE_BORDER_COLOR, 1.0)
		draw_line(_snapped_pos - Vector2(0, 6), _snapped_pos + Vector2(0, 6), RANGE_BORDER_COLOR, 1.0)
	else:
		# 建筑单位：先画攻击范围圆（min_attack_range>0 时中心掏空成环形）
		if _attack_range > 0.0:
			_draw_range_circle(_snapped_pos, _attack_range, _min_attack_range)
		# 觉醒狙击弹扫描条带（紫色光晕，从部署位延伸到对方底边）
		if _sniper_scan_half_width > 0.0:
			_draw_sniper_strip(_snapped_pos)
		# 单位虚影：优先显示模型纹理（半透明），无纹理时退化为白色方块
		for offset in _offsets:
			var pos: Vector2 = _snapped_pos + offset
			if _frame_texture:
				# 绘制半透明单位模型（只加透明度不变暗）
				var tex_size := _frame_texture.get_size()
				var scaled_size := tex_size * _tex_scale
				var draw_pos := pos + _tex_offset
				var tex_rect := Rect2(draw_pos - scaled_size / 2.0, scaled_size)
				draw_texture_rect(_frame_texture, tex_rect, false, Color(1.0, 1.0, 1.0, 0.5))
			else:
				# 无动画配置的单位退化为半透明白色方块
				var fill_rect := Rect2(pos.x - PREVIEW_HALF, pos.y - PREVIEW_HALF, PREVIEW_HALF * 2, PREVIEW_HALF * 2)
				draw_rect(fill_rect, Color(1.0, 1.0, 1.0, 0.35), true)
			# 碰撞体边框始终显示（绿=可部署 / 红=不可部署）
			var border_rect := Rect2(pos.x - PREVIEW_HALF, pos.y - PREVIEW_HALF, PREVIEW_HALF * 2, PREVIEW_HALF * 2)
			draw_rect(border_rect, border_color, false, 1.5)


## 绘制范围圆/环（统一白色渐变环样式，由 RangeVfx 提供）。
## inner_radius>0 时额外画迫击炮盲区内圈边界（简单白线标记）。
func _draw_range_circle(center: Vector2, outer_radius: float, inner_radius: float) -> void:
	if outer_radius <= 0.0:
		return
	# 外圈：白色渐变环
	RangeVfx.draw_gradient_ring(self, center, outer_radius, RangeVfx.COLOR_PREVIEW)
	# 迫击炮盲区内圈边界标记
	if inner_radius > 0.0:
		draw_arc(center, inner_radius, 0, TAU, 64, RANGE_BORDER_COLOR, 1.5)


## 绘制觉醒狙击弹扫描条带：浅紫色光晕，从部署位正前方延伸到对方底边。
## 宽度 = scan_half_width × 2（左右各半宽）。不画精确边界，用渐变光晕表示扫描区。
func _draw_sniper_strip(pos: Vector2) -> void:
	var half_w := _sniper_scan_half_width
	# 玩家始终在屏幕下方，扫描条向上（-Y）延伸到竞技场顶边 y=0
	var end_y := 0.0
	var strip_top := end_y
	var strip_bottom := pos.y
	var strip_h := strip_bottom - strip_top
	var center_x := pos.x
	# 三层渐变填充：外层最宽最淡 → 中层 → 内层最窄最亮，模拟光晕扩散
	# 外光晕（1.8x 宽，极淡）
	var outer_rect := Rect2(center_x - half_w * 1.8, strip_top, half_w * 3.6, strip_h)
	draw_rect(outer_rect, Color(0.65, 0.35, 0.9, 0.06), true)
	# 中层（1.3x 宽，稍浓）
	var mid_rect := Rect2(center_x - half_w * 1.3, strip_top, half_w * 2.6, strip_h)
	draw_rect(mid_rect, Color(0.7, 0.4, 0.95, 0.10), true)
	# 核心带（原始宽度，最浓）
	var core_rect := Rect2(center_x - half_w, strip_top, half_w * 2.0, strip_h)
	draw_rect(core_rect, Color(0.75, 0.45, 1.0, 0.15), true)
	# 左右边线（淡紫虚线感）
	var line_color := Color(0.8, 0.5, 1.0, 0.35)
	draw_line(Vector2(center_x - half_w, strip_top), Vector2(center_x - half_w, strip_bottom), line_color, 1.0)
	draw_line(Vector2(center_x + half_w, strip_top), Vector2(center_x + half_w, strip_bottom), line_color, 1.0)
