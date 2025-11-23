extends Node
class_name LevelManager

## =========================================================================
## LevelManager – losowanie kationów, spawn probówek, numerowanie, reagenty
## -------------------------------------------------------------------------
## - czyta konfigurację levelu (mode, group_id, itp.),
## - spawnuje probówki startowe / robocze,
## - przechowuje poprawne odpowiedzi (EX1, EX2),
## - nadaje etykiety probówkom,
## - ustawia reagenty w butelkach na półce.
## =========================================================================

# ───────────────────────── TRYB PRACY I PARAMETRY ─────────────────
enum Mode { SANDBOX, EXERCISE_SINGLE, EXERCISE_MIX }

var mode: Mode = Mode.EXERCISE_SINGLE
var group_id: int = 1
var starter_count: int = 3
var mix_difficulty: int = 2

# ───────────────────────── REFERENCJE SCENY ───────────────────────────────
@onready var probe_beaker:  Node2D = $"../ProbeBeaker1"   ## Zlewka dla ćw. 1
@onready var probe_beaker2: Node2D = $"../ProbeBeaker2"   ## Zlewka dla ćw. 2 + egzamin
@onready var reagent_shelf: Node2D = $"../ReagentShelf"   ## Półka z butelkami reagentów

const STARTER_PROBE_SCENE: PackedScene     = preload("res://scenes/starter_probe.tscn")
const BIG_STARTER_PROBE_SCENE: PackedScene = preload("res://scenes/starter_probe_big.tscn")
const WORK_PROBE_SCENE: PackedScene        = preload("res://scenes/work_probe.tscn")

# ───────────────────────── REAGENTY ─────────────────────────────
const REAGENT_PATH_PREFIX := "res://data/reagents/"
const REAGENT_PATH_SUFFIX := ".tres"

# ───────────────────────── CZCIONKA ─────────────────────────────────
const WORK_LABEL_FONT_SIZE: int = 20
const STARTER_LABEL_FONT_SIZE: int = 13

# ───────────────────────── PARAMETRY CHEMICZNE ────────────────────────────
## Ile „sztuk” kationu w pojedynczej probówki startowej w EX1.
const STARTER_CATION_AMOUNT: int = 100
## Ile „sztuk” kationu na KAŻDY kation w mieszance (EX2 / egzamin).
const MIX_CATION_AMOUNT: int = 500

# ───────────────────────── STAN ODPOWIEDZI I PROBÓWEK ─────────────────────
## EX1: mapa „slot indeks → kation”.
var _single_answer_map: Dictionary = {}
## EX2: lista kationów w mieszance.
var _mix_answer_list: Array[String] = []

## Referencje do spawnowanych probówek
var _starter_probes: Array[Node2D] = []
var _work_probes: Array[Node2D] = []


# =================================================================
# INIT – konfiguracja startowa levelu
# =================================================================
func _ready() -> void:
	starter_count = clamp(starter_count, 1, 12)
	mix_difficulty = clamp(mix_difficulty, 1, 5)

	# Konfiguracja levelu przekazana z LevelSelect (Settings)
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

	call_deferred("respawn_level")


# =================================================================
# METODY WYWOŁYWANE Z ZEWNĄTRZ
# =================================================================
func respawn_level() -> void:
	_clear_all_slots("starter_slots")
	_clear_all_slots("work_slots")
	_clear_reagent_bottles()

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

	_spawn_reagents_for_current_level()

	var lab_root := get_tree().get_first_node_in_group("lab_root")
	if lab_root != null and lab_root.has_method("_refresh_probe_highlights"):
		lab_root._refresh_probe_highlights()


func get_single_answer_map() -> Dictionary:
	return _single_answer_map.duplicate(true)


func get_mix_answer_list() -> Array[String]:
	return _mix_answer_list.duplicate()


func relabel_now() -> void:
	_relabel_group("work_slots")
	_relabel_group("starter_slots")


# =================================================================
# KONFIGURACJA LEVELU – TRYBY SANDBOX / EX1 / EX2
# =================================================================
func _setup_sandbox() -> void:
	_spawn_work_tubes()


