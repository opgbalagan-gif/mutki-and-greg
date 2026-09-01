class_name GameHUD
extends CanvasLayer

signal retry_pressed
signal character_selected(fighter_id: String)

@onready var hp_bar: ProgressBar = $Root/TopPanel/HPBar
@onready var hp_label: Label = $Root/TopPanel/HPLabel
@onready var top_panel: Panel = $Root/TopPanel
@onready var greg_health_bar: GregHealthBar = $Root/GregHealthBar
@onready var wave_label: Label = $Root/TopPanel/WaveLabel
@onready var score_label: Label = $Root/TopPanel/ScoreLabel
@onready var combo_label: Label = $Root/ComboLabel
@onready var super_bar: ProgressBar = $Root/BottomPanel/SuperBar
@onready var super_title_label: Label = $Root/BottomPanel/SuperTitle
@onready var fighter_portrait: TextureRect = $Root/BottomPanel/GregPortrait
@onready var debug_label: Label = $Root/DebugPanel/DebugLabel
@onready var debug_panel: Panel = $Root/DebugPanel
@onready var message_panel: Panel = $Root/MessagePanel
@onready var message_label: Label = $Root/MessagePanel/MessageLabel
@onready var character_select: Control = $Root/CharacterSelect
var fighter_name := "МУТКИ"
var special_name := "GREG SUPER"
var current_fighter_id := ""


func _ready() -> void:
	$Root/MessagePanel/RetryButton.pressed.connect(func(): retry_pressed.emit())
	$Root/CharacterSelect/MenuPanel/MutkiButton.pressed.connect(
		func(): character_selected.emit("mutki")
	)
	$Root/CharacterSelect/MenuPanel/GregButton.pressed.connect(
		func(): character_selected.emit("greg")
	)
	set_super(0.0)


func show_character_select() -> void:
	character_select.visible = true
	$Root/TopPanel.visible = false
	greg_health_bar.visible = false
	$Root/BottomPanel.visible = false


func configure_fighter(fighter_id: String, display_name: String, _attack_count: int) -> void:
	current_fighter_id = fighter_id
	fighter_name = display_name
	special_name = "GREG POWER" if fighter_id == "greg" else "GREG SUPER"
	character_select.visible = false
	$Root/TopPanel.visible = true
	$Root/BottomPanel.visible = true
	var greg_selected := fighter_id == "greg"
	hp_bar.visible = not greg_selected
	hp_label.visible = not greg_selected
	greg_health_bar.visible = greg_selected
	top_panel.offset_bottom = 100.0 if greg_selected else 152.0
	combo_label.position.y = 318.0 if greg_selected else 170.0
	super_title_label.text = special_name
	var portrait_path := "res://assets/characters/%s/idle/%s_idle_01.png" % [fighter_id, fighter_id]
	fighter_portrait.texture = load(portrait_path) as Texture2D
	set_super(0.0)


func set_hp(current: int, maximum: int) -> void:
	if current_fighter_id == "greg":
		greg_health_bar.set_health(float(current), float(maximum))
		return
	hp_bar.max_value = maximum
	hp_bar.value = current
	hp_label.text = "%s  %d / %d" % [fighter_name, current, maximum]


func set_wave(value: int, wave_size: int) -> void:
	wave_label.text = "WAVE %02d  ·  %d FIGHTERS" % [value, wave_size]


func set_score(value: int) -> void:
	score_label.text = "%07d" % value


func set_combo(value: int) -> void:
	combo_label.visible = value > 1
	combo_label.text = "x%d COMBO" % value


func set_super(value: float) -> void:
	super_bar.value = value
	super_title_label.text = "%s  ·  READY!" % special_name if value >= 100.0 else special_name


func set_debug_visible(value: bool) -> void:
	debug_panel.visible = value


func set_debug_text(value: String) -> void:
	debug_label.text = value


func show_game_over(score: int) -> void:
	message_panel.visible = true
	message_label.text = "РАЙОН НЕ УДЕРЖАН\nSCORE  %07d" % score


func hide_message() -> void:
	message_panel.visible = false
