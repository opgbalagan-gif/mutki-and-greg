class_name GameHUD
extends CanvasLayer

signal super_pressed
signal retry_pressed
signal attack_pressed(attack_index: int)
signal character_selected(fighter_id: String)

@onready var hp_bar: ProgressBar = $Root/TopPanel/HPBar
@onready var hp_label: Label = $Root/TopPanel/HPLabel
@onready var wave_label: Label = $Root/TopPanel/WaveLabel
@onready var score_label: Label = $Root/TopPanel/ScoreLabel
@onready var combo_label: Label = $Root/ComboLabel
@onready var super_bar: ProgressBar = $Root/BottomPanel/SuperBar
@onready var super_button: Button = $Root/BottomPanel/SuperButton
@onready var super_title_label: Label = $Root/BottomPanel/SuperTitle
@onready var fighter_portrait: TextureRect = $Root/BottomPanel/GregPortrait
@onready var debug_label: Label = $Root/DebugPanel/DebugLabel
@onready var debug_panel: Panel = $Root/DebugPanel
@onready var message_panel: Panel = $Root/MessagePanel
@onready var message_label: Label = $Root/MessagePanel/MessageLabel
@onready var character_select: Control = $Root/CharacterSelect
@onready var attack_buttons: Array[Button] = [
	$Root/AttackPanel/Attack1,
	$Root/AttackPanel/Attack2,
	$Root/AttackPanel/Attack3,
	$Root/AttackPanel/Attack4,
]

var fighter_name := "МУТКИ"
var special_name := "GREG SUPER"


func _ready() -> void:
	super_button.pressed.connect(func(): super_pressed.emit())
	$Root/MessagePanel/RetryButton.pressed.connect(func(): retry_pressed.emit())
	$Root/CharacterSelect/MenuPanel/MutkiButton.pressed.connect(
		func(): character_selected.emit("mutki")
	)
	$Root/CharacterSelect/MenuPanel/GregButton.pressed.connect(
		func(): character_selected.emit("greg")
	)
	for index in attack_buttons.size():
		attack_buttons[index].pressed.connect(_on_attack_button_pressed.bind(index))
	set_super(0.0)


func _on_attack_button_pressed(index: int) -> void:
	attack_pressed.emit(index)


func show_character_select() -> void:
	character_select.visible = true
	$Root/TopPanel.visible = false
	$Root/AttackPanel.visible = false
	$Root/BottomPanel.visible = false


func configure_fighter(fighter_id: String, display_name: String, attack_count: int) -> void:
	fighter_name = display_name
	special_name = "GREG POWER" if fighter_id == "greg" else "GREG SUPER"
	character_select.visible = false
	$Root/TopPanel.visible = true
	$Root/AttackPanel.visible = true
	$Root/BottomPanel.visible = true
	super_title_label.text = special_name
	var portrait_path := "res://assets/characters/%s/idle/%s_idle_01.png" % [fighter_id, fighter_id]
	fighter_portrait.texture = load(portrait_path) as Texture2D
	for index in attack_buttons.size():
		attack_buttons[index].disabled = index >= attack_count
	set_super(0.0)


func set_hp(current: int, maximum: int) -> void:
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
	super_button.disabled = value < 100.0
	var short_name := "POWER" if special_name == "GREG POWER" else "GREG"
	super_button.text = "%s\nREADY!" % short_name if value >= 100.0 else "%s\n%02d%%" % [short_name, int(value)]


func set_debug_visible(value: bool) -> void:
	debug_panel.visible = value


func set_debug_text(value: String) -> void:
	debug_label.text = value


func show_game_over(score: int) -> void:
	message_panel.visible = true
	message_label.text = "РАЙОН НЕ УДЕРЖАН\nSCORE  %07d" % score


func hide_message() -> void:
	message_panel.visible = false
