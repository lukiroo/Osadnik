extends Control

## =========================================================================
## LevelSelect.gd – wybór poziomu
## -------------------------------------------------------------------------
## - Pozwala wybrać ćwiczenie (G1_EX1 … G45_EX2) oraz egzamin.
## - Ustawia tryb trudności (Normalny/Trudny) w Settings.
## - Na podstawie progresu blokuje/odblokowuje poziomy i egzamin.
## - Konfiguruje następną scenę labu przez Settings.set_next_level_config().
## =========================================================================

# ───────────────────────── REFERENCJE UI ─────────────────────────
@onready var difficulty_select: OptionButton = $MarginContainer/VBox/HBoxDiff/DiffSelect
@onready var level_grid: GridContainer      = $MarginContainer/VBox/Grid
@onready var exam_button: Button            = $MarginContainer/VBox/ExamBtn
@onready var back_button: Button            = $MarginContainer/VBox/BackBtn


# ───────────────────────── START EKRANU ─────────────────────────────
func _ready() -> void:
	# Upewnij się, że OptionButton ma wpisy „Normalny/Trudny”.
	if difficulty_select.item_count == 0:
		difficulty_select.add_item("Normalny", 0)
		difficulty_select.add_item("Trudny", 1)

	difficulty_select.selected = clamp(Settings.difficulty_mode, 0, 1)

	if not difficulty_select.item_selected.is_connected(_on_difficulty_changed):
		difficulty_select.item_selected.connect(_on_difficulty_changed)

	# Przypięcie przycisków poziomów.
	_bind_level_button("G1_Ex1", func(): _start_level(1, "EX1"))
	_bind_level_button("G1_Ex2", func(): _start_level(1, "EX2"))
	_bind_level_button("G2_Ex1", func(): _start_level(2, "EX1"))
	_bind_level_button("G2_Ex2", func(): _start_level(2, "EX2"))
	_bind_level_button("G3_Ex1", func(): _start_level(3, "EX1"))
	_bind_level_button("G3_Ex2", func(): _start_level(3, "EX2"))
	_bind_level_button("G45_Ex1", func(): _start_level(4, "EX1"))
	_bind_level_button("G45_Ex2", func(): _start_level(4, "EX2"))

	# Egzamin + powrót.
	if not exam_button.pressed.is_connected(_on_exam_pressed):
		exam_button.pressed.connect(_on_exam_pressed)
	if not back_button.pressed.is_connected(_on_back_button_pressed):
		back_button.pressed.connect(_on_back_button_pressed)

	# Startowy stan z progresu.
	_refresh_level_locks()

	# Reaguj na zmiany Settings (np. po zaliczeniu).
	if not Settings.changed.is_connected(_on_settings_changed):
		Settings.changed.connect(_on_settings_changed)


# ───────────────────────── CALLBACKI SETTINGS ───────────────────
## Zmiana w Settings – odśwież blokady i tryb trudności.
func _on_settings_changed() -> void:
	_refresh_level_locks()
	difficulty_select.selected = clamp(Settings.difficulty_mode, 0, 1)


# ───────────────────────── HANDLERY UI ──────────────────────────
## Zmiana trybu trudności z OptionButton.
func _on_difficulty_changed(index: int) -> void:
	Settings.set_difficulty_mode(index)

## Przycisk „Powrót” – wyjście do głównego menu.
func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")


# ───────────────────────── BINDOWANIE PRZYCISKÓW ─────────────────
## Podpina callback do przycisku poziomu, jeśli istnieje.
func _bind_level_button(node_name: String, callback: Callable) -> void:
	var btn: Button = level_grid.get_node_or_null(node_name) as Button
	if btn and not btn.pressed.is_connected(callback):
		btn.pressed.connect(callback)


# ───────────────────────── BLOKADY I OPISY LEVELI ───────────────
## Odświeża stan „zablokowane/odblokowane” oraz tooltipy dla wszystkich poziomów.
func _refresh_level_locks() -> void:
	var level_button_map: Dictionary = {
		"G1_Ex1": Settings.level_key(1, "EXERCISE_SINGLE"),
		"G1_Ex2": Settings.level_key(1, "EXERCISE_MIX"),
		"G2_Ex1": Settings.level_key(2, "EXERCISE_SINGLE"),
		"G2_Ex2": Settings.level_key(2, "EXERCISE_MIX"),
		"G3_Ex1": Settings.level_key(3, "EXERCISE_SINGLE"),
		"G3_Ex2": Settings.level_key(3, "EXERCISE_MIX"),
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

## Zamienia level_key → tekstowy opis najlepszego wyniku.
func _best_result_text(level_key: String) -> String:
	var stars: int = 0
	if Settings.has_method("get_best_stars"):
		stars = int(Settings.get_best_stars(level_key))  # 0..3

	var base_text := "Najlepszy wynik: {0}/3".format([stars])
	return base_text + (" (niezaliczone)" if stars == 0 else "")


# ───────────────────────── START LEVELI ─────────────────────────
## Start normalnego ćwiczenia (EX1 lub EX2) – ustawia config i odpala lab.
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

## Start egzaminu – specjalny config (group_id=0, 1 starter, podkręcony mix).
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
