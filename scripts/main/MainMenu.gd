## 菜单保持参考图的原始版式；只有热区和卡组卡面覆盖在素材之上。
extends Control

const LOBBY_TEXTURE := preload("res://assets/ui/menu/lobby_reference.png")
const DECK_TEXTURE := preload("res://assets/ui/menu/deck_reference.png")
const LOADING_TEXTURE := preload("res://assets/ui/menu/battle_loading.jpg")
## 与 deck_reference.png 中 1-5 号卡组按钮逐一对齐的热区。
const PRESET_BUTTON_AREAS := [
	Rect2(0.185, 0.257, 0.110, 0.054),
	Rect2(0.314, 0.257, 0.111, 0.054),
	Rect2(0.443, 0.257, 0.111, 0.054),
	Rect2(0.577, 0.257, 0.110, 0.054),
	Rect2(0.707, 0.257, 0.111, 0.054),
]
const MIN_LOADING_VISIBLE_SECONDS := 0.6
const MAX_CONCURRENT_LOADS := 2

enum Page { LOBBY, DECK }
enum OnlineChoice { SOLO, HOST, JOIN }

var _page: Page = Page.LOBBY
var _selected_preset := 0
var _loading := false
var _room_mode: OnlineChoice = OnlineChoice.SOLO
var _found_hosts: Array[String] = []

var _background: TextureRect
var _lobby_layer: Control
var _deck_layer: Control
var _selected_marker: Panel
var _card_layer: Control
var _settings: Control
var _room_overlay: Control
var _room_status: Label
var _host_picker: OptionButton
var _ip_input: LineEdit
var _room_action: Button
var _loading_overlay: Control
var _loading_text: Label
var _loading_progress: ProgressBar
var _mode_select: OptionButton
var _online_select: OptionButton
# ---- 自由组卡层 ----
var _builder_layer: Control
var _builder_grid: Control
var _builder_count: Label
var _builder_confirm: Button
var _builder_frames: Dictionary = {}  # card_id -> 选中金色边框 Panel
var _builder_card_nodes: Dictionary = {}  # card_id -> {tex, btn} 冲突视觉更新用
var _builder_selection: Array = []    # 已选 card_id 列表
const BUILDER_COLS: int = 4
const BUILDER_CARD_W: float = 92.0
const BUILDER_CARD_H: float = 92.0
const BUILDER_MARGIN_X: float = 12.0
const BUILDER_START_Y: float = 108.0
const BUILDER_STEP_X: float = 107.0
const BUILDER_STEP_Y: float = 94.0


func _ready() -> void:
	# menu BGM 原配置为空；现在播放新增的官方大厅音乐。
	AudioManager.play_bgm("menu")
	_selected_preset = Game.selected_deck_index
	_build_base()
	_build_lobby_layer()
	_build_deck_layer()
	_build_settings()
	_build_room_overlay()
	_build_loading_overlay()
	_build_deck_builder()
	_show_page(Page.LOBBY)
	NetworkManager.connected_to_server.connect(_on_connected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.host_discovered.connect(_on_host_discovered)
	NetworkManager.web_match_ready.connect(_on_web_match_ready)


func _build_base() -> void:
	_background = TextureRect.new()
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_SCALE
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)


func _build_lobby_layer() -> void:
	_lobby_layer = _full_layer()
	add_child(_lobby_layer)
	# 与原图齿轮、Battle、Deck、Battle 底栏严格重合的透明热区。
	_add_hotspot(_lobby_layer, Rect2(0.83, 0.025, 0.14, 0.075), _open_settings, "设置")
	_add_hotspot(_lobby_layer, Rect2(0.25, 0.655, 0.51, 0.145), _on_battle_pressed, "开始对战")
	_add_hotspot(_lobby_layer, Rect2(0.03, 0.855, 0.45, 0.145), _show_page.bind(Page.DECK), "卡组")
	_add_hotspot(_lobby_layer, Rect2(0.48, 0.855, 0.49, 0.145), _on_battle_pressed, "对战")


func _build_deck_layer() -> void:
	_deck_layer = _full_layer()
	add_child(_deck_layer)
	for index in range(5):
		_add_hotspot(_deck_layer, PRESET_BUTTON_AREAS[index], _select_preset.bind(index), "预设 %d" % (index + 1))
	_card_layer = _full_layer()
	_deck_layer.add_child(_card_layer)
	_add_hotspot(_deck_layer, Rect2(0.04, 0.855, 0.45, 0.145), _show_page.bind(Page.DECK), "卡组")
	_add_hotspot(_deck_layer, Rect2(0.50, 0.855, 0.46, 0.145), _show_page.bind(Page.LOBBY), "大厅")
	# 自由组卡入口
	var builder_btn := Button.new()
	builder_btn.text = "✎ 自由组卡"
	builder_btn.position = Vector2(150, 8)
	builder_btn.size = Vector2(140, 30)
	builder_btn.add_theme_font_size_override("font_size", 16)
	builder_btn.pressed.connect(_open_deck_builder)
	_deck_layer.add_child(builder_btn)


