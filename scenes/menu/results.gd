extends Control

## =========================================================================
## Results.gd – ekran podsumowania ćwiczenia
## -------------------------------------------------------------------------
## - Odczytuje kontekst ostatniego biegu z Settings (mode, group_id, odpowiedzi).
## - Buduje UI odpowiedzi (EX1: radiobuttony, EX2: checkboxy).
## - Liczy wynik, błędy i gwiazdki, aktualizuje progres w Settings.
## - Pozwala spróbować ponownie albo przejść do kolejnego levelu.
## =========================================================================

# ───────────────────────── REFERENCJE UI ─────────────────────────
@onready var title_label: Label         = $MarginContainer/VBox/Title
@onready var scroll: ScrollContainer    = $MarginContainer/VBox/Scroll
@onready var items_box: VBoxContainer   = $MarginContainer/VBox/Scroll/Items
@onready var grade_label: Label         = $MarginContainer/VBox/GradeLabel
@onready var confirm_button: Button     = $MarginContainer/VBox/ConfirmBtn
@onready var back_button: Button        = $MarginContainer/VBox/BackBtn
@onready var try_again_button: Button   = $MarginContainer/VBox/TryAgainBtn
@onready var next_button: Button        = $MarginContainer/VBox/NextBtn

# EX1: po jednym ButtonGroup na wiersz + przyciski w tym wierszu.
var _single_row_groups: Array = []
var _single_row_buttons: Array = []

# EX2: lista checkboxów (mix).
var _mix_checkboxes: Array = []

# Kontekst bieżącego podejścia.
var _mode_str: String = ""
var _group_id: int = 0
var _correct_single: Dictionary = {}
var _correct_mix: Array = []

# Flaga zablokowania po zatwierdzeniu.
var _locked_after_submit: bool = false

# Litery do oznaczania probówek startowych: A, B, C, ...
const START_TUBE_LABELS: Array[String] = [
	"A","B","C","D","E","F","G","H","I","J","K","L"
]


# ───────────────────────── START PODSUMOWANIA ─────────────────────────────
func _ready() -> void:
	grade_label.text = ""

	var ctx: Dictionary = Settings.get_last_run_context()
	_mode_str       = String(ctx.get("mode_str", "EXERCISE_SINGLE"))
	_group_id       = int(ctx.get("group_id", 1))
	_correct_single = ctx.get("single_answer_map", {}) as Dictionary
	_correct_mix    = ctx.get("mix_answer_list", []) as Array

	var current_key: String = Settings.level_key(_group_id, _mode_str)
	var next_key: String = Settings.get_next_level_key(current_key)
	var can_go_next: bool = (next_key != "" and Settings.is_unlocked(next_key))
	next_button.visible = can_go_next

	if _mode_str == "EXERCISE_SINGLE":
		title_label.text = "Ćwiczenie 1: wybierz kation dla każdej probówki"
		if _correct_single.is_empty():
			_items_empty_msg("Brak mapy odpowiedzi — wróć do laboratorium i kliknij „Zakończ i sprawdź”.")
			confirm_button.disabled = true
			return
		_build_single_rows()
	else:
		title_label.text = "Ćwiczenie 2: wybierz wszystkie kationy w próbce"
		if _correct_mix.is_empty():
			_items_empty_msg("Brak listy kationów mieszanki — wróć do laboratorium i kliknij „Zakończ i sprawdź”.")
			confirm_button.disabled = true
			return
		_build_mix_row()


# ───────────────────────── DANE CHEMICZNE (LISTY JONÓW) ─────────
func _ions_for_group(group_id: int) -> Array[String]:
	if group_id == 0:
		return [
			"Ag+","Hg2 2+","Pb2+","Hg2+","Cu2+","Bi3+","Cd2+",
			"As3+","As5+","Sb3+","Sb5+","Sn2+","Sn4+","Zn2+",
			"Ni2+","Co2+","Mn2+","Fe2+","Fe3+","Al3+","Cr3+",
			"Ca2+","Sr2+","Ba2+","Mg2+","K+","Na+","NH4+"
		]
	if group_id == 1:
		return ["Ag+","Hg2 2+","Pb2+"]
	if group_id == 2:
		return ["Hg2+","Pb2+","Cu2+","Bi3+","Cd2+","As3+","As5+","Sb3+","Sb5+","Sn2+","Sn4+"]
	if group_id == 3:
		return ["Zn2+","Ni2+","Co2+","Mn2+","Fe2+","Fe3+","Al3+","Cr3+"]

	# Grupa IV+V (group_id == 4).
	return ["Ca2+","Sr2+","Ba2+","Mg2+","K+","Na+","NH4+"]


