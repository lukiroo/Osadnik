extends Control

## =========================================================================
## results_cations.gd – ekran podsumowania zadania / egzaminu (kationy)
## -------------------------------------------------------------------------
## - buduje listę przycisków z kationami,
## - zbiera odpowiedzi gracza i liczy błędy/gwiazdki,
## - koloruje odpowiedzi na zielono/czerwono,
## - umożliwia powtórkę, przejście dalej lub powrót.
## =========================================================================

const ANSWER_BUTTON_SCENE: PackedScene = preload("res://scenes/menu/answer_button.tscn")

const COLOR_NEUTRAL      := Color(1, 1, 1, 1)
const COLOR_SELECTED     := Color(0.565, 0.851, 1.0, 1.0)
const COLOR_CORRECT      := Color(0.0, 0.882, 0.376, 1.0)
const COLOR_WRONG        := Color(0.914, 0.235, 0.294, 1.0)
const COLOR_TRUE_ANSWER  := Color(0.0, 0.737, 0.473, 0.2)

const ION_LABELS := {
	"Ag+": "Ag⁺", "Hg22+": "Hg₂²⁺", "Pb2+": "Pb²⁺",
	"Hg2+":"Hg²⁺", "Cu2+": "Cu²⁺", "Bi3+": "Bi³⁺", "Cd2+": "Cd²⁺",
	"As3+":"As³⁺", "As5+": "As⁵⁺", "Sb3+": "Sb³⁺", "Sb5+": "Sb⁵⁺", "Sn2+":"Sn²⁺", "Sn4+": "Sn⁴⁺",
	"Zn2+":"Zn²⁺", "Ni2+":"Ni²⁺", "Co2+":"Co²⁺", "Mn2+":"Mn²⁺", "Fe2+":"Fe²⁺", "Fe3+":"Fe³⁺", "Al3+":"Al³⁺", "Cr3+":"Cr³⁺",
	"Ca2+":"Ca²⁺", "Sr2+":"Sr²⁺", "Ba2+":"Ba²⁺", "Mg2+":"Mg²⁺",
	"K+": "K⁺", "Na+": "Na⁺", "NH4+": "NH₄⁺"
}

@export_group("Font label")
@export var ion_label_font: Font


@onready var title_label: Label              = $MarginContainer/VBox/Title
@onready var items_box: VBoxContainer        = $MarginContainer/VBox/Items
@onready var result_box: VBoxContainer       = $ResultBox
@onready var result_stars_row: HBoxContainer = $ResultBox/Stars

@onready var confirm_button: TextureButton   = $ConfirmBtn
@onready var try_again_button: TextureButton = $TryAgainBtn
@onready var next_button: TextureButton      = $NextBtn
@onready var back_button: TextureButton      = $BackBtn

# EX1 – po probówkach
var _single_row_groups: Array = []      ## Array[ButtonGroup]
var _single_row_buttons: Array = []     ## Array[Array[TextureButton]]

# EX2 – mieszanina
var _mix_buttons: Array = []            ## Array[TextureButton]

var _exercise_mode: String = ""         ## "EXERCISE_SINGLE" / "EXERCISE_MIX"
var _group_id: int = 0                  ## 1–4, 0 = egzamin
var _single_correct_map: Dictionary = {}
var _mix_correct_list: Array = []

var _locked_after_submit: bool = false

const START_TUBE_LABELS: Array[String] = ["A","B","C","D","E"]


## Zamienia numer grupy (1–4) na zapis rzymski używany w tytule.
func _group_to_roman(group_id: int) -> String:
	match group_id:
		1:
			return "I"
		2:
			return "II"
		3:
			return "III"
		4:
			return "IV–V"
		_:
			return "?"


## Ustawia UI, wczytuje kontekst z Settings, ustawia tytuł i buduje listę odpowiedzi.
func _ready() -> void:
	items_box.add_theme_constant_override("separation", 20)

	result_box.visible = false
	try_again_button.visible = false
	_update_result_stars(0)

	var ctx := Settings.get_last_run_context()
	_exercise_mode      = String(ctx.get("mode_str", "EXERCISE_SINGLE"))
	_group_id           = int(ctx.get("group_id", 1))
	_single_correct_map = ctx.get("single_answer_map", {}) as Dictionary
	_mix_correct_list   = ctx.get("mix_answer_list", []) as Array

	var current_key := Settings.level_key_cations(_group_id, _exercise_mode)
	var next_key := Settings.get_next_level_key_cations(current_key)
	next_button.visible = (next_key != "" and Settings.is_unlocked_cations(next_key))

	if _exercise_mode == "EXERCISE_SINGLE":
		var roman := _group_to_roman(_group_id)
		title_label.text = "ZADANIE 1\nIDENTYFIKACJA POJEDYNCZYCH KATIONÓW GRUPY %s" % roman
		_build_single_rows()
	else:
		if _group_id == 0:
			title_label.text = "ANALIZA MIESZANINY KATIONÓW GRUP I – V"
		else:
			var roman := _group_to_roman(_group_id)
			title_label.text = "ZADANIE 2\nIDENTYFIKACJA MIESZANINY KATIONÓW GRUPY %s" % roman
		_build_mix_row()