func _setup_exercise_single() -> void:
	# Ćwiczenie 1 – klasyczna zlewka i normalne probówki startowe.
	if probe_beaker:
		probe_beaker.visible = true
	if probe_beaker2:
		probe_beaker2.visible = false

	var group_cations: Array[String] = _get_group_cations(group_id)
	if group_cations.is_empty():
		push_error("[LevelManager] Brak kationów dla grupy %d" % group_id)
		return

	var chosen_ids: Array[String] = _pick_distinct(group_cations, starter_count)
	var starter_slots: Array = _get_slots("starter_slots")
	var count: int = min(starter_slots.size(), chosen_ids.size())

	for i in count:
		var cation_id: String = String(chosen_ids[i])
		var solution: Mixture = _make_simple_solution(cation_id)
		var tube: Node2D = _instantiate_probe_as_starter(solution, false) # normalna startowa
		if tube:
			_snap_to_slot(tube, starter_slots[i])
			_starter_probes.append(tube)
			_single_answer_map[i] = cation_id

	_spawn_work_tubes()


func _setup_exercise_mix() -> void:
	# Ćwiczenie 2 + egzamin – nowa zlewka i duża probówka startowa.
	if probe_beaker:
		probe_beaker.visible = false
	if probe_beaker2:
		probe_beaker2.visible = true

	var group_cations: Array[String] = _get_group_cations(group_id)
	if group_cations.is_empty():
		push_error("[LevelManager] Brak kationów dla grupy %d" % group_id)
		return

	var chosen_ids: Array[String] = []

	if group_id == 0:
		# ─────────────────────────────────────────────
		# EXAM: losujemy po jednym kationie z każdej
		# grupy Freseniusa (G1..G4, maksymalnie 4).
		# ─────────────────────────────────────────────
		var shuffled := group_cations.duplicate()
		shuffled.shuffle()

		var used_groups: Dictionary = {}
		var max_total :Variant= min(mix_difficulty, 4)

		for cid in shuffled:
			if chosen_ids.size() >= max_total:
				break
			var g := _fresenius_group_for_cation(String(cid))
			if g <= 0:
				continue
			if used_groups.has(g):
				continue
			used_groups[g] = true
			chosen_ids.append(String(cid))

		# awaryjnie – gdyby z jakiegoś powodu nic nie weszło,
		# wracamy do zwykłego losowania, żeby nie zabić levelu
		if chosen_ids.is_empty():
			chosen_ids = _pick_distinct(group_cations, mix_difficulty)
	else:
		# zwykłe EX2: stare zachowanie
		chosen_ids = _pick_distinct(group_cations, mix_difficulty)

	_mix_answer_list = chosen_ids

	var mix_solution: Mixture = _make_multi_solution(chosen_ids)

	# Wybierz odpowiednią zlewkę: preferuj ProbeBeaker2, fallback na ProbeBeaker1.
	var beaker_node: Node2D = probe_beaker2 if probe_beaker2 != null else probe_beaker
	if beaker_node == null:
		push_error("[LevelManager] Brak węzła ProbeBeaker2 ani ProbeBeaker1.")
		return

	var first_slot := beaker_node.get_node_or_null("ProbeSlot1")
	if first_slot == null:
		push_error("[LevelManager] Brak węzła '%s/ProbeSlot1'." % beaker_node.name)
		return

	var starter_tube: Node2D = _instantiate_probe_as_starter(mix_solution, true) # duża startowa
	if starter_tube:
		_snap_to_slot(starter_tube, first_slot)
		_starter_probes.append(starter_tube)

	_spawn_work_tubes()


# =================================================================
# REAGENTY – LISTY PER LEVEL I KONFIG BUTELEK
# =================================================================
func _get_reagent_ids_for_current_level() -> Array[String]:
	var ids: Array[String] = []

	match mode:
		Mode.SANDBOX:
			ids = ["HCl", "NaOH"]

		Mode.EXERCISE_SINGLE, Mode.EXERCISE_MIX:
			match group_id:
				1:
					ids = ["HCl", "NaOH", "KI", "KBr", "K2CrO4"]
				2:
					ids = ["HCl", "NaOH", "KI", "KBr", "Pb(NO3)2"]
				3:
					ids = ["HCl", "NaOH", "KI", "KBr", "Pb(NO3)2"]
				4:
					ids = ["HCl", "NaOH", "KI", "KBr", "Pb(NO3)2"]
				0:
					# egzamin – na razie ta sama lista
					ids = ["HCl", "NaOH", "KI", "KBr", "Pb(NO3)2"]
				_:
					ids = []

	return ids


## Zwraca listę butelek z półki, posortowanych po numerze z nazwy (Bottle1, Bottle2, ...).
func _get_reagent_bottles() -> Array[ReagentBottle]:
	var out: Array[ReagentBottle] = []
	if reagent_shelf == null:
		return out

	for child in reagent_shelf.get_children():
		if child is ReagentBottle:
			out.append(child as ReagentBottle)

	out.sort_custom(func(a, b) -> bool:
		return _parse_slot_index(String(a.name)) < _parse_slot_index(String(b.name))
	)

	return out


