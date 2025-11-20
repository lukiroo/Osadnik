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
	# Wynik tekstowy czyścimy na starcie.
	grade_label.text = ""

	# Kontekst z Settings (ustawiony w Lab.gd przy kliknięciu „Zakończ i sprawdź”).
	var ctx: Dictionary = Settings.get_last_run_context()
	_mode_str       = String(ctx.get("mode_str", "EXERCISE_SINGLE"))
	_group_id       = int(ctx.get("group_id", 1))
	_correct_single = ctx.get("single_answer_map", {}) as Dictionary
	_correct_mix    = ctx.get("mix_answer_list", []) as Array

	# Czy przycisk „Dalej” ma być od razu widoczny (jeśli kolejny poziom już odblokowany).
	var current_key: String = Settings.level_key(_group_id, _mode_str)
	var next_key: String = Settings.get_next_level_key(current_key)
	var can_go_next: bool = (next_key != "" and Settings.is_unlocked(next_key))
	next_button.visible = can_go_next

	# Budowa layoutu w zależności od trybu ćwiczenia.
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
## Zwraca listę dopuszczalnych kationów dla danej grupy.
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
## Tworzy wiersze z radiobuttonami dla ćwiczenia 1 (jedna odpowiedź na probówkę).
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
## Buduje siatkę checkboxów dla ćwiczenia 2 (dowolna liczba zaznaczeń).
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
## Kliknięcie „Zatwierdź” – liczenie wyniku, gwiazdek i aktualizacja progresu.
func _on_confirm_btn_pressed() -> void:
	if _locked_after_submit:
		return

	var total_answers: int = 0
	var correct_answers: int = 0
	var mistakes: int = 0
	var passed: bool = false

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

	passed = (mistakes <= Settings.max_errors_allowed())

	# Zaktualizuj progres levelu.
	var level_key: String = Settings.level_key(_group_id, _mode_str)
	Settings.submit_result(level_key, mistakes)

	# Tekst wyniku.
	grade_label.text = "Wynik: {0}/{1} poprawnych".format([
		int(correct_answers),
		int(total_answers)
	])

	if passed:
		grade_label.text += " — ZALICZONE"
	else:
		grade_label.text += " — NIEZALICZONE (błędy: {0}, limit: {1})".format([
			int(mistakes),
			int(Settings.max_errors_allowed())
		])

	# Gwiazdki jako liczba (bez symboli).
	var stars: int = _compute_stars(Settings.difficulty_mode, mistakes)
	grade_label.text += "\nGwiazdki: {0}/3".format([stars])

	# Zablokuj wybory, ukryj „Zatwierdź”, pokaż „Spróbuj ponownie”.
	_lock_all_choices()
	confirm_button.disabled = true
	confirm_button.visible = false
	_locked_after_submit = true
	try_again_button.visible = true

	# Stan „Dalej”: jeśli kolejny poziom jest odblokowany (mogło się właśnie zmienić).
	var current_key: String = Settings.level_key(_group_id, _mode_str)
	var next_key: String = Settings.get_next_level_key(current_key)
	var can_go_next: bool = (next_key != "" and Settings.is_unlocked(next_key))
	next_button.visible = can_go_next


# ───────────────────────── GWIAZDKI (LOKALNA WERSJA) ─────────────
## Lokalna wersja liczenia gwiazdek (spójna z Settings.max_errors_allowed()).
func _compute_stars(difficulty: int, mistakes: int) -> int:
	if mistakes > Settings.max_errors_allowed():
		return 0
	if difficulty == 0: # normalny
		return 2 if mistakes == 0 else 1
	else: # trudny
		return 3 if mistakes == 0 else 2


# ───────────────────────── BLOKADA WYBORÓW ───────────────────────
## Po zatwierdzeniu – blokuje wszystkie przyciski/checkboxy odpowiedzi.
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
	get_tree().change_scene_to_file("res://scenes/lab.tscn")

func _on_next_btn_pressed() -> void:
	var curr_key: String = Settings.level_key(_group_id, _mode_str)
	var next_key: String = Settings.get_next_level_key(curr_key)
	if next_key == "":
		get_tree().change_scene_to_file("res://scenes/menu/level_select.tscn")
		return
	_start_next_level_from_key(next_key)


# ───────────────────────── START KOLEJNEGO LEVELU ────────────────
## Mapuje klucz typu "G1_EX2"/"G45_EX1"/"EXAM" na config Settings i odpala lab.
func _start_next_level_from_key(next_key: String) -> void:
	var next_group_id: int = 0
	var next_mode_str: String = "EXERCISE_SINGLE"
	var is_exam: bool = false

	if next_key == "EXAM":
		is_exam = true
		next_mode_str = "EXERCISE_MIX"
		next_group_id = 0
	else:
		# Format: "G<NUM>_EX1" lub "G<NUM>_EX2", gdzie NUM to "1","2","3" lub "45".
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
## Zamienia indeks slotu (0,1,2,...) na literę probówki: A,B,C,...
## Dla indeksu spoza tabelki awaryjnie zwraca numer (1-based).
func _slot_index_to_letter(slot_idx: int) -> String:
	if slot_idx >= 0 and slot_idx < START_TUBE_LABELS.size():
		return START_TUBE_LABELS[slot_idx]
	return str(slot_idx + 1)