# ==================== LISTY KATIONÓW DLA GRUP ====================

## Lista jonów, które mogą wystąpić w danej grupie (0 = wszystkie).
func _ions_for_group(group_id: int) -> Array[String]:
	if group_id == 0:
		return [
			"Ag+","Hg22+","Pb2+","Hg2+","Cu2+","Bi3+","Cd2+",
			"As3+","As5+","Sb3+","Sb5+","Sn2+","Sn4+","Zn2+",
			"Ni2+","Co2+","Mn2+","Fe2+","Fe3+","Al3+","Cr3+",
			"Ca2+","Sr2+","Ba2+","Mg2+","K+","Na+","NH4+"
		]
	if group_id == 1:
		return ["Ag+","Hg22+","Pb2+"]
	if group_id == 2:
		return ["Hg2+","Pb2+","Cu2+","Bi3+","Cd2+","As3+","As5+","Sb3+","Sb5+","Sn2+","Sn4+"]
	if group_id == 3:
		return ["Zn2+","Ni2+","Co2+","Mn2+","Fe2+","Fe3+","Al3+","Cr3+"]

	# grupa IV+V
	return ["Ca2+","Sr2+","Ba2+","Mg2+","K+","Na+","NH4+"]


# ===================== BUDOWANIE UI – EX1 ========================

## Wiersze odpowiedzi dla EX1 – dla każdej probówki etykieta i rząd przycisków.
func _build_single_rows() -> void:
	_clear_items()
	_single_row_groups.clear()
	_single_row_buttons.clear()

	var slots: Array = _single_correct_map.keys()
	slots.sort()

	var ion_choices := _ions_for_group(_group_id)

	for row_idx in range(slots.size()):
		var slot_idx: int = int(slots[row_idx])

		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 40)

		var tube_label := Label.new()
		var tube_name := _slot_index_to_letter(slot_idx)
		tube_label.text = "PROBÓWKA %s:" % tube_name
		row.add_child(tube_label)

		var group := ButtonGroup.new()
		_single_row_groups.append(group)

		var buttons_box := HBoxContainer.new()
		buttons_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons_box.add_theme_constant_override("separation", 8)

		var row_buttons: Array = []
		for ion_id in ion_choices:
			var ion_button := ANSWER_BUTTON_SCENE.instantiate() as TextureButton

			ion_button.toggle_mode = true
			ion_button.button_group = group
			ion_button.focus_mode = Control.FOCUS_NONE
			ion_button.self_modulate = COLOR_NEUTRAL
			ion_button.set_meta("ion_id", ion_id)

			var label_node := ion_button.get_node("Label") as Label
			label_node.text = ION_LABELS.get(ion_id, ion_id)

			ion_button.toggled.connect(_on_answer_button_toggled.bind(ion_button))
			row_buttons.append(ion_button)
			buttons_box.add_child(ion_button)

		row.add_child(buttons_box)
		items_box.add_child(row)
		_single_row_buttons.append(row_buttons)


# ===================== BUDOWANIE UI – EX2 ========================

## UI odpowiedzi dla mieszaniny – egzamin ma kilka rzędów pogrupowanych jonów, EX2 jedną linię.
func _build_mix_row() -> void:
	_clear_items()
	_mix_buttons.clear()

	var root_box := VBoxContainer.new()
	root_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_box.alignment = BoxContainer.ALIGNMENT_CENTER
	root_box.add_theme_constant_override("separation", 16)

	var hint_label := Label.new()
	hint_label.text = "ZAZNACZ WSZYSTKIE KATIONY ZIDENTYFIKOWANE W PROBÓWCE"
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_box.add_child(hint_label)

	if _group_id == 0:
		var exam_rows: Array = []

		exam_rows.append(_ions_for_group(1))

		var group2 := _ions_for_group(2).duplicate()
		group2.erase("Pb2+")
		exam_rows.append(group2)

		exam_rows.append(_ions_for_group(3))
		exam_rows.append(["Ca2+","Sr2+","Ba2+"])
		exam_rows.append(["Mg2+","K+","Na+","NH4+"])

		for ions_in_row in exam_rows:
			var row := HBoxContainer.new()
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", 8)

			for ion_id in ions_in_row:
				var ion_button := ANSWER_BUTTON_SCENE.instantiate() as TextureButton
				ion_button.toggle_mode = true
				ion_button.focus_mode = Control.FOCUS_NONE
				ion_button.self_modulate = COLOR_NEUTRAL
				ion_button.set_meta("ion_id", ion_id)

				var label_node := ion_button.get_node("Label") as Label
				label_node.text = ION_LABELS.get(ion_id, ion_id)

				ion_button.toggled.connect(_on_answer_button_toggled.bind(ion_button))
				_mix_buttons.append(ion_button)
				row.add_child(ion_button)

			root_box.add_child(row)
	else:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 8)

		var ion_choices := _ions_for_group(_group_id)
		for ion_id in ion_choices:
			var ion_button := ANSWER_BUTTON_SCENE.instantiate() as TextureButton
			ion_button.toggle_mode = true
			ion_button.focus_mode = Control.FOCUS_NONE
			ion_button.self_modulate = COLOR_NEUTRAL
			ion_button.set_meta("ion_id", ion_id)

			var label_node := ion_button.get_node("Label") as Label
			label_node.text = ION_LABELS.get(ion_id, ion_id)

			ion_button.toggled.connect(_on_answer_button_toggled.bind(ion_button))
			_mix_buttons.append(ion_button)
			row.add_child(ion_button)

		root_box.add_child(row)

	items_box.add_child(root_box)