func _build_settings() -> void:
	_settings = _full_layer()
	_settings.visible = false
	add_child(_settings)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color("#071426dc")
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings.add_child(shade)
	var panel := Panel.new()
	panel.position = Vector2(31, 150)
	panel.size = Vector2(378, 450)
	panel.add_theme_stylebox_override("panel", _panel_style(Color("#173a68"), 20, Color("#80d7ff"), 3))
	_settings.add_child(panel)
	var title := _label("对局设置", 27, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	title.position = Vector2(20, 20)
	title.size = Vector2(338, 42)
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_color_override("font_outline_color", Color("#15253e"))
	panel.add_child(title)
	panel.add_child(_positioned_label("对局模式", Vector2(30, 79), Vector2(300, 25)))
	_mode_select = OptionButton.new()
	_mode_select.position = Vector2(30, 105)
	_mode_select.size = Vector2(318, 43)
	_mode_select.add_item("7× 圣水模式（极速）", Game.MatchMode.FAST_7X)
	_mode_select.add_item("经典 1v1（官方倍率）", Game.MatchMode.CLASSIC_1V1)
	_mode_select.selected = Game.match_mode
	_style_option(_mode_select)
	panel.add_child(_mode_select)
	panel.add_child(_positioned_label("对手与联机方式", Vector2(30, 170), Vector2(300, 25)))
	_online_select = OptionButton.new()
	_online_select.position = Vector2(30, 196)
	_online_select.size = Vector2(318, 43)
	_online_select.add_item("单机 · 对战 AI", OnlineChoice.SOLO)
	_online_select.add_item("局域网 · 创建房间", OnlineChoice.HOST)
	_online_select.add_item("局域网 · 加入房间", OnlineChoice.JOIN)
	_style_option(_online_select)
	panel.add_child(_online_select)
	var hint := _label("双方会在进入对局前锁定各自选中的预设卡组。", 13, Color("#d0ecff"), HORIZONTAL_ALIGNMENT_CENTER)
	hint.position = Vector2(25, 263)
	hint.size = Vector2(328, 44)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(hint)
	var save := _styled_button("保存并返回大厅", Vector2(318, 50), Color("#b97208"), Color("#f7bf32"))
	save.position = Vector2(30, 337)
	save.pressed.connect(_apply_settings)
	panel.add_child(save)
	var close := _styled_button("取消", Vector2(318, 35), Color("#305c8e"), Color("#39a8f2"))
	close.position = Vector2(30, 397)
	close.pressed.connect(func(): _settings.visible = false)
	panel.add_child(close)


func _build_room_overlay() -> void:
	_room_overlay = _full_layer()
	_room_overlay.visible = false
	add_child(_room_overlay)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color("#071426df")
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_room_overlay.add_child(shade)
	var panel := Panel.new()
	panel.position = Vector2(25, 171)
	panel.size = Vector2(390, 390)
	panel.add_theme_stylebox_override("panel", _panel_style(Color("#173a68"), 20, Color("#80d7ff"), 3))
	_room_overlay.add_child(panel)
	var title := _label("局域网对战", 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	title.position = Vector2(24, 20)
	title.size = Vector2(342, 38)
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_color_override("font_outline_color", Color("#15253e"))
	panel.add_child(title)
	_room_status = _label("", 14, Color("#d5efff"), HORIZONTAL_ALIGNMENT_CENTER)
	_room_status.position = Vector2(28, 68)
	_room_status.size = Vector2(334, 86)
	_room_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_room_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(_room_status)
	_host_picker = OptionButton.new()
	_host_picker.position = Vector2(32, 164)
	_host_picker.size = Vector2(326, 40)
	_host_picker.visible = false
	_style_option(_host_picker)
	_host_picker.item_selected.connect(_pick_host)
	panel.add_child(_host_picker)
	_ip_input = LineEdit.new()
	_ip_input.position = Vector2(32, 214)
	_ip_input.size = Vector2(326, 39)
	_ip_input.placeholder_text = "或输入主机 IP，例如 192.168.1.100"
	_ip_input.visible = false
	_ip_input.add_theme_stylebox_override("normal", _panel_style(Color("#0c2343"), 10, Color("#77cef8"), 2))
	panel.add_child(_ip_input)
	_room_action = _styled_button("", Vector2(326, 50), Color("#b97208"), Color("#f7bf32"))
	_room_action.position = Vector2(32, 276)
	_room_action.pressed.connect(_on_room_action)
	panel.add_child(_room_action)
	var back := _styled_button("返回大厅", Vector2(326, 35), Color("#305c8e"), Color("#39a8f2"))
	back.position = Vector2(32, 335)
	back.pressed.connect(_close_room_overlay)
	panel.add_child(back)


func _build_loading_overlay() -> void:
	_loading_overlay = _full_layer()
	_loading_overlay.visible = false
	add_child(_loading_overlay)
	var image := TextureRect.new()
	image.texture = LOADING_TEXTURE
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_loading_overlay.add_child(image)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color("#05112670")
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_loading_overlay.add_child(shade)
	_loading_text = _label("正在准备战斗资源…", 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_loading_text.position = Vector2(20, 610)
	_loading_text.size = Vector2(400, 48)
	_loading_text.add_theme_constant_override("outline_size", 7)
	_loading_text.add_theme_color_override("font_outline_color", Color("#15253e"))
	_loading_overlay.add_child(_loading_text)
	_loading_progress = ProgressBar.new()
	_loading_progress.position = Vector2(55, 665)
	_loading_progress.size = Vector2(330, 18)
	_loading_progress.min_value = 0.0
	_loading_progress.max_value = 100.0
	_loading_progress.value = 0.0
	_loading_progress.show_percentage = false
	_loading_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_progress.add_theme_stylebox_override("background", _panel_style(Color("#071426cc"), 9, Color("#d8f3ff"), 2))
	_loading_progress.add_theme_stylebox_override("fill", _panel_style(Color("#35b8ff"), 9))
	_loading_overlay.add_child(_loading_progress)


func _show_page(page: Page) -> void:
	_page = page
	_background.texture = LOBBY_TEXTURE if page == Page.LOBBY else DECK_TEXTURE
	_lobby_layer.visible = page == Page.LOBBY
	_deck_layer.visible = page == Page.DECK
	if page == Page.DECK:
		_refresh_deck_cards()


func _select_preset(index: int) -> void:
	_selected_preset = index
	Game.set_selected_deck(index)
	_refresh_deck_cards()


func _refresh_deck_cards() -> void:
	for child in _card_layer.get_children():
		child.queue_free()
	var cards: Array = Game.get_selected_deck()  # 自动返回自定义卡组或当前预设
	for index in range(cards.size()):
		var image := TextureRect.new()
		var x := 0.077 + (index % 4) * 0.220
		var y := 0.414 + (index / 4) * 0.174
		image.set_anchors_preset(Control.PRESET_TOP_LEFT)
		image.anchor_left = x
		image.anchor_right = x + 0.180
		image.anchor_top = y
		image.anchor_bottom = y + 0.145
		image.offset_left = 0
		image.offset_right = 0
		image.offset_top = 0
		image.offset_bottom = 0
		image.texture = _card_texture(str(cards[index]))
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_card_layer.add_child(image)
	# 选中态使用 Panel 而非 Button，避免字体的最小尺寸把高亮框撑出底图按钮。
	if _selected_marker and is_instance_valid(_selected_marker):
		_selected_marker.queue_free()
	var selected_area: Rect2 = PRESET_BUTTON_AREAS[_selected_preset]
	_selected_marker = Panel.new()
	_selected_marker.add_theme_stylebox_override("panel", _panel_style(Color("#c98208e8"), 12, Color("#ffd24b"), 2))
	_selected_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selected_marker.anchor_left = selected_area.position.x
	_selected_marker.anchor_right = selected_area.end.x
	_selected_marker.anchor_top = selected_area.position.y
	_selected_marker.anchor_bottom = selected_area.end.y
	var selected_label := _label(str(_selected_preset + 1), 25, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	selected_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	selected_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selected_label.add_theme_constant_override("outline_size", 3)
	selected_label.add_theme_color_override("font_outline_color", Color("#8a5100"))
	_selected_marker.add_child(selected_label)
	_deck_layer.add_child(_selected_marker)


func _on_battle_pressed() -> void:
	Game.set_selected_deck(_selected_preset)
	match _online_select.selected:
		OnlineChoice.SOLO:
			NetworkManager.leave()
			Game.set_network_mode(false)
			Game.prepare_battle_decks(Game.get_selected_deck(), DataRegistry.get_default_enemy_deck())
			_begin_loading()
		OnlineChoice.HOST:
			_open_host_room()
		OnlineChoice.JOIN:
			_open_join_room()


func _open_settings() -> void:
	_settings.visible = true


func _apply_settings() -> void:
	Game.set_match_mode(_mode_select.get_selected_id())
	_settings.visible = false


func _open_host_room() -> void:
	if OS.has_feature("web"):
		_open_web_room()
		return
	Game.set_match_mode(_mode_select.get_selected_id())
	Game.set_network_mode(true)
	Game.set_remote_deck([])
	var err := NetworkManager.host_game()
	if err != OK:
		Game.set_network_mode(false)
		return
	_room_mode = OnlineChoice.HOST
	_room_overlay.visible = true
	_host_picker.visible = false
	_ip_input.visible = false
	_room_action.text = "等待对手加入…"
	_room_action.disabled = true
	_room_status.text = "房间已创建。把你的 IP 告诉好友：\n\n%s\n端口：%d" % [_local_ips(), NetworkManager.DEFAULT_PORT]


func _open_join_room() -> void:
	if OS.has_feature("web"):
		_open_web_room()
		return
	_room_mode = OnlineChoice.JOIN
	_room_overlay.visible = true
	_host_picker.visible = true
	_ip_input.visible = true
	_host_picker.clear()
	_host_picker.add_item("扫描局域网房间…")
	_ip_input.text = ""
	_room_action.text = "连接房间"
	_room_action.disabled = false
	_room_status.text = "选择扫描到的房间，或输入好友的局域网 IP。"
	_found_hosts.clear()
	NetworkManager.start_scanning()


func _open_web_room() -> void:
	_room_mode = OnlineChoice.JOIN
	_room_overlay.visible = true
	_host_picker.visible = false
	_ip_input.visible = true
	_ip_input.placeholder_text = "wss://你的专服地址"
	_room_action.text = "连接在线服务器"
	_room_action.disabled = false
	_room_status.text = "网页版需要连接专用服务器。两名玩家填入同一个 wss:// 地址后会自动配对。"


func _on_room_action() -> void:
	if _room_mode != OnlineChoice.JOIN:
		return
	var ip := _ip_input.text.strip_edges()
	if OS.has_feature("web"):
		if ip.is_empty():
			_room_status.text = "请输入 WebSocket 服务器地址（wss://...）。"
			return
		Game.set_match_mode(_mode_select.get_selected_id())
		Game.set_network_mode(true)
		if NetworkManager.join_web_game(ip) != OK:
			Game.set_network_mode(false)
			_room_status.text = "无法连接在线服务器，请检查 wss:// 地址。"
			return
		_room_status.text = "正在连接在线服务器…"
		_room_action.disabled = true
		return
	if ip.is_empty() and not _found_hosts.is_empty():
		ip = _found_hosts[0]
	if ip.is_empty():
		_room_status.text = "尚未找到房间，请稍候扫描或输入 IP。"
		return
	Game.set_match_mode(_mode_select.get_selected_id())
	Game.set_network_mode(true)
	NetworkManager.stop_scanning()
	if NetworkManager.join_game(ip) != OK:
		Game.set_network_mode(false)
		_room_status.text = "无法连接，请检查 IP 后重试。"
		return
	_room_status.text = "正在连接 %s…" % ip
	_room_action.disabled = true


func _close_room_overlay() -> void:
	NetworkManager.stop_scanning()
	NetworkManager.leave()
	Game.set_network_mode(false)
	_room_overlay.visible = false


func _pick_host(index: int) -> void:
	if index >= 0 and index < _found_hosts.size():
		_ip_input.text = _found_hosts[index]


func _on_host_discovered(ip: String) -> void:
	if not _room_overlay.visible or _room_mode != OnlineChoice.JOIN or ip in _found_hosts:
		return
	_found_hosts.append(ip)
	_host_picker.clear()
	for host_ip in _found_hosts:
		_host_picker.add_item("发现房间：" + host_ip)


func _on_connected() -> void:
	NetworkManager.stop_scanning()
	if NetworkManager.is_web_transport() and not NetworkManager.is_server():
		NetworkManager.submit_web_lobby_deck(Game.get_selected_deck(), _mode_select.get_selected_id())
		_room_status.text = "已连接，正在等待另一名玩家加入…"
		return
	if NetworkManager.is_client():
		_rpc_submit_lobby_deck.rpc_id(1, Game.get_selected_deck())
		_room_status.text = "已连接，正在等待主机锁定本局牌序…"
	elif NetworkManager.is_server():
		_room_status.text = "对手已连接，正在同步双方卡组…"


func _on_web_match_ready(_player_order: Array, _enemy_order: Array, _team: String, _mode: int) -> void:
	if not _room_overlay.visible:
		return
	_room_status.text = "匹配成功，正在加载战斗…"
	_begin_loading()


func _on_connection_failed() -> void:
	Game.set_network_mode(false)
	if _room_overlay.visible:
		_room_status.text = "连接失败，请确认双方在同一局域网并检查 IP。"
		_room_action.disabled = false
		NetworkManager.start_scanning()


func _on_server_disconnected() -> void:
	Game.set_network_mode(false)
	_room_overlay.visible = false


func _begin_loading() -> void:
	if _loading:
		return
	# 后续 BattleScene 的就绪握手通过常驻 NetworkManager 完成；新局开始前必须清空上一局状态。
	if NetworkManager.is_networked():
		NetworkManager.reset_battle_scene_readiness()
	_loading = true
	_settings.visible = false
	_room_overlay.visible = false
	_loading_overlay.visible = true
	_loading_text.text = "正在准备战斗资源… 0%"
	_loading_progress.value = 0.0
	_load_battle_resources()


## 真实加载流程：后台并发读取战斗场景、双方初始手牌帧、卡面和塔贴图；完成后才切场景。
func _load_battle_resources() -> void:
	var started_msec := Time.get_ticks_msec()
	var manifest: Array[String] = []
	var manifest_seen: Dictionary = {}
	var frame_sets: Array[Dictionary] = []
	var frame_set_seen: Dictionary = {}
	_add_loading_path(SceneLoader.BATTLE_SCENE_PATH, manifest, manifest_seen)

	var player_order := Game.get_prepared_player_deck()
	var enemy_order := Game.get_prepared_enemy_deck()
	# Client 视角会在战斗中翻转阵营：自己的牌是蓝方 player，Host 的牌是红方 enemy。
	if NetworkManager.is_networked_client():
		var host_order := player_order
		player_order = enemy_order
		enemy_order = host_order
	var player_cards := _initial_hand_cards(player_order)
	var enemy_cards := _initial_hand_cards(enemy_order)
	# 卡面很小，加载页直接覆盖整副卡组；这样战斗内新预告牌刷新 UI 时不会再同步读图。
	_collect_card_icons(player_order, manifest, manifest_seen)
	_collect_card_icons(enemy_order, manifest, manifest_seen)
	_collect_card_art(player_cards, "player", manifest, manifest_seen, frame_sets, frame_set_seen)
	_collect_card_art(enemy_cards, "enemy", manifest, manifest_seen, frame_sets, frame_set_seen)

	# 皇家塔贴图和塔顶公主由数据动态加载，不属于 BattleScene 的静态依赖，必须显式加入清单。
	_queue_unit_frame_set("princess", "player", manifest, manifest_seen, frame_sets, frame_set_seen)
	_queue_unit_frame_set("princess", "enemy", manifest, manifest_seen, frame_sets, frame_set_seen)
	for tower_key in ["guard_tower", "king_tower"]:
		var tower_data := DataRegistry.get_tower_data(tower_key)
		var sprite_data: Dictionary = tower_data.get("sprite", {})
		_add_loading_path(sprite_data.get("player_texture", ""), manifest, manifest_seen)
		_add_loading_path(sprite_data.get("enemy_texture", ""), manifest, manifest_seen)

	var pending: Dictionary = {}
	var next_index := 0
	var completed := 0
	var failed := 0
	var battle_scene: PackedScene = null
	while completed + failed < manifest.size():
		while pending.size() < MAX_CONCURRENT_LOADS and next_index < manifest.size():
			var path := manifest[next_index]
			next_index += 1
			if SpriteRegistry.has_preloaded_resource(path) or ResourceLoader.has_cached(path):
				var cached := load(path)
				if cached is Resource:
					SpriteRegistry.retain_preloaded_resource(path, cached)
				if path == SceneLoader.BATTLE_SCENE_PATH and cached is PackedScene:
					battle_scene = cached
				completed += 1
				continue
			var err := ResourceLoader.load_threaded_request(path, "", true)
			if err == OK or err == ERR_BUSY:
				pending[path] = 0.0
			else:
				push_warning("[MainMenu] 预加载请求失败: %s (%d)" % [path, err])
				failed += 1

		# 每帧最多收取一个完成资源，避免集中完成时再次造成主线程尖峰。
		for path in pending.keys():
			var item_progress: Array = []
			var status := ResourceLoader.load_threaded_get_status(path, item_progress)
			pending[path] = float(item_progress[0]) if not item_progress.is_empty() else 0.0
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				var resource := ResourceLoader.load_threaded_get(path)
				if resource is Resource:
					SpriteRegistry.retain_preloaded_resource(path, resource)
				if path == SceneLoader.BATTLE_SCENE_PATH and resource is PackedScene:
					battle_scene = resource
				pending.erase(path)
				completed += 1
				break
			elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				push_warning("[MainMenu] 预加载失败: " + path)
				pending.erase(path)
				failed += 1
				break

		var partial := 0.0
		for value in pending.values():
			partial += float(value)
		var progress := float(completed + failed) + partial
		_set_loading_progress(progress / maxf(float(manifest.size()), 1.0))
		await get_tree().process_frame

	_loading_text.text = "正在整理单位动画…"
	for frame_set in frame_sets:
		SpriteRegistry.get_sprite_frames(frame_set["unit_id"], frame_set["team"])
	_set_loading_progress(1.0)

	var elapsed := (Time.get_ticks_msec() - started_msec) / 1000.0
	print("[MainMenu] 战斗资源预加载完成: %d 项, 失败 %d 项, %.0f ms" % [
		manifest.size(), failed, elapsed * 1000.0,
	])
	var remaining := MIN_LOADING_VISIBLE_SECONDS - elapsed
	if remaining > 0.0:
		await get_tree().create_timer(remaining).timeout
	if is_instance_valid(self):
		Game.start_battle(battle_scene)


## 按 DeckManager 的规则推导真正的初始 4 手牌 + 1 张预告牌。
## 预告牌会在首次出牌后立即补位，7× 模式下也必须在对局前完成加载。
func _initial_hand_cards(deck_order: Array) -> Array:
	var hand: Array = []
	for card_id in deck_order:
		var card: Dictionary = DataRegistry.card_data.get(card_id, {})
		if hand.size() < DeckManager.HAND_SIZE and not bool(card.get("exclude_from_initial_hand", false)):
			hand.append(card_id)
	for card_id in deck_order:
		if not hand.has(card_id):
			hand.append(card_id)
			break
	return hand


func _collect_card_art(cards: Array, team: String, manifest: Array[String], manifest_seen: Dictionary,
		frame_sets: Array[Dictionary], frame_set_seen: Dictionary) -> void:
	for card_id in cards:
		var card := DataRegistry.get_card_data(card_id)
		var unit_id: String = card.get("unit_id", "")
		if unit_id != "":
			_queue_unit_frame_set(unit_id, team, manifest, manifest_seen, frame_sets, frame_set_seen)


func _collect_card_icons(cards: Array, manifest: Array[String], manifest_seen: Dictionary) -> void:
	for card_id in cards:
		var card := DataRegistry.get_card_data(card_id)
		_add_loading_path(card.get("icon", ""), manifest, manifest_seen)
		_add_loading_path(card.get("awakening_icon", ""), manifest, manifest_seen)


func _queue_unit_frame_set(unit_id: String, team: String, manifest: Array[String], manifest_seen: Dictionary,
		frame_sets: Array[Dictionary], frame_set_seen: Dictionary) -> void:
	var key := unit_id + ":" + team
	if frame_set_seen.has(key):
		return
	frame_set_seen[key] = true
	frame_sets.append({"unit_id": unit_id, "team": team})
	for path in SpriteRegistry.get_texture_paths(unit_id, team):
		_add_loading_path(path, manifest, manifest_seen)


func _add_loading_path(path: String, manifest: Array[String], seen: Dictionary) -> void:
	if path == "" or seen.has(path) or not ResourceLoader.exists(path):
		return
	seen[path] = true
	manifest.append(path)


func _set_loading_progress(ratio: float) -> void:
	var clamped := clampf(ratio, 0.0, 1.0)
	_loading_progress.value = clamped * 100.0
	_loading_text.text = "正在加载战斗资源… %d%%" % roundi(clamped * 100.0)


## 在大厅场景完成卡组锁定，避免两端加载速度不同导致远端手牌被默认值覆盖。
@rpc("any_peer", "call_remote", "reliable")
func _rpc_submit_lobby_deck(cards: Array) -> void:
	if not NetworkManager.is_server():
		return
	var validated: Array = []
	for card_id in cards:
		if card_id is String and not DataRegistry.get_card_data(card_id).is_empty():
			validated.append(card_id)
	if validated.size() >= 5:
		Game.set_remote_deck(validated)
		Game.prepare_battle_decks(Game.get_selected_deck(), validated)
		var peer_id := multiplayer.get_remote_sender_id()
		_rpc_receive_prepared_decks.rpc_id(
			peer_id,
			Game.get_prepared_player_deck(),
			Game.get_prepared_enemy_deck()
		)
		_begin_loading()


## Host 把唯一的本局牌序发给 Client，双方据此加载完全相同的首发美术资源。
@rpc("authority", "call_remote", "reliable")
func _rpc_receive_prepared_decks(player_order: Array, enemy_order: Array) -> void:
	if NetworkManager.is_server():
		return
	Game.set_remote_deck(player_order)
	Game.set_prepared_battle_decks(player_order, enemy_order)
	_begin_loading()


func _full_layer() -> Control:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return layer


func _add_hotspot(parent: Control, area: Rect2, callback: Callable, tooltip: String) -> Button:
	var button := Button.new()
	button.flat = true
	button.text = ""
	button.tooltip_text = tooltip
	button.anchor_left = area.position.x
	button.anchor_top = area.position.y
	button.anchor_right = area.end.x
	button.anchor_bottom = area.end.y
	button.offset_left = 0
	button.offset_top = 0
	button.offset_right = 0
	button.offset_bottom = 0
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _card_texture(card_id: String) -> Texture2D:
	var asset_id := card_id.replace("card_", "")
	var path := "res://assets/ui/cards/%s.png" % asset_id
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func _local_ips() -> String:
	var addresses := NetworkManager.get_local_addresses()
	return " / ".join(addresses) if not addresses.is_empty() else "未检测到局域网 IP"


func _label(value: String, font_size: int, color: Color, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _positioned_label(value: String, position_value: Vector2, size_value: Vector2) -> Label:
	var label := _label(value, 15, Color("#c8e9ff"))
	label.position = position_value
	label.size = size_value
	return label


func _styled_button(value: String, button_size: Vector2, fill: Color, border: Color) -> Button:
	var button := Button.new()
	button.text = value
	button.size = button_size
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _panel_style(fill, 12, border, 2))
	button.add_theme_stylebox_override("hover", _panel_style(fill.lightened(0.12), 12, Color.WHITE, 2))
	button.add_theme_stylebox_override("pressed", _panel_style(fill.darkened(0.12), 12, border.darkened(0.2), 2))
	button.add_theme_stylebox_override("disabled", _panel_style(Color("#35516d"), 12, Color("#6687a4"), 1))
	return button


func _style_option(option: OptionButton) -> void:
	option.add_theme_font_size_override("font_size", 15)
	option.add_theme_color_override("font_color", Color.WHITE)
	option.add_theme_stylebox_override("normal", _panel_style(Color("#0c2343"), 10, Color("#77cef8"), 2))
	option.add_theme_stylebox_override("hover", _panel_style(Color("#163b68"), 10, Color.WHITE, 2))


func _panel_style(fill: Color, radius: int, border := Color.TRANSPARENT, border_width := 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	return style


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _builder_layer and _builder_layer.visible:
			_builder_layer.visible = false
		elif _settings.visible:
			_settings.visible = false
		elif _room_overlay.visible:
			_close_room_overlay()


# ==================== 自由组卡层 ====================

func _build_deck_builder() -> void:
	_builder_layer = Control.new()
	_builder_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_builder_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_builder_layer.visible = false
	add_child(_builder_layer)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.03, 0.08, 0.15, 0.94)
	_builder_layer.add_child(shade)
	var title := _label("自由组卡", 28, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	title.position = Vector2(20, 18)
	title.size = Vector2(400, 44)
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_color_override("font_outline_color", Color("#15253e"))
	_builder_layer.add_child(title)
	_builder_count = _label("已选 0 / 8", 20, Color("#ffd966"), HORIZONTAL_ALIGNMENT_CENTER)
	_builder_count.position = Vector2(20, 64)
	_builder_count.size = Vector2(400, 28)
	_builder_layer.add_child(_builder_count)
	_builder_grid = Control.new()
	_builder_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_builder_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_builder_layer.add_child(_builder_grid)
	_builder_confirm = Button.new()
	_builder_confirm.text = "确认出战（选满 8 张）"
	_builder_confirm.position = Vector2(60, 700)
	_builder_confirm.size = Vector2(200, 50)
	_builder_confirm.add_theme_font_size_override("font_size", 16)
	_builder_confirm.disabled = true
	_builder_confirm.pressed.connect(_confirm_builder)
	_builder_layer.add_child(_builder_confirm)
	var cancel := Button.new()
	cancel.text = "返回"
	cancel.position = Vector2(280, 700)
	cancel.size = Vector2(100, 50)
	cancel.add_theme_font_size_override("font_size", 16)
	cancel.pressed.connect(_close_deck_builder)
	_builder_layer.add_child(cancel)


func _open_deck_builder() -> void:
	# 自由组卡编辑当前选中的预设槽位，重新打开时应显示该槽位现有配置。
	_builder_selection = Game.get_selected_deck()
	_builder_layer.visible = true
	_refresh_builder_grid()
	_update_builder_hud()


func _close_deck_builder() -> void:
	_builder_layer.visible = false


## 卡池：card_data 中所有带有效卡面 icon 的卡牌（含觉醒/精英），按 id 排序
func _builder_pool() -> Array:
	var pool := []
	for card_id in DataRegistry.card_data:
		var icon: String = DataRegistry.card_data[card_id].get("icon", "")
		if icon != "" and ResourceLoader.exists(icon):
			pool.append(card_id)
	pool.sort()
	return pool


func _refresh_builder_grid() -> void:
	for child in _builder_grid.get_children():
		child.queue_free()
	_builder_frames.clear()
	_builder_card_nodes.clear()
	var pool := _builder_pool()
	for i in range(pool.size()):
		var card_id: String = pool[i]
		var col := i % BUILDER_COLS
		var row := i / BUILDER_COLS
		var slot := Control.new()
		slot.position = Vector2(BUILDER_MARGIN_X + col * BUILDER_STEP_X, BUILDER_START_Y + row * BUILDER_STEP_Y)
		slot.size = Vector2(BUILDER_CARD_W, BUILDER_CARD_H)
		var tex := TextureRect.new()
		tex.texture = _card_texture(card_id)
		tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(tex)
		var frame := Panel.new()
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		frame.add_theme_stylebox_override("panel", _panel_style(Color(1, 0.85, 0.4, 0.0), 0, Color("#ffd966"), 4))
		frame.visible = card_id in _builder_selection
		slot.add_child(frame)
		_builder_frames[card_id] = frame
		var btn := Button.new()
		btn.flat = true
		btn.text = ""
		btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		btn.pressed.connect(_toggle_builder_card.bind(card_id))
		slot.add_child(btn)
		_builder_card_nodes[card_id] = {"tex": tex, "btn": btn}
		_builder_grid.add_child(slot)
	_apply_conflict_states()


func _toggle_builder_card(card_id: String) -> void:
	var idx := _builder_selection.find(card_id)
	if idx >= 0:
		_builder_selection.remove_at(idx)
	else:
		if _builder_selection.size() >= 8:
			return
		if _would_conflict(card_id):
			return  # 与已选卡 unit_id 冲突（精英 vs 普通同单位），禁止同选
		_builder_selection.append(card_id)
	if _builder_frames.has(card_id):
		_builder_frames[card_id].visible = card_id in _builder_selection
	_apply_conflict_states()
	_update_builder_hud()


## 互斥检查：选 card_id 是否会与已选卡 unit_id 冲突（精英 vs 普通同单位不能同选）
func _would_conflict(card_id: String) -> bool:
	var my_unit: String = DataRegistry.card_data[card_id].get("unit_id", "")
	if my_unit == "":
		return false
	for sel_id in _builder_selection:
		if sel_id == card_id:
			continue
		if DataRegistry.card_data[sel_id].get("unit_id", "") == my_unit:
			return true
	return false


## 更新所有卡牌的冲突视觉：未选但会冲突的卡变灰禁用，其余正常
func _apply_conflict_states() -> void:
	for card_id in _builder_card_nodes:
		var card: String = card_id
		var node := _builder_card_nodes[card_id] as Dictionary
		if node == null or node.is_empty():
			continue
		var conflict := _would_conflict(card) and not (card in _builder_selection)
		var tex := node.get("tex", null) as TextureRect
		var btn := node.get("btn", null) as Button
		if tex:
			tex.modulate = Color(0.35, 0.35, 0.35) if conflict else Color.WHITE
		if btn:
			btn.disabled = conflict


func _update_builder_hud() -> void:
	_builder_count.text = "已选 %d / 8" % _builder_selection.size()
	_builder_count.add_theme_color_override("font_color", Color("#7fff7f") if _builder_selection.size() >= 8 else Color("#ffd966"))
	_builder_confirm.disabled = _builder_selection.size() != 8


func _confirm_builder() -> void:
	if _builder_selection.size() != 8:
		return
	Game.set_selected_deck_cards(_builder_selection)
	_refresh_deck_cards()  # 卡组页立即显示新选的 8 张
	_close_deck_builder()