## Czyści butelki: chowa je i wyzerowuje reagent.
func _clear_reagent_bottles() -> void:
	for bottle in _get_reagent_bottles():
		bottle.reagent = null
		bottle.visible = false


func _load_reagent_by_id(id: String) -> Reagent:
	var safe_id := id.strip_edges()
	if safe_id == "":
		return null

	var path := REAGENT_PATH_PREFIX + safe_id + REAGENT_PATH_SUFFIX
	var res := ResourceLoader.load(path)
	if res == null:
		# Po prostu nie ustawiamy reagentu, bez ostrzeżeń.
		return null

	return res as Reagent


## Ustawia reagenty w gotowych butelkach na półce.
func _spawn_reagents_for_current_level() -> void:
	var bottles: Array[ReagentBottle] = _get_reagent_bottles()
	if bottles.is_empty():
		return

	var ids: Array[String] = _get_reagent_ids_for_current_level()
	if ids.is_empty():
		_clear_reagent_bottles()
		return

	var count: int = min(bottles.size(), ids.size())

	for i in bottles.size():
		if i < count:
			var reagent_res: Reagent = _load_reagent_by_id(ids[i])
			if reagent_res:
				bottles[i].reagent = reagent_res
				bottles[i].visible = true
			else:
				bottles[i].reagent = null
				bottles[i].visible = false
		else:
			bottles[i].reagent = null
			bottles[i].visible = false


# =================================================================
# SPAWN PROBÓWEK ROBOCZYCH
# =================================================================
func _spawn_work_tubes() -> void:
	var work_slots: Array = []
	for slot in get_tree().get_nodes_in_group("work_slots"):
		if slot is Node and slot.has_method("accept_probe"):
			work_slots.append(slot)

	if work_slots.is_empty():
		return

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
# SPAWN PROBÓWEK
# =================================================================
func _instantiate_probe_as_starter(mix: Mixture, use_big: bool = false) -> Node2D:
	var scene: PackedScene = null
	if use_big:
		scene = BIG_STARTER_PROBE_SCENE
	else:
		scene = STARTER_PROBE_SCENE

	if scene == null:
		push_error("[LevelManager] Brak sceny probówki startowej.")
		return null

	var tube: Probe = scene.instantiate() as Probe
	if tube == null:
		push_error("[LevelManager] instantiate() zwróciło obiekt, który nie jest Probe (starter).")
		return null

	tube.tube_role = Probe.TubeRole.STARTER
	tube.mixture = mix
	tube.fill_level = 1.0
	tube.draggable = false        # startery w beakerze mają być nieruchome

	if tube.has_method("_apply_liquid_fill_visual"):
		tube._apply_liquid_fill_visual()

	return tube


func _instantiate_probe_as_work_empty() -> Node2D:
	var scene: PackedScene = WORK_PROBE_SCENE
	if scene == null:
		push_error("[LevelManager] Brak sceny probówki roboczej.")
		return null

	var tube: Probe = scene.instantiate() as Probe
	if tube == null:
		push_error("[LevelManager] instantiate() zwróciło obiekt, który nie jest Probe (work).")
		return null

	tube.tube_role = Probe.TubeRole.WORK
	tube.mixture = Mixture.new()
	tube.fill_level = 0.0

	if tube.has_method("_apply_liquid_fill_visual"):
		tube._apply_liquid_fill_visual()

	return tube


# =================================================================
# SLOTY / ETYKIETY / LOSOWANIE
# =================================================================
func _get_slots(group_name: String) -> Array:
	var slot_list: Array = []
	for node in get_tree().get_nodes_in_group(group_name):
		if node is Node and node.has_method("accept_probe"):
			slot_list.append(node)
	return slot_list


func _snap_to_slot(probe: Node2D, slot: Node) -> void:
	if probe == null or slot == null:
		return

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


func _clear_all_slots(group_name: String) -> void:
	for slot in _get_slots(group_name):
		for child in slot.get_children():
			if child is Node and child.is_in_group("probes"):
				child.queue_free()


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
			_set_probe_num_label(probe, str(slot_index), WORK_LABEL_FONT_SIZE, false)
		"ProbeRack2":
			_set_probe_num_label(probe, str(5 + slot_index), WORK_LABEL_FONT_SIZE, false)
		"ProbeBeaker1", "ProbeBeaker2":
			match mode:
				Mode.EXERCISE_SINGLE:
					if slot_index <= starter_count:
						var letter_label := _index_to_letter(slot_index)
						_set_probe_num_label(probe, letter_label, STARTER_LABEL_FONT_SIZE, true)
					else:
						_hide_probe_label(probe)
				Mode.EXERCISE_MIX:
					_hide_probe_label(probe)
				_:
					_hide_probe_label(probe)
		_:
			_hide_probe_label(probe)