# ======================= KLIK W ODPOWIEDŹ ========================

## Klik w przycisk jonu – przed zatwierdzeniem tylko kolor „wybrany”.
func _on_answer_button_toggled(pressed: bool, btn: TextureButton) -> void:
	if _locked_after_submit:
		return
	btn.self_modulate = COLOR_SELECTED if pressed else COLOR_NEUTRAL


# ======================= ZATWIERDZENIE ===========================

## Zbiera odpowiedzi, liczy błędy/gwiazdki, koloruje zaznaczenia.
func _on_confirm_btn_pressed() -> void:
	if _locked_after_submit:
		return

	var mistakes := 0
	var single_user_answers: Dictionary = {}
	var mix_user_answers: Array = []

	if _exercise_mode == "EXERCISE_SINGLE":
		var slots: Array = _single_correct_map.keys()
		slots.sort()

		for row_idx in range(_single_row_groups.size()):
			var chosen_ion := ""
			for btn in _single_row_buttons[row_idx]:
				var ion_button := btn as TextureButton
				if ion_button.button_pressed:
					chosen_ion = String(ion_button.get_meta("ion_id", ion_button.name))
					break

			var slot_idx: int = int(slots[row_idx])
			single_user_answers[slot_idx] = chosen_ion

		mistakes = Settings.count_mistakes_single(_single_correct_map, single_user_answers)
	else:
		var seen: Dictionary = {}
		for btn in _mix_buttons:
			var ion_button := btn as TextureButton
			if ion_button.button_pressed:
				var ion_id: String = String(ion_button.get_meta("ion_id", ""))
				if ion_id != "" and not seen.has(ion_id):
					seen[ion_id] = true
					mix_user_answers.append(ion_id)

		mistakes = Settings.count_mistakes_mix(_mix_correct_list, mix_user_answers)

	var exercise_id := ("EX1" if _exercise_mode == "EXERCISE_SINGLE" else "EX2")

	var stars := Settings.compute_stars(
		mistakes,
		Settings.difficulty_mode,
		_group_id,
		exercise_id
	)

	var level_key := Settings.level_key_cations(_group_id, _exercise_mode)
	Settings.submit_result_cations(level_key, mistakes)

	result_box.visible = true
	_update_result_stars(stars)
	confirm_button.visible = false
	confirm_button.disabled = true
	try_again_button.visible = true

	if _exercise_mode == "EXERCISE_SINGLE":
		_apply_result_colors_single()
	else:
		_apply_result_colors_mix()

	_lock_all_choices()
	_locked_after_submit = true

	var current_key := Settings.level_key_cations(_group_id, _exercise_mode)
	var next_key := Settings.get_next_level_key_cations(current_key)
	next_button.visible = (next_key != "" and Settings.is_unlocked_cations(next_key))


# =================== KOLOROWANIE WYNIKÓW =========================

## EX1 – zaznaczone odpowiedzi na zielono/czerwono, prawidłowa na żółto jeśli nie zaznaczona.
func _apply_result_colors_single() -> void:
	var slots: Array = _single_correct_map.keys()
	slots.sort()

	for row_idx in range(slots.size()):
		var slot_idx: int = int(slots[row_idx])
		var correct_ion: String = _single_correct_map[slot_idx]

		for btn in _single_row_buttons[row_idx]:
			var ion_button := btn as TextureButton
			var ion_id: String = String(ion_button.get_meta("ion_id", ""))

			var is_correct := (ion_id == correct_ion)

			if ion_button.button_pressed:
				if is_correct:
					ion_button.self_modulate = COLOR_CORRECT
				else:
					ion_button.self_modulate = COLOR_WRONG
			else:
				if is_correct:
					ion_button.self_modulate = COLOR_TRUE_ANSWER
				else:
					ion_button.self_modulate = COLOR_NEUTRAL


