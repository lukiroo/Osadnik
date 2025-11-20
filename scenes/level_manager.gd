extends Node
class_name LevelManager

## =========================================================================
## LevelManager – losowanie kationów, spawn probówek i numerowanie
## -------------------------------------------------------------------------
## Odpowiada za:
## - odczyt konfiguracji levelu z autoloada Settings (tryb, grupa, itp.),
## - spawn probówek startowych (z kationami) oraz roboczych (pustych),
## - przechowywanie poprawnych odpowiedzi dla EX1 (mapa slot → kation)
##   oraz EX2 (lista kationów w mieszance),
## - nadawanie etykiet probówkom:
##     * racki robocze: numery 1, 2, 3, ...
##     * beaker startowy w EX1: litery A, B, C, D, E,
## - udostępnianie danych dla ekranu wyników
##   (get_single_answer_map, get_mix_answer_list).
## =========================================================================

# ───────────────────────── TRYB PRACY I PODSTAWOWA KONFIG ─────────────────
enum Mode { SANDBOX, EXERCISE_SINGLE, EXERCISE_MIX }

@export var mode: Mode = Mode.EXERCISE_SINGLE
@export_range(0, 4, 1) var group_id: int = 1           ## 0 = tryb egzaminu

@export var starter_count: int = 3                     ## Ile startowych probówek w EX1.
@export_range(1, 5, 1) var mix_difficulty: int = 2     ## Ile kationów w mieszance w EX2.

# ───────────────────────── REFERENCJE SCENY ───────────────────────────────
@onready var probe_beaker: Node2D = $"../ProbeBeaker"  ## Zlewka z probówką do identyfikacji.

@export var starter_probe_scene: PackedScene           ## Scena probówki startowej.
@export var work_probe_scene: PackedScene              ## Scena probówki roboczej.

# ───────────────────────── STAŁE WIZUALNE ─────────────────────────────────
const WORK_LABEL_FONT_SIZE: int = 20
const STARTER_LABEL_FONT_SIZE: int = 13

# ───────────────────────── STAN ODPOWIEDZI I PROBÓWEK ─────────────────────
## EX1: mapa „slot indeks → kation”.
var _single_answer_map: Dictionary = {} 
## EX2: lista kationów w mieszance.
var _mix_answer_list: Array[String] = []

## Referencje do spawnowanych probówek
var _starter_probes: Array[Node2D] = []
var _work_probes: Array[Node2D] = []

# ───────────────────────── PARAMETRY CHEMICZNE MIESZANKI ──────────────────
@export var mix_cation_amount: int = 100               ## „Porcja” ładunku na każdy kation w mieszance.


# =================================================================
# INIT – konfiguracja startowa levelu
# =================================================================
func _ready() -> void:
	## Korekta zakresów (na wypadek nietypowych wartości z Inspectora).
	starter_count = clamp(starter_count, 1, 12)
	mix_difficulty = clamp(mix_difficulty, 1, 5)

	## Autoload Settings może przekazać konfigurację kolejnego levelu.
	var settings_node := get_tree().get_root().get_node_or_null("Settings")
	if settings_node and settings_node.has_method("get_and_clear_next_level_config"):
		var cfg: Dictionary = settings_node.get_and_clear_next_level_config()
		if not cfg.is_empty():
			if cfg.has("mode"):
				var mode_str := String(cfg["mode"])
				mode = Mode.EXERCISE_SINGLE if mode_str == "EXERCISE_SINGLE" else Mode.EXERCISE_MIX
			if cfg.has("group_id"):
				group_id = int(cfg["group_id"])
			if cfg.has("starter_count"):
				starter_count = int(cfg["starter_count"])
			if cfg.has("mix_difficulty"):
				mix_difficulty = int(cfg["mix_difficulty"])

	if starter_probe_scene == null:
		push_warning("[LevelManager] starter_probe_scene nie ustawione w Inspectorze.")
	if work_probe_scene == null:
		push_warning("[LevelManager] work_probe_scene nie ustawione w Inspectorze.")

	## Docelowy spawn probówek dopiero po starcie sceny.
	call_deferred("respawn_level")


