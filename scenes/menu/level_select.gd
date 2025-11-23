extends Control

## =========================================================================
## LevelSelect.gd – wybór poziomu
## -------------------------------------------------------------------------
## Odpowiada za:
## - wybór grupy i typu zadania (EX1 / EX2),
## - wybór trudności (Normalny / Trudny) dla zadań
## - blokowanie/odblokowywanie leveli na podstawie progresu,
## - start wybranego poziomu z odpowiednią konfiguracją.
## =========================================================================

@onready var levels_root: VBoxContainer = $MarginContainer/VBox

@onready var exam_button: BaseButton = $MarginContainer/VBox/ExamBtn
@onready var back_button: BaseButton = $MarginContainer/VBox/BackBtn

@onready var difficulty_overlay: Control = $DifficultyOverlay
@onready var difficulty_panel: Panel     = $DifficultyOverlay/DifficultyPanel
@onready var diff_label: Label           = $DifficultyOverlay/DifficultyPanel/VBox/Label
@onready var diff_normal_btn: BaseButton = $DifficultyOverlay/DifficultyPanel/VBox/HBox/NormalBtn
@onready var diff_hard_btn: BaseButton   = $DifficultyOverlay/DifficultyPanel/VBox/HBox/HardBtn

var _pending_group_id: int = 0         # grupa kliknięta przed wyborem trudności
var _pending_exercise_id: String = ""  # "EX1" / "EX2"


## Przygotowuje ekran wyboru leveli: podpina sygnały przycisków, ukrywa overlay trudności i odświeża blokady.
func _ready() -> void:
	difficulty_overlay.visible = false

	_bind_level_button("G1_Ex1", func(): _on_level_button_pressed(1, "EX1"))
	_bind_level_button("G1_Ex2", func(): _on_level_button_pressed(1, "EX2"))
	_bind_level_button("G2_Ex1", func(): _on_level_button_pressed(2, "EX1"))
	_bind_level_button("G2_Ex2", func(): _on_level_button_pressed(2, "EX2"))
	_bind_level_button("G3_Ex1", func(): _on_level_button_pressed(3, "EX1"))
	_bind_level_button("G3_Ex2", func(): _on_level_button_pressed(3, "EX2"))
	_bind_level_button("G45_Ex1", func(): _on_level_button_pressed(4, "EX1"))
	_bind_level_button("G45_Ex2", func(): _on_level_button_pressed(4, "EX2"))


	_refresh_level_locks()

	if not Settings.changed.is_connected(_on_settings_changed):
		Settings.changed.connect(_on_settings_changed)


## Reaguje na zmiany w Settings (np. po zaliczeniu poziomu) i odświeża blokady oraz gwiazdki na przyciskach.
func _on_settings_changed() -> void:
	_refresh_level_locks()


# ======================= HANDLERY BUTTONÓW =======================

## Wraca do głównego menu.
func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")


## Obsługuje kliknięcie przycisku poziomu. Dla grupy 1 od razu startuje level na Normalnym, dla innych pokazuje panel wyboru trudności.
func _on_level_button_pressed(group_id: int, exercise_id: String) -> void:
	if group_id == 1:
		Settings.set_difficulty_mode(0)
		_start_level(group_id, exercise_id)
		return

	_pending_group_id = group_id
	_pending_exercise_id = exercise_id
	_show_difficulty_panel(group_id, exercise_id)


## Utawia opis w panelu trudności i pokazuje overlay z przyciskami Normalny / Trudny.
func _show_difficulty_panel(group_id: int, exercise_id: String) -> void:
	if group_id == 0:
		diff_label.text = "EGZAMIN\nANALIZA MIESZANINY KATIONÓW"
	else:
		var exercise_text := (
			"IDENTYFIKACJA POJEDYNCZYCH KATIONÓW"
			if exercise_id == "EX1"
			else "IDENTYFIKACJA MIESZANINY KATIONÓW"
		)
		diff_label.text = "GRUPA %d\n%s" % [group_id, exercise_text]

	difficulty_overlay.visible = true


## Chowa overlay z wyborem trudności.
func _hide_difficulty_panel() -> void:
	difficulty_overlay.visible = false


## Nasłuchuje kliknięć myszy i zamyka panel trudności, jeśli gracz kliknie poza jego obszarem.
func _input(event: InputEvent) -> void:
	if not difficulty_overlay.visible:
		return

	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and event.pressed:
		var panel_rect: Rect2 = difficulty_panel.get_global_rect()
		if not panel_rect.has_point(event.position):
			_hide_difficulty_panel()
			get_viewport().set_input_as_handled()