## EX2 – zaznaczone jony na zielono/czerwono, wszystkie prawidłowe podświetlone.
func _apply_result_colors_mix() -> void:
	var correct_set: Dictionary = {}
	for ion_id in _mix_correct_list:
		correct_set[ion_id] = true

	for btn in _mix_buttons:
		var ion_button := btn as TextureButton
		var ion_id: String = String(ion_button.get_meta("ion_id", ""))

		var is_correct := correct_set.has(ion_id)

		if ion_button.button_pressed:
			if is_correct:
				ion_button.self_modulate = COLOR_CORRECT
			else:
				ion_button.self_modulate = COLOR_WRONG
		else:
			if is_correct:
				ion_button.self_modulate = COLOR_TRUE_ANSWER
			else:
				ion_button.self_modulate = COLOR_NEUTRAL


# =================== BLOKOWANIE PO ZATWIERDZENIU =================

## Po zatwierdzeniu blokuje wszystkie przyciski odpowiedzi.
func _lock_all_choices() -> void:
	if _exercise_mode == "EXERCISE_SINGLE":
		for row_buttons in _single_row_buttons:
			for btn in row_buttons:
				(btn as TextureButton).disabled = true
	else:
		for btn in _mix_buttons:
			(btn as TextureButton).disabled = true


# ============================= NAWIGACJA =========================

## Powrót do wyboru poziomu (kationy).
func _on_back_btn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/level_select_cations.tscn")


## Powtórka tego samego poziomu z taką samą konfiguracją.
func _on_try_again_btn_pressed() -> void:
	var is_exam := (_group_id == 0)
	var counts := Settings.compute_level_counts(_exercise_mode, is_exam)
	var cfg: Dictionary = {
		"mode": _exercise_mode,
		"group_id": _group_id,
		"starter_count": counts.starter_count,
		"mix_difficulty": counts.mix_difficulty,
		"branch": "CATIONS"
	}

	Settings.set_next_level_config(cfg)
	get_tree().change_scene_to_file("res://scenes/lab.tscn")


## Jeśli jest kolejny poziom – odpala go, inaczej wraca do wyboru poziomu.
func _on_next_btn_pressed() -> void:
	var curr_key := Settings.level_key_cations(_group_id, _exercise_mode)
	var next_key := Settings.get_next_level_key_cations(curr_key)
	if next_key == "":
		get_tree().change_scene_to_file("res://scenes/menu/level_select_cations.tscn")
		return
	_start_next_level_from_key(next_key)


## Zamienia klucz poziomu na konfigurację i przełącza na lab.
func _start_next_level_from_key(next_key: String) -> void:
	var next_group_id := 0
	var next_mode := "EXERCISE_SINGLE"
	var is_exam := false

	if next_key == "EXAM":
		is_exam = true
		next_mode = "EXERCISE_MIX"
		next_group_id = 0
	else:
		var parts: Array = next_key.split("_")
		var num_str: String = String(parts[0]).substr(1)  # "1","2","3","45"
		next_group_id = 4 if num_str == "45" else int(num_str)
		next_mode = "EXERCISE_SINGLE" if parts[1] == "EX1" else "EXERCISE_MIX"

	var counts := Settings.compute_level_counts(next_mode, is_exam)
	var cfg: Dictionary = {
		"mode": next_mode,
		"group_id": next_group_id,
		"starter_count": counts.starter_count,
		"mix_difficulty": counts.mix_difficulty,
		"branch": "CATIONS"
	}

	Settings.set_next_level_config(cfg)
	get_tree().change_scene_to_file("res://scenes/lab.tscn")


# ============================ POMOCNICZE =========================

## Czyści listę wierszy odpowiedzi.
func _clear_items() -> void:
	for child in items_box.get_children():
		child.queue_free()


## Ustawia widoczność gwiazdek w wierszu podsumowania.
func _update_result_stars(stars: int) -> void:
	stars = clamp(stars, 0, 3)
	for i in range(result_stars_row.get_child_count()):
		var slot := result_stars_row.get_child(i)
		var star := slot.get_node("Star") as CanvasItem
		star.visible = (i < stars)


## Zamienia indeks probówki (0,1,2…) na literę (A,B,C,...).
func _slot_index_to_letter(slot_idx: int) -> String:
	if slot_idx >= 0 and slot_idx < START_TUBE_LABELS.size():
		return START_TUBE_LABELS[slot_idx]
	return str(slot_idx + 1)
