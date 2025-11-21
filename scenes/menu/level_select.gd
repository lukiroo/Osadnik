extends Control

## =========================================================================
## LevelSelect.gd – wybór poziomu
## -------------------------------------------------------------------------
## - Przy kliknięciu poziomu:
##     * G1_Ex1 / G1_Ex2 → od razu start "Normalny",
##     * pozostałe → pokazuje się panel z przyciskami Normalny / Trudny.
## - Trudność jest zapisywana w Settings.difficulty_mode (0/1).
## - Na podstawie progresu blokuje/odblokowuje poziomy i egzamin.
## - Konfiguruje następną scenę labu przez Settings.set_next_level_config().
## =========================================================================

# ───────────────────────── REFERENCJE UI ─────────────────────────

@onready var level_grid: GridContainer = $MarginContainer/VBox/Grid
@onready var exam_button: Button       = $MarginContainer/VBox/ExamBtn
@onready var back_button: Button       = $MarginContainer/VBox/BackBtn

# Panel z wyborem trudności (Twoja struktura)
@onready var difficulty_panel: Panel   = $DifficultyPanel
@onready var diff_label: Label         = $DifficultyPanel/VBox/Label
@onready var diff_normal_btn: Button = $DifficultyPanel/VBox/HBox/NormalBtn
@onready var diff_hard_btn: Button = $DifficultyPanel/VBox/HBox/HardBtn

# Zapamiętujemy, jaki level został kliknięty przed wyborem trudności:
var _pending_group_id: int = 0
var _pending_exercise_id: String = ""   # "EX1" albo "EX2"


# ───────────────────────── START EKRANU ─────────────────────────────
func _ready() -> void:
	# Panel trudności na start ukryty.
	if difficulty_panel:
		difficulty_panel.visible = false

	# Przypięcie przycisków poziomów:
	_bind_level_button("G1_Ex1", func(): _on_level_button_pressed(1, "EX1"))
	_bind_level_button("G1_Ex2", func(): _on_level_button_pressed(1, "EX2"))
	_bind_level_button("G2_Ex1", func(): _on_level_button_pressed(2, "EX1"))
	_bind_level_button("G2_Ex2", func(): _on_level_button_pressed(2, "EX2"))
	_bind_level_button("G3_Ex1", func(): _on_level_button_pressed(3, "EX1"))
	_bind_level_button("G3_Ex2", func(): _on_level_button_pressed(3, "EX2"))
	_bind_level_button("G45_Ex1", func(): _on_level_button_pressed(4, "EX1"))
	_bind_level_button("G45_Ex2", func(): _on_level_button_pressed(4, "EX2"))

	# Egzamin + powrót.
	if not exam_button.pressed.is_connected(_on_exam_pressed):
		exam_button.pressed.connect(_on_exam_pressed)
	if not back_button.pressed.is_connected(_on_back_button_pressed):
		back_button.pressed.connect(_on_back_button_pressed)

	# Przycisk „Normalny / Trudny” w panelu:
	if diff_normal_btn and not diff_normal_btn.pressed.is_connected(_on_diff_normal_pressed):
		diff_normal_btn.pressed.connect(_on_diff_normal_pressed)
	if diff_hard_btn and not diff_hard_btn.pressed.is_connected(_on_diff_hard_pressed):
		diff_hard_btn.pressed.connect(_on_diff_hard_pressed)

	# Startowy stan z progresu.
	_refresh_level_locks()

	# Reaguj na zmiany Settings (np. po zaliczeniu).
	if not Settings.changed.is_connected(_on_settings_changed):
		Settings.changed.connect(_on_settings_changed)


# ───────────────────────── CALLBACKI SETTINGS ───────────────────
func _on_settings_changed() -> void:
	_refresh_level_locks()
	# difficulty_mode ustawiamy tylko przy wyborze Normalny/Trudny.


# ───────────────────────── HANDLERY UI ──────────────────────────

func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")


# Kliknięcie przycisku levelu (w gridzie)
func _on_level_button_pressed(group_id: int, exercise_id: String) -> void:
	# Grupa 1 – EX1 / EX2 zawsze Normalny, bez panelu.
	if group_id == 1:
		Settings.set_difficulty_mode(0) # 0 = Normalny
		_start_level(group_id, exercise_id)
		return

	# Pozostałe – pokaż panel wyboru trudności.
	_pending_group_id = group_id
	_pending_exercise_id = exercise_id
	_show_difficulty_panel(group_id, exercise_id)