# ───────────────────────── BUDOWANIE UI – EX1 (SINGLE) ───────────
func _build_single_rows() -> void:
	_clear_items()
	_single_row_groups.clear()
	_single_row_buttons.clear()

	var slots: Array = _correct_single.keys()
	slots.sort()

	var ion_choices: Array[String] = _ions_for_group(_group_id)

	for i in range(slots.size()):
		var slot_idx: int = int(slots[i])

		var row: HBoxContainer = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 12)

		var num_label: Label = Label.new()
		var tube_label: String = _slot_index_to_letter(slot_idx)
		num_label.text = "Probówka %s:" % tube_label
		num_label.custom_minimum_size.x = 140
		row.add_child(num_label)

		var group: ButtonGroup = ButtonGroup.new()
		_single_row_groups.append(group)

		var flow: FlowContainer = FlowContainer.new()
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 6)

		var row_buttons: Array = []
		for ion in ion_choices:
			var btn: Button = Button.new()
			btn.text = ion
			btn.toggle_mode = true
			btn.button_group = group
			btn.focus_mode = Control.FOCUS_NONE
			row_buttons.append(btn)
			flow.add_child(btn)

		row.add_child(flow)
		items_box.add_child(row)
		_single_row_buttons.append(row_buttons)


# ───────────────────────── BUDOWANIE UI – EX2 (MIX) ──────────────
func _build_mix_row() -> void:
	_clear_items()
	_mix_checkboxes.clear()

	var root_box: VBoxContainer = VBoxContainer.new()
	root_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_box.add_theme_constant_override("separation", 8)

	var hint_label: Label = Label.new()
	hint_label.text = "Zaznacz wszystkie kationy, które zidentyfikowałeś w próbce."
	root_box.add_child(hint_label)

	var grid: GridContainer = GridContainer.new()
	grid.columns = 5
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)

	var ion_choices: Array[String] = _ions_for_group(_group_id)
	for ion in ion_choices:
		var cb: CheckBox = CheckBox.new()
		cb.text = ion
		cb.focus_mode = Control.FOCUS_NONE
		_mix_checkboxes.append(cb)
		grid.add_child(cb)

	root_box.add_child(grid)
	items_box.add_child(root_box)


# ───────────────────────── ZATWIERDZANIE WYNIKU ──────────────────
func _on_confirm_btn_pressed() -> void:
	if _locked_after_submit:
		return

	var total_answers: int = 0
	var correct_answers: int = 0
	var mistakes: int = 0

	if _mode_str == "EXERCISE_SINGLE":
		total_answers = _correct_single.size()
		var user_map: Dictionary = {}

		var slots: Array = _correct_single.keys()
		slots.sort()

		for row_index in range(_single_row_groups.size()):
			var chosen_text: String = ""
			for btn in _single_row_buttons[row_index]:
				var b: Button = btn as Button
				if b.button_pressed:
					chosen_text = b.text
					break
			var slot_idx: int = int(slots[row_index])
			user_map[slot_idx] = chosen_text

		mistakes = Settings.count_mistakes_single(_correct_single, user_map)
		correct_answers = max(0, total_answers - mistakes)
	else:
		total_answers = _correct_mix.size()

		var user_list: Array = []
		var seen: Dictionary = {}
		for btn in _mix_checkboxes:
			var cb: CheckBox = btn as CheckBox
			if cb.button_pressed and cb.text != "" and not seen.has(cb.text):
				seen[cb.text] = true
				user_list.append(cb.text)

		mistakes = Settings.count_mistakes_mix(_correct_mix, user_list)

		var expected_set: Dictionary = {}
		for ion in _correct_mix:
			expected_set[ion] = true

		var hits: int = 0
		for ion in user_list:
			if expected_set.has(ion):
				hits += 1
		correct_answers = hits

	var exercise_id: String = ("EX1" if _mode_str == "EXERCISE_SINGLE" else "EX2")

	var stars: int = Settings.compute_stars(
		mistakes,
		Settings.difficulty_mode,
		_group_id,
		exercise_id
	)

	var max_err: int = Settings.max_errors_allowed_for(
		_group_id,
		exercise_id,
		Settings.difficulty_mode
	)

	var passed: bool = (stars > 0)

	var level_key: String = Settings.level_key(_group_id, _mode_str)
	Settings.submit_result(level_key, mistakes)

	grade_label.text = "Wynik: {0}/{1} poprawnych".format([
		int(correct_answers),
		int(total_answers)
	])

	if passed:
		grade_label.text += " — ZALICZONE"
	else:
		grade_label.text += " — NIEZALICZONE (błędy: {0}, limit: {1})".format([
			int(mistakes),
			int(max_err)
		])

	grade_label.text += "\nGwiazdki: {0}/3".format([stars])

	_lock_all_choices()
	confirm_button.disabled = true
	confirm_button.visible = false
	_locked_after_submit = true
	try_again_button.visible = true

	var current_key: String = Settings.level_key(_group_id, _mode_str)
	var next_key: String = Settings.get_next_level_key(current_key)
	var can_go_next: bool = (next_key != "" and Settings.is_unlocked(next_key))
	next_button.visible = can_go_next