func _parse_slot_index(slot_name: String) -> int:
	var re := RegEx.new()
	re.compile("(\\d+)$")
	var match := re.search(slot_name)
	if match:
		return int(match.get_string(1))
	return -1


func _relabel_group(group_name: String) -> void:
	for slot in _get_slots(group_name):
		var tube := _find_probe_in_slot(slot)
		if tube:
			_label_probe_for_slot(tube, slot)


func _find_probe_in_slot(slot: Node) -> Node2D:
	if slot.has_method("get_probe"):
		return slot.call("get_probe") as Node2D
	for child in slot.get_children():
		if child is Node and child.is_in_group("probes"):
			return child as Node2D
	return null


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


func _hide_probe_label(probe: Node2D) -> void:
	var lbl: Label = probe.get_node_or_null("NumLabel") as Label
	if lbl == null:
		var any := probe.find_child("NumLabel", true, false)
		if any is Label:
			lbl = any as Label
	if lbl:
		lbl.visible = false


func _index_to_letter(index: int) -> String:
	var letters := ["A", "B", "C", "D", "E"]
	if index >= 1 and index <= letters.size():
		return letters[index - 1]
	return str(index)


# =================================================================
# LISTY KATIONÓW + LOSOWANIE
# =================================================================
func _get_group_cations(group: int) -> Array[String]:
	if group == 0:
		var all: Array[String] = []
		all += ["Ag+", "Hg22+", "Pb2+"]
		all += ["Hg2+", "Pb2+", "Cu2+", "Cd2+", "Bi3+", "As3+", "As5+", "Sb3+", "Sb5+", "Sn2+", "Sn4+"]
		all += ["Zn2+", "Ni2+", "Co2+", "Mn2+", "Fe2+", "Fe3+", "Al3+", "Cr3+"]
		all += ["Ca2+", "Sr2+", "Ba2+", "Mg2+", "K+", "Na+", "NH4+"]
		return all

	match group:
		1:
			return ["Ag+", "Hg22+", "Pb2+"]
		2:
			return ["Hg2+", "Pb2+", "Cu2+", "Cd2+", "Bi3+", "As3+", "As5+", "Sb3+", "Sb5+", "Sn2+", "Sn4+"]
		3:
			return ["Zn2+", "Ni2+", "Co2+", "Mn2+", "Fe2+", "Fe3+", "Al3+", "Cr3+"]
		4:
			return ["Ca2+", "Sr2+", "Ba2+", "Mg2+", "K+", "Na+", "NH4+"]
		_:
			return []


func _pick_distinct(pool: Array[String], n: int) -> Array[String]:
	var tmp: Array[String] = pool.duplicate()
	tmp.shuffle()
	var count: int = min(n, tmp.size())
	var out: Array[String] = []
	for i in count:
		out.append(tmp[i])
	return out


func _fresenius_group_for_cation(cation_id: String) -> int:
	# Mapa kation -> grupa Freseniusa (1..4).
	# Pb2+ przypisujemy do grupy 1, żeby uniknąć podwójnej przynależności.
	if cation_id in ["Ag+", "Hg22+", "Pb2+"]:
		return 1
	elif cation_id in ["Hg2+", "Cu2+", "Cd2+", "Bi3+", "As3+", "As5+", "Sb3+", "Sb5+", "Sn2+", "Sn4+"]:
		return 2
	elif cation_id in ["Zn2+", "Ni2+", "Co2+", "Mn2+", "Fe2+", "Fe3+", "Al3+", "Cr3+"]:
		return 3
	elif cation_id in ["Ca2+", "Sr2+", "Ba2+", "Mg2+", "K+", "Na+", "NH4+"]:
		return 4
	return -1


func _make_simple_solution(cation_id: String) -> Mixture:
	var mix := Mixture.new()
	mix.add_ions({cation_id: STARTER_CATION_AMOUNT, "NO3-": STARTER_CATION_AMOUNT})
	return mix


func _make_multi_solution(cation_ids: Array[String]) -> Mixture:
	var mix := Mixture.new()
	var ions_dict: Dictionary = {}

	for c in cation_ids:
		ions_dict[c] = MIX_CATION_AMOUNT

	if ions_dict.size() > 0:
		ions_dict["NO3-"] = cation_ids.size() * MIX_CATION_AMOUNT

	mix.add_ions(ions_dict)
	return mix