func _show_difficulty_panel(group_id: int, exercise_id: String) -> void:
	if difficulty_panel == null:
		# Awaryjnie – brak panelu → odpal Normalny.
		Settings.set_difficulty_mode(0)
		_start_level(group_id, exercise_id)
		return

	if diff_label:
		var ex_text := "Ćwiczenie 1" if exercise_id == "EX1" else "Ćwiczenie 2"
		diff_label.text = "Grupa %d – %s\nWybierz trudność:" % [group_id, ex_text]


	difficulty_panel.visible = true
	# Jeśli chcesz, w Inspektorze ustaw DifficultyPanel → Mouse > Filter = "Stop",
	# żeby w tym czasie blokował klikanie w tło.


func _hide_difficulty_panel() -> void:
	if difficulty_panel:
		difficulty_panel.visible = false

func _input(event: InputEvent) -> void:
	# Jeśli panel nie jest widoczny – nic nie robimy.
	if not difficulty_panel or not difficulty_panel.visible:
		return

	# Interesuje nas tylko klik LPM.
	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and event.pressed:
		var panel_rect: Rect2 = difficulty_panel.get_global_rect()
		var click_pos: Vector2 = event.position  # współrzędne w oknie
		if not panel_rect.has_point(click_pos):
			_hide_difficulty_panel()
			get_viewport().set_input_as_handled()


func _on_diff_normal_pressed() -> void:
	Settings.set_difficulty_mode(0) # Normalny
	_hide_difficulty_panel()
	_start_level(_pending_group_id, _pending_exercise_id)


func _on_diff_hard_pressed() -> void:
	Settings.set_difficulty_mode(1) # Trudny
	_hide_difficulty_panel()
	_start_level(_pending_group_id, _pending_exercise_id)


# ───────────────────────── BINDOWANIE PRZYCISKÓW ─────────────────
func _bind_level_button(node_name: String, callback: Callable) -> void:
	var btn: Button = level_grid.get_node_or_null(node_name) as Button
	if btn and not btn.pressed.is_connected(callback):
		btn.pressed.connect(callback)


# ───────────────────────── BLOKADY I OPISY LEVELI ───────────────
func _refresh_level_locks() -> void:
	var level_button_map: Dictionary = {
		"G1_Ex1":  Settings.level_key(1, "EXERCISE_SINGLE"),
		"G1_Ex2":  Settings.level_key(1, "EXERCISE_MIX"),
		"G2_Ex1":  Settings.level_key(2, "EXERCISE_SINGLE"),
		"G2_Ex2":  Settings.level_key(2, "EXERCISE_MIX"),
		"G3_Ex1":  Settings.level_key(3, "EXERCISE_SINGLE"),
		"G3_Ex2":  Settings.level_key(3, "EXERCISE_MIX"),
		"G45_Ex1": Settings.level_key(4, "EXERCISE_SINGLE"),
		"G45_Ex2": Settings.level_key(4, "EXERCISE_MIX")
	}

	for node_name in level_button_map.keys():
		var btn: Button = level_grid.get_node_or_null(node_name) as Button
		if not btn:
			continue

		var level_key: String = String(level_button_map[node_name])
		var unlocked: bool = Settings.is_unlocked(level_key)

		btn.disabled = not unlocked
		btn.modulate.a = 1.0 if unlocked else 0.5
		btn.tooltip_text = _best_result_text(level_key)

	# Egzamin odblokowany po G45_EX2.
	var exam_unlocked: bool = Settings.is_unlocked("EXAM")
	exam_button.disabled = not exam_unlocked
	exam_button.modulate.a = 1.0 if exam_unlocked else 0.5
	exam_button.tooltip_text = _best_result_text("EXAM")


func _best_result_text(level_key: String) -> String:
	var stars: int = 0
	if Settings.has_method("get_best_stars"):
		stars = int(Settings.get_best_stars(level_key))  # 0..3

	var base_text := "Najlepszy wynik: {0}/3".format([stars])
	return base_text + (" (niezaliczone)" if stars == 0 else "")


# ───────────────────────── START LEVELI ─────────────────────────
func _start_level(group_id: int, exercise_id: String) -> void:
	var mode_str := "EXERCISE_SINGLE" if exercise_id == "EX1" else "EXERCISE_MIX"
	var counts: Dictionary = Settings.compute_level_counts(mode_str)
	var cfg: Dictionary = {
		"mode": mode_str,
		"group_id": group_id,
		"starter_count": counts.starter_count,
		"mix_difficulty": counts.mix_difficulty
	}
	Settings.set_next_level_config(cfg)
	get_tree().change_scene_to_file("res://scenes/lab.tscn")


func _on_exam_pressed() -> void:
	var mode_str := "EXERCISE_MIX"
	var counts: Dictionary = Settings.compute_level_counts(mode_str, true)
	var cfg: Dictionary = {
		"mode": mode_str,
		"group_id": 0,
		"starter_count": 1,
		"mix_difficulty": counts.mix_difficulty
	}
	Settings.set_next_level_config(cfg)
	get_tree().change_scene_to_file("res://scenes/lab.tscn")