# =================================================================
# METODY WYWOŁYWANE Z ZEWNĄTRZ
# =================================================================

## Reset levelu: czyści probówki w slotach i tworzy konfigurację od nowa.
func respawn_level() -> void:
	_clear_all_slots("starter_slots")
	_clear_all_slots("work_slots")

	_single_answer_map.clear()
	_mix_answer_list.clear()
	_starter_probes.clear()
	_work_probes.clear()

	match mode:
		Mode.SANDBOX:
			_setup_sandbox()
		Mode.EXERCISE_SINGLE:
			_setup_exercise_single()
		Mode.EXERCISE_MIX:
			_setup_exercise_mix()

	print(
		"[LM] starters=", _starter_probes.size(),
		" single_answers=", _single_answer_map.size(),
		" mix=", _mix_answer_list
	)

	## Po spawnie probówek odświeża highlighty
	var lab_root := get_tree().get_first_node_in_group("lab_root")
	if lab_root != null and lab_root.has_method("_refresh_probe_highlights"):
		lab_root._refresh_probe_highlights()


## EX1 – zwraca kopię mapy odpowiedzi (slot → kation).
func get_single_answer_map() -> Dictionary:
	return _single_answer_map.duplicate(true)


## EX2 – zwraca kopię listy kationów w mieszance.
func get_mix_answer_list() -> Array[String]:
	return _mix_answer_list.duplicate()


## Używane np. przy zmianie opcji etykiet – ponownie nadaje numerację.
func relabel_now() -> void:
	_relabel_group("work_slots")
	_relabel_group("starter_slots")


# =================================================================
# KONFIGURACJA LEVELU – TRYBY SANDBOX / EX1 / EX2
# =================================================================

## Prosty sandbox – wyłącznie probówki robocze
func _setup_sandbox() -> void:
	_spawn_work_tubes()


## EXERCISE_SINGLE – kilka startowych probówek z pojedynczym kationem + probówki robocze.
func _setup_exercise_single() -> void:
	if probe_beaker:
		probe_beaker.visible = true

	var group_cations: Array[String] = _get_group_cations(group_id)
	if group_cations.is_empty():
		push_warning("Brak kationów dla grupy %d" % group_id)
		return

	var chosen_ids: Array[String] = _pick_distinct(group_cations, starter_count)

	var starter_slots: Array = _get_slots("starter_slots")
	var count: int = min(starter_slots.size(), chosen_ids.size())

	for i in count:
		var cation_id: String = String(chosen_ids[i])
		var solution: Mixture = _make_simple_solution(cation_id)
		var tube: Node2D = _instantiate_probe_as_starter(solution)
		if tube:
			_snap_to_slot(tube, starter_slots[i])
			_starter_probes.append(tube)
			## Uwaga: kluczem jest indeks slotu (0..), a nie tekst na etykiecie.
			_single_answer_map[i] = cation_id

	_spawn_work_tubes()


## EXERCISE_MIX – jedna probówka startowa z mieszanką + probówki robocze.
func _setup_exercise_mix() -> void:
	if probe_beaker:
		probe_beaker.visible = true

	var group_cations: Array[String] = _get_group_cations(group_id)
	if group_cations.is_empty():
		push_warning("Brak kationów dla grupy %d" % group_id)
		return

	var chosen_ids: Array[String] = _pick_distinct(group_cations, mix_difficulty)
	_mix_answer_list = chosen_ids

	var mix_solution: Mixture = _make_multi_solution(chosen_ids)

	## Szukamy sceny z węzłem Lab (bezpośrednio lub jako dziecko).
	var lab_scene: Node = get_tree().current_scene
	if lab_scene == null:
		push_error("[LevelManager] Brak current_scene.")
		return

	if lab_scene.name != "Lab":
		var lab_candidate := lab_scene.get_node_or_null("Lab")
		if lab_candidate:
			lab_scene = lab_candidate

	var beaker_node := lab_scene.get_node_or_null("ProbeBeaker")
	if beaker_node == null:
		push_error("[LevelManager] Brak węzła 'ProbeBeaker'.")
		return
	var first_slot := beaker_node.get_node_or_null("ProbeSlot1")
	if first_slot == null:
		push_error("[LevelManager] Brak węzła 'ProbeBeaker/ProbeSlot1'.")
		return

	var starter_tube: Node2D = _instantiate_probe_as_starter(mix_solution)
	if starter_tube:
		_snap_to_slot(starter_tube, first_slot)
		_starter_probes.append(starter_tube)

	_spawn_work_tubes()