# ───────────────────────── BLOKADA WYBORÓW ───────────────────────
func _lock_all_choices() -> void:
	if _mode_str == "EXERCISE_SINGLE":
		for row_buttons in _single_row_buttons:
			for btn in row_buttons:
				(btn as Button).disabled = true
	else:
		for cb in _mix_checkboxes:
			(cb as CheckBox).disabled = true


# ───────────────────────── HANDLERY NAWIGACJI ────────────────────
func _on_back_btn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/level_select.tscn")


func _on_try_again_btn_pressed() -> void:
	# Restartuje TEN SAM level z TĄ SAMĄ trudnością.
	# Wystarczy ponownie ustawić config w Settings i odpalić lab.
	var is_exam: bool = (_group_id == 0)  # egzamin = group_id 0
	var counts: Dictionary = Settings.compute_level_counts(_mode_str, is_exam)
	var cfg: Dictionary = {
		"mode": _mode_str,
		"group_id": _group_id,
		"starter_count": counts.starter_count,
		"mix_difficulty": counts.mix_difficulty
	}
	Settings.set_next_level_config(cfg)
	get_tree().change_scene_to_file("res://scenes/lab.tscn")


func _on_next_btn_pressed() -> void:
	var curr_key: String = Settings.level_key(_group_id, _mode_str)
	var next_key: String = Settings.get_next_level_key(curr_key)
	if next_key == "":
		get_tree().change_scene_to_file("res://scenes/menu/level_select.tscn")
		return
	_start_next_level_from_key(next_key)


# ───────────────────────── START KOLEJNEGO LEVELU ────────────────
func _start_next_level_from_key(next_key: String) -> void:
	var next_group_id: int = 0
	var next_mode_str: String = "EXERCISE_SINGLE"
	var is_exam: bool = false

	if next_key == "EXAM":
		is_exam = true
		next_mode_str = "EXERCISE_MIX"
		next_group_id = 0
	else:
		var parts: Array = next_key.split("_")
		if parts.size() >= 2 and String(parts[0]).begins_with("G"):
			var num_str: String = String(parts[0]).substr(1) # "1"/"2"/"3"/"45"
			next_group_id = 4 if num_str == "45" else int(num_str)
			next_mode_str = "EXERCISE_SINGLE" if parts[1] == "EX1" else "EXERCISE_MIX"

	var counts: Dictionary = Settings.compute_level_counts(next_mode_str, is_exam)
	var cfg: Dictionary = {
		"mode": next_mode_str,
		"group_id": next_group_id,
		"starter_count": counts.starter_count,
		"mix_difficulty": counts.mix_difficulty
	}
	Settings.set_next_level_config(cfg)
	get_tree().change_scene_to_file("res://scenes/lab.tscn")


# ───────────────────────── POMOCNICZE (UI) ───────────────────────
func _clear_items() -> void:
	for child in items_box.get_children():
		child.queue_free()


func _items_empty_msg(msg: String) -> void:
	_clear_items()
	var label: Label = Label.new()
	label.text = msg
	items_box.add_child(label)


# ───────────────────────── POMOCNICZE (LITERY) ───────────────────
func _slot_index_to_letter(slot_idx: int) -> String:
	if slot_idx >= 0 and slot_idx < START_TUBE_LABELS.size():
		return START_TUBE_LABELS[slot_idx]
	return str(slot_idx + 1)