## Ustawia tryb Normalny, chowa panel i startuje wybrany poziom.
func _on_diff_normal_pressed() -> void:
	Settings.set_difficulty_mode(0)
	_hide_difficulty_panel()
	_start_level(_pending_group_id, _pending_exercise_id)


## Ustawia tryb Trudny, chowa panel i startuje wybrany poziom.
func _on_diff_hard_pressed() -> void:
	Settings.set_difficulty_mode(1)
	_hide_difficulty_panel()
	_start_level(_pending_group_id, _pending_exercise_id)


## Obsługuje przycisk egzaminu: ustawia pending na grupę 0 / EX2 i pokazuje panel trudności.
func _on_exam_pressed() -> void:
	_pending_group_id = 0
	_pending_exercise_id = "EX2"
	_show_difficulty_panel(0, "EX2")


# ==================== BINDOWANIE PRZYCISKÓW ======================

## Znajduje przycisk poziomu po nazwie i podłącza do niego przekazaną funkcję callback.
func _bind_level_button(node_name: String, callback: Callable) -> void:
	var btn := levels_root.find_child(node_name, true, false) as BaseButton
	if not btn.pressed.is_connected(callback):
		btn.pressed.connect(callback)


# ====================== BLOKADY I GWIAZDKI =======================

## Blokuje/odblokowuje przyciski poziomów na podstawie progresu oraz ustawia im podpisy i gwiazdki.
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
		var btn := levels_root.find_child(node_name, true, false) as BaseButton
		var level_key: String = level_button_map[node_name]
		var unlocked := Settings.is_unlocked(level_key)

		btn.disabled = not unlocked
		btn.modulate.a = 1.0 if unlocked else 0.5

		_set_level_button_caption(node_name)
		var stars := Settings.get_best_stars(level_key)
		_update_level_button_stars(node_name, stars)

	var exam_unlocked := Settings.is_unlocked("EXAM")
	exam_button.disabled = not exam_unlocked
	exam_button.modulate.a = 1.0 if exam_unlocked else 0.5
	_set_level_button_caption("ExamBtn")
	var exam_stars := Settings.get_best_stars("EXAM")
	_update_level_button_stars("ExamBtn", exam_stars)


## Ustawia tekst na przycisku poziomu („Zadanie 1/2” lub „Analiza mieszaniny”).
func _set_level_button_caption(node_name: String) -> void:
	var btn := levels_root.find_child(node_name, true, false) as Control
	var vbox := btn.get_node("VBox") as VBoxContainer
	var lbl  := vbox.get_node("Label") as Label

	var text := ""
	if node_name == "ExamBtn":
		text = "Analiza mieszaniny"
	elif node_name.ends_with("Ex1"):
		text = "Zadanie 1"
	elif node_name.ends_with("Ex2"):
		text = "Zadanie 2"

	lbl.text = text


# Ustawia widoczność 0–3 gwiazdek na przycisku levelu.
func _update_level_button_stars(node_name: String, stars: int) -> void:
	stars = clamp(stars, 0, 3)

	var btn := levels_root.find_child(node_name, true, false) as Control
	if btn == null:
		return

	var vbox := btn.get_node("VBox") as VBoxContainer
	var star_container := vbox.get_node("HBox") as HBoxContainer

	var shadow_names := ["Shadow1", "Shadow2", "Shadow3"]
	var star_names := ["Star1", "Star2", "Star3"]

	for i in range(shadow_names.size()):
		var shadow := star_container.get_node(shadow_names[i])
		var star := shadow.get_node(star_names[i]) as CanvasItem
		star.visible = (i < stars)




# ========================= START LEVELU ==========================

## Buduje konfigurację poziomu na podstawie grupy i typu ćwiczenia, zapisuje ją w Settings i przełącza scenę na lab.
func _start_level(group_id: int, exercise_id: String) -> void:
	var mode_str := "EXERCISE_SINGLE" if exercise_id == "EX1" else "EXERCISE_MIX"
	var counts := Settings.compute_level_counts(mode_str, group_id == 0)

	var cfg: Dictionary = {
		"mode": mode_str,
		"group_id": group_id,
		"starter_count": counts.starter_count,
		"mix_difficulty": counts.mix_difficulty
	}
	Settings.set_next_level_config(cfg)
	get_tree().change_scene_to_file("res://scenes/lab.tscn")