# =================================================================
# SPAWN PROBÓWEK ROBOCZYCH
# =================================================================

## Spawnuje puste probówki robocze w slotach z grupy „work_slots”.
func _spawn_work_tubes() -> void:
	var work_slots: Array = []
	for slot in get_tree().get_nodes_in_group("work_slots"):
		if slot is Node and slot.has_method("accept_probe"):
			work_slots.append(slot)

	if work_slots.is_empty():
		push_warning("[LevelManager] Brak slotów w grupie 'work_slots'.")
		return

	## Sortowanie po współrzędnej X, żeby kolejność była intuicyjna.
	work_slots.sort_custom(
		func(a, b) -> bool:
			return a.global_position.x < b.global_position.x
	)

	for slot in work_slots:
		var is_taken: bool = (slot.has_method("is_occupied") and bool(slot.call("is_occupied")))
		if is_taken:
			continue

		var tube: Node2D = _instantiate_probe_as_work_empty()
		if tube == null:
			continue

		var target_pos: Vector2 = slot.global_position
		if slot.has_method("get_anchor_global"):
			var anchor_val: Variant = slot.call("get_anchor_global")
			if anchor_val is Vector2:
				target_pos = anchor_val

		var accepted: bool = false
		if slot.has_method("accept_probe"):
			accepted = bool(slot.call("accept_probe", tube, target_pos))
		if not accepted:
			slot.add_child(tube)
			tube.global_position = target_pos

		_label_probe_for_slot(tube, slot)
		_work_probes.append(tube)


# =================================================================
# FABRYKA PROBÓWEK (INSTANTIATE)
# =================================================================

## Tworzy probówkę startową z podaną mieszaniną (pełna, „duża”).
func _instantiate_probe_as_starter(mix: Mixture) -> Node2D:
	var scene: PackedScene = starter_probe_scene if starter_probe_scene != null else work_probe_scene
	if scene == null:
		push_error("[LevelManager] Brak sceny probówki startowej.")
		return null

	var tube: Probe = scene.instantiate() as Probe
	if tube == null:
		push_error("[LevelManager] instantiate() zwróciło obiekt, który nie jest Probe (starter).")
		return null

	# Ustawiamy podstawowe parametry bez kombinowania z property_list:
	tube.tube_role = Probe.TubeRole.STARTER
	tube.mixture = mix
	tube.fill_level = 1.0

	# Upewniamy się, że wizualny poziom cieczy jest spójny ze stanem.
	if tube.has_method("_apply_liquid_fill_visual"):
		tube._apply_liquid_fill_visual()

	return tube


## Tworzy pustą probówkę roboczą (rola „WORK”).
func _instantiate_probe_as_work_empty() -> Node2D:
	var scene: PackedScene = work_probe_scene if work_probe_scene != null else starter_probe_scene
	if scene == null:
		push_error("[LevelManager] Brak sceny probówki roboczej.")
		return null

	var tube: Probe = scene.instantiate() as Probe
	if tube == null:
		push_error("[LevelManager] instantiate() zwróciło obiekt, który nie jest Probe (work).")
		return null

	# Pusta probówka robocza – nowa mieszanina, brak cieczy na starcie.
	tube.tube_role = Probe.TubeRole.WORK
	tube.mixture = Mixture.new()
	tube.fill_level = 0.0

	if tube.has_method("_apply_liquid_fill_visual"):
		tube._apply_liquid_fill_visual()

	return tube


# =================================================================
# SLOTY I DOKOWANIE
# =================================================================

## Zwraca listę slotów z danej grupy, które mają metodę `accept_probe`.
func _get_slots(group_name: String) -> Array:
	var slot_list: Array = []
	for node in get_tree().get_nodes_in_group(group_name):
		if node is Node and node.has_method("accept_probe"):
			slot_list.append(node)
	return slot_list


