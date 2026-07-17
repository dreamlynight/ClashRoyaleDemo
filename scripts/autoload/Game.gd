# 文件名：Game.gd
# 作用：保存全局游戏状态，提供场景切换的统一入口。
#       不处理具体战斗细节，只管"现在在哪个界面"。
# 挂载位置：Autoload（全局单例），在 project.godot 中注册。
# 初学者阅读建议：先看 start_battle()，理解点击"开始战斗"后场景怎么跳转。

extends Node

## 游戏状态枚举
enum GameState {
	MENU,     ## 在主菜单
	BATTLE,   ## 在战斗中
	PAUSED,   ## 暂停
	RESULT    ## 战斗结束，显示结果
}

## 当前游戏状态
var current_state: GameState = GameState.MENU

## 是否处于联机模式（true = 联机对战 / false = 单机 vs AI）
var network_mode: bool = false

## 对局规则：极速模式维持原有 7 倍圣水；经典模式采用官方 1v1 时间与倍率节奏。
enum MatchMode { FAST_7X, CLASSIC_1V1 }
var match_mode: int = MatchMode.FAST_7X

## 大厅中选择的预设卡组。
var selected_deck_index: int = 0
var remote_deck_cards: Array = []
## 自由组卡会直接更新当前选中的预设槽位。保留这两个字段以兼容旧调用方。
var custom_deck: Array = []
var use_custom_deck: bool = false
## 运行时可编辑的预设卡组。常量 PRESET_DECKS 只作为每个槽位的初始配置，
## 避免自由组卡误改共享默认数据，也确保切换预设后能保留各自的修改。
var configured_preset_decks: Array = []
## 加载页提前洗好的本局牌序。BattleManager 复用它，保证预加载的初始手牌就是实际初始手牌。
var prepared_player_deck_order: Array = []
var prepared_enemy_deck_order: Array = []

const PRESET_DECKS: Array[Dictionary] = [
	{"name": "皇家冲锋", "cards": ["card_hog_rider", "card_musketeer", "card_knight_elite", "card_fireball", "card_archers", "card_goblins", "card_inferno_tower", "card_arrows"]},
	{"name": "空中奇袭", "cards": ["card_balloon", "card_flyer", "card_mega_minion_elite", "card_musketeer", "card_fireball", "card_arrows", "card_goblins", "card_inferno_tower"]},
	{"name": "重甲推进", "cards": ["card_giant", "card_pekka", "card_mini_pekka", "card_musketeer", "card_poison", "card_arrows", "card_goblins", "card_elixir_collector"]},
	{"name": "迫击炮阵地", "cards": ["card_mortar", "card_princess", "card_knight_elite", "card_archers", "card_fireball", "card_poison", "card_ranger", "card_inferno_tower"]},
	{"name": "王子突击", "cards": ["card_prince", "card_valkyrie", "card_hog_rider", "card_musketeer", "card_fireball", "card_arrows", "card_mega_minion_elite", "card_elixir_collector"]},
]


## 设置联机模式（由 MainMenu 在进入战斗前调用）
func set_network_mode(enabled: bool) -> void:
	network_mode = enabled
	print("[Game] network_mode =", enabled)


func set_match_mode(mode: int) -> void:
	match_mode = mode
	print("[Game] match_mode =", mode)


func set_selected_deck(index: int) -> void:
	selected_deck_index = clampi(index, 0, PRESET_DECKS.size() - 1)
	print("[Game] selected deck =", selected_deck_index)


## 确保每套预设都有独立的可编辑运行时副本。
func _ensure_configured_preset_decks() -> void:
	if configured_preset_decks.size() == PRESET_DECKS.size():
		return
	configured_preset_decks.clear()
	for preset in PRESET_DECKS:
		var cards: Array = preset.get("cards", [])
		configured_preset_decks.append(cards.duplicate())


## 更新当前选中预设的卡组。自由组卡确认后和开始游戏都会经由此处读取同一份数据。
func set_selected_deck_cards(cards: Array) -> void:
	_ensure_configured_preset_decks()
	configured_preset_decks[selected_deck_index] = cards.duplicate()
	# 旧字段作为当前槽位的镜像保留，不能再作为全局覆盖层影响其他预设。
	custom_deck = cards.duplicate()
	use_custom_deck = false
	print("[Game] preset %d deck updated: %s" % [selected_deck_index, cards])


## 兼容旧的自由组卡调用：现在它会更新当前预设，而不是创建脱离预设的全局覆盖层。
func set_custom_deck(cards: Array) -> void:
	set_selected_deck_cards(cards)


func get_selected_deck() -> Array:
	_ensure_configured_preset_decks()
	return configured_preset_decks[selected_deck_index].duplicate()


func set_remote_deck(cards: Array) -> void:
	remote_deck_cards = cards.duplicate()


func get_remote_deck() -> Array:
	return remote_deck_cards.duplicate()


## 在进入加载页前锁定本局双方牌序。只把洗牌时机前移，不改变牌组内容或轮转规则。
func prepare_battle_decks(player_cards: Array, enemy_cards: Array) -> void:
	prepared_player_deck_order = player_cards.duplicate()
	prepared_enemy_deck_order = enemy_cards.duplicate()
	prepared_player_deck_order.shuffle()
	prepared_enemy_deck_order.shuffle()


## 联机 Client 接收 Host 已锁定的牌序。
func set_prepared_battle_decks(player_order: Array, enemy_order: Array) -> void:
	prepared_player_deck_order = player_order.duplicate()
	prepared_enemy_deck_order = enemy_order.duplicate()


## 专用联机服务器在两名玩家提交卡组后调用。
## 服务器和两个 Web 客户端都会收到同一份已洗牌的牌序，避免各端自行 shuffle 导致不同步。
func configure_dedicated_network_match(player_order: Array, enemy_order: Array, mode: int) -> void:
	set_network_mode(true)
	set_match_mode(mode)
	set_remote_deck(enemy_order)
	set_prepared_battle_decks(player_order, enemy_order)


func get_prepared_player_deck() -> Array:
	return prepared_player_deck_order.duplicate()


func get_prepared_enemy_deck() -> Array:
	return prepared_enemy_deck_order.duplicate()


func clear_prepared_battle_decks() -> void:
	prepared_player_deck_order.clear()
	prepared_enemy_deck_order.clear()


## 进入战斗场景
func start_battle(preloaded_scene: PackedScene = null) -> void:
	current_state = GameState.BATTLE
	SceneLoader.load_battle(preloaded_scene)


## 返回主菜单
func return_to_menu() -> void:
	current_state = GameState.MENU
	SceneLoader.load_main_menu()


## 重新开始战斗（重新加载战斗场景）
func restart_battle() -> void:
	current_state = GameState.BATTLE
	# 重开会重新实例化 BattleScene；清空上一局的场景握手，避免旧的 ready 标记
	# 让 Host 在 Client 新场景尚未创建时提前发送 BattleManager RPC。
	if network_mode and NetworkManager.is_networked():
		NetworkManager.reset_battle_scene_readiness()
	SceneLoader.load_battle()