## Dokuje probówkę w danym slocie, w razie potrzeby szukając innego wolnego.
func _snap_to_slot(probe: Node2D, slot: Node) -> void:
	if probe == null or slot == null:
		return

	## Jeśli slot jest zajęty i nie ma flagi `allow_when_occupied`, szukamy alternatywy.
	if slot.has_method("is_occupied") and slot.call("is_occupied") and not bool(slot.get("allow_when_occupied")):
		var group_name := "starter_slots" if slot.is_in_group("starter_slots") else "work_slots"
		for candidate in _get_slots(group_name):
			if not (candidate.has_method("is_occupied") and candidate.call("is_occupied")):
				slot = candidate
				break

	if probe.get_parent():
		probe.get_parent().remove_child(probe)
	slot.add_child(probe)

	var anchor_pos: Vector2 = slot.global_position
	if slot.has_method("get_anchor_global"):
		anchor_pos = slot.call("get_anchor_global") as Vector2

	probe.global_position = anchor_pos

	if slot.has_method("accept_probe"):
		slot.call("accept_probe", probe, anchor_pos)

	_label_probe_for_slot(probe, slot)


## Usuwa probówki (z grupy „probes”) ze wszystkich slotów danej grupy.
func _clear_all_slots(group_name: String) -> void:
	for slot in _get_slots(group_name):
		for child in slot.get_children():
			if child is Node and child.is_in_group("probes"):
				child.queue_free()


# =================================================================
# NUMEROWANIE / ETYKIETY PROBÓWEK
# =================================================================

## Ustawia etykietę probówki na podstawie slotu i trybu.
func _label_probe_for_slot(probe: Node2D, slot: Node) -> void:
	if probe == null or slot == null:
		return

	var container_name: String = ""
	var parent := slot.get_parent()
	if parent:
		container_name = String(parent.name)

	var slot_index: int = _parse_slot_index(String(slot.name))
	if slot_index <= 0:
		_hide_probe_label(probe)
		return

	match container_name:
		"ProbeRack1":
			## Pierwszy stojak – numery 1, 2, 3, ...
			_set_probe_num_label(probe, str(slot_index), WORK_LABEL_FONT_SIZE, false)

		"ProbeRack2":
			## Drugi stojak – kontynuacja (np. 6, 7, ...).
			_set_probe_num_label(probe, str(5 + slot_index), WORK_LABEL_FONT_SIZE, false)

		"ProbeBeaker":
			## Beaker – startowe probówki w EX1 mają litery A..E.
			match mode:
				Mode.EXERCISE_SINGLE:
					if slot_index <= starter_count:
						var letter_label := _index_to_letter(slot_index)
						## W EX1 litery zawsze widoczne, niezależnie od opcji Settings.
						_set_probe_num_label(probe, letter_label, STARTER_LABEL_FONT_SIZE, true)
					else:
						_hide_probe_label(probe)
				Mode.EXERCISE_MIX:
					_hide_probe_label(probe)
				_:
					_hide_probe_label(probe)

		_:
			_hide_probe_label(probe)


## Wyciąga numeryczną końcówkę z nazwy slotu, np. "ProbeSlot3" → 3.
func _parse_slot_index(slot_name: String) -> int:
	var re := RegEx.new()
	re.compile("(\\d+)$")
	var match := re.search(slot_name)
	if match:
		return int(match.get_string(1))
	return -1


## Przelicza etykiety probówek w slotach danej grupy.
func _relabel_group(group_name: String) -> void:
	for slot in _get_slots(group_name):
		var tube := _find_probe_in_slot(slot)
		if tube:
			_label_probe_for_slot(tube, slot)


## Szuka probówki w danym slocie (przez metodę get_probe lub grupę „probes”).
func _find_probe_in_slot(slot: Node) -> Node2D:
	if slot.has_method("get_probe"):
		return slot.call("get_probe") as Node2D
	for child in slot.get_children():
		if child is Node and child.is_in_group("probes"):
			return child as Node2D
	return null


## Ustawia tekst etykiety, biorąc pod uwagę globalne ustawienia (Settings.show_tube_labels).
func _set_probe_num_label(
	probe: Node2D,
	text: String,
	font_size: int = -1,
	force_visible: bool = false
) -> void:
	var lbl: Label = probe.get_node_or_null("NumLabel") as Label
	if lbl == null:
		var any := probe.find_child("NumLabel", true, false)
		if any is Label:
			lbl = any as Label
	if lbl == null:
		return

	lbl.text = text

	var show_labels: bool = true
	if not force_visible:
		var settings_node := get_tree().get_root().get_node_or_null("Settings")
		if settings_node != null and "show_tube_labels" in settings_node:
			show_labels = bool(settings_node.show_tube_labels)

	lbl.visible = show_labels or force_visible

	if font_size > 0:
		lbl.add_theme_font_size_override("font_size", font_size)


## Ukrywa etykietę probówki (jeśli istnieje).
func _hide_probe_label(probe: Node2D) -> void:
	var lbl: Label = probe.get_node_or_null("NumLabel") as Label
	if lbl == null:
		var any := probe.find_child("NumLabel", true, false)
		if any is Label:
			lbl = any as Label
	if lbl:
		lbl.visible = false


## Zamienia indeks slotu (1..5) na literę A..E (dla beakera).
func _index_to_letter(index: int) -> String:
	var letters := ["A", "B", "C", "D", "E"]
	if index >= 1 and index <= letters.size():
		return letters[index - 1]
	## Fallback (gdyby kiedyś slotów było więcej niż liter).
	return str(index)


# =================================================================
# DANE CHEMICZNE / LOSOWANIE
# =================================================================

## Zwraca listę kationów dla danej grupy (albo wszystkich, gdy group == 0).
func _get_group_cations(group: int) -> Array[String]:
	if group == 0:
		var all: Array[String] = []
		all += ["Ag+", "Hg2 2+", "Pb2+"]
		all += ["Hg2+", "Pb2+", "Cu2+", "Cd2+", "Bi3+", "As3+", "As5+", "Sb3+", "Sb5+", "Sn2+", "Sn4+"]
		all += ["Zn2+", "Ni2+", "Co2+", "Mn2+", "Fe2+", "Fe3+", "Al3+", "Cr3+"]
		all += ["Ca2+", "Sr2+", "Ba2+", "Mg2+", "K+", "Na+", "NH4+"]
		return all

	match group:
		1:
			return ["Ag+", "Hg2 2+", "Pb2+"]
		2:
			return ["Hg2+", "Pb2+", "Cu2+", "Cd2+", "Bi3+", "As3+", "As5+", "Sb3+", "Sb5+", "Sn2+", "Sn4+"]
		3:
			return ["Zn2+", "Ni2+", "Co2+", "Mn2+", "Fe2+", "Fe3+", "Al3+", "Cr3+"]
		4:
			return ["Ca2+", "Sr2+", "Ba2+", "Mg2+", "K+", "Na+", "NH4+"]
		_:
			return []


## Losuje n różnych kationów z podanej puli.
func _pick_distinct(pool: Array[String], n: int) -> Array[String]:
	var tmp: Array[String] = pool.duplicate()
	tmp.shuffle()
	var count: int = min(n, tmp.size())
	var out: Array[String] = []
	for i in count:
		out.append(tmp[i])
	return out


## Tworzy prosty roztwór z jednym kationem (EX1).
func _make_simple_solution(cation_id: String) -> Mixture:
	var mix := Mixture.new()
	mix.add_ions({cation_id: 100, "NO3-": 1})
	return mix


## Tworzy roztwór z kilkoma kationami (EX2).
func _make_multi_solution(cation_ids: Array[String]) -> Mixture:
	var mix := Mixture.new()
	var ions_dict: Dictionary = {}

	for c in cation_ids:
		ions_dict[c] = mix_cation_amount

	if ions_dict.size() > 0:
		ions_dict["NO3-"] = cation_ids.size() * mix_cation_amount

	mix.add_ions(ions_dict)
	return mix
