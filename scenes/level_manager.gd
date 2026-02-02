extends Node
class_name LevelManager

## =========================================================================
## level_manager.gd – losowanie próbek, spawn probówek, numerowanie, reagenty
## -------------------------------------------------------------------------
## Odpowiada za:
## - odczyt konfiguracji poziomu (mode, group_id, branch: kationy/aniony/sandbox),
## - przygotowanie probówek startowych do analizy (EX1 / EX2 / egzamin – sprawdzian z analizy wszystkich grup),
## - losowanie składu mieszanin i zapamiętanie poprawnych odpowiedzi,
## - spawn probówek startowych w zlewce i roboczych do pracy na stojakach,
## - nadawanie etykiet probówkom (literki/numerki),
## - ustawianie reagentów w butelkach na półce.
## =========================================================================

# -------------------------- TRYB PRACY / PARAMETRY ------------------------
enum Mode { SANDBOX, EXERCISE_SINGLE, EXERCISE_MIX }
enum Branch { CATIONS, ANIONS, SANDBOX }

var mode: Mode = Mode.EXERCISE_SINGLE
var branch: Branch = Branch.CATIONS

var group_id: int = 1
var starter_count: int = 3
var mix_difficulty: int = 2

# -------------------------- REFERENCJE SCENY ------------------------------
@onready var probe_beaker1: Node2D = $"../ProbeBeaker1"   ## Zlewka EX1 Normal (3 probówki)
@onready var probe_beaker2: Node2D = $"../ProbeBeaker2"   ## Zlewka EX1 Hard (5 probówek)
@onready var probe_beaker3: Node2D = $"../ProbeBeaker3"   ## Zlewka EX2 + egzamin (1 probówka)
@onready var reagent_shelf: Node2D = $"../ReagentShelf"   ## Półka z butelkami reagentów

const STARTER_PROBE_SCENE: PackedScene     = preload("res://scenes/starter_probe.tscn")
const BIG_STARTER_PROBE_SCENE: PackedScene = preload("res://scenes/starter_probe_big.tscn")
const WORK_PROBE_SCENE: PackedScene        = preload("res://scenes/work_probe.tscn")

# -------------------------- ŚCIEŻKI ZASOBÓW REAGENTÓW ---------------------
const REAGENT_PATH_PREFIX := "res://data/reagents/"
const REAGENT_PATH_SUFFIX := ".tres"

# -------------------------- CZCIONKI ETYKIET ------------------------------
const WORK_LABEL_FONT_SIZE: int = 20
const STARTER_LABEL_FONT_SIZE: int = 13

# -------------------------- PARAMETRY „ILOŚCIOWE” -------------------------
## EX1 – ilość jonów w pojedynczej probówce startowej.
const STARTER_CATION_AMOUNT: int = 100
## EX2 / egzamin – ilość jonów na każdy składnik mieszaniny.
const MIX_CATION_AMOUNT: int = 160

# -------------------------- STAN POPRAWNYCH ODPOWIEDZI -------------------
## EX1: mapa „indeks probówki → jon” (kation/anion; indeks odpowiada literkom A/B/C...).
var _single_answer_map: Dictionary = {}
## EX2: lista jonów w mieszaninie (kolejność nie ma znaczenia).
var _mix_answer_list: Array[String] = []


# =================================================================
# INICJALIZACJA – odczyt konfiguracji poziomu z Settings i start budowania levelu
# =================================================================
func _ready() -> void:
	# Odczyt konfiguracji poziomu z węzła Settings (jeśli istnieje).
	var settings_node := get_tree().get_root().get_node_or_null("Settings")
	var cfg: Dictionary = {}
	if settings_node and settings_node.has_method("get_and_clear_next_level_config"):
		cfg = settings_node.get_and_clear_next_level_config()

	if not cfg.is_empty():
		# Odczyt trybu poziomu (SANDBOX / EXERCISE_SINGLE / EXERCISE_MIX).
		if cfg.has("mode"):
			var mode_str := String(cfg["mode"])
			if mode_str == "SANDBOX":
				mode = Mode.SANDBOX
			elif mode_str == "EXERCISE_MIX":
				mode = Mode.EXERCISE_MIX
			else:
				mode = Mode.EXERCISE_SINGLE

		# Odczyt parametrów poziomu (grupa, liczba probówek, trudność mieszaniny).
		if cfg.has("group_id"):
			group_id = int(cfg["group_id"])
		if cfg.has("starter_count"):
			starter_count = int(cfg["starter_count"])
		if cfg.has("mix_difficulty"):
			mix_difficulty = int(cfg["mix_difficulty"])

		# Odczyt gałęzi (kationy / aniony / sandbox).
		if cfg.has("branch"):
			var branch_str := String(cfg["branch"])
			if branch_str == "ANIONS":
				branch = Branch.ANIONS
			elif branch_str == "SANDBOX":
				branch = Branch.SANDBOX
			else:
				branch = Branch.CATIONS
		else:
			# Gdy nie podano branch – sandbox → SANDBOX, reszta → CATIONS.
			branch = Branch.SANDBOX if mode == Mode.SANDBOX else Branch.CATIONS
	else:
		# Brak konfiguracji – ustawienie sensownej domyślnej gałęzi.
		branch = Branch.SANDBOX if mode == Mode.SANDBOX else Branch.CATIONS

	# Ograniczenie parametrów do sensownych zakresów (zabezpieczenie przed dziwnym cfg).
	starter_count = clamp(starter_count, 1, 12)
	mix_difficulty = clamp(mix_difficulty, 1, 5)

	# Uruchomienie budowania poziomu po zakończeniu inicjalizacji sceny.
	call_deferred("respawn_level")


# =================================================================
# METODY WYWOŁYWANE Z ZEWNĄTRZ (Lab / inne sceny)
# =================================================================

## Czyści i ponownie buduje cały level (probówki, mieszaniny, reagenty).
func respawn_level() -> void:
	_clear_all_slots("starter_slots")
	_clear_all_slots("work_slots")
	_clear_reagent_bottles()

	_single_answer_map.clear()
	_mix_answer_list.clear()

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


## Zwraca kopię mapy poprawnych odpowiedzi dla EX1 (do Results).
func get_single_answer_map() -> Dictionary:
	return _single_answer_map.duplicate(true)


## Zwraca listę prawidłowych jonów mieszaniny dla EX2 / egzaminu.
func get_mix_answer_list() -> Array[String]:
	return _mix_answer_list.duplicate()


## Przelicza etykiety probówek (np. po ręcznym przeniesieniu między slotami).
func relabel_now() -> void:
	_relabel_group("work_slots")
	_relabel_group("starter_slots")


## Helpery dla lab.gd – sprawdzanie gałęzi ścieżki.
func is_cations_branch() -> bool:
	return branch == Branch.CATIONS

func is_anions_branch() -> bool:
	return branch == Branch.ANIONS

func is_sandbox_branch() -> bool:
	return branch == Branch.SANDBOX

# =================================================================
# MAPOWANIE: forma spawnowana w probówce -> forma kationowa do odpowiedzi
# =================================================================
func _answer_id_for_spawned_id(spawn_id: String) -> String:
	match spawn_id:
		"AsO33-":
			return "As3+"
		"AsO43-":
			return "As5+"
		_:
			return spawn_id

# =================================================================
# MAPOWANIE DO ODPOWIEDZI W MIESZANINIE (EX2 / EGZAMIN)
# - w mieszaninie nie rozróżniamy stopni utlenienia: As / Sb / Sn
# =================================================================
func _mix_answer_id_for_spawned_id(spawn_id: String) -> String:
	match spawn_id:
		# arsen (u Ciebie w probówce spawnuje się jako AsO33- albo AsO43-)
		"AsO33-", "AsO43-":
			return "As"
		# antymon
		"Sb3+", "Sb5+":
			return "Sb"
		# cyna
		"Sn2+", "Sn4+":
			return "Sn"
		_:
			return spawn_id


# =================================================================
# LOSOWANIE DO MIESZANINY (EX2)
# - nie pozwala wylosować naraz dwóch form tego samego pierwiastka:
#   As(III)+As(V) / Sb(III)+Sb(V) / Sn(II)+Sn(IV)
# =================================================================
func _pick_distinct_for_mix(pool: Array[String], n: int) -> Array[String]:
	var tmp: Array[String] = pool.duplicate()
	tmp.shuffle()

	var used: Dictionary = {}
	var out: Array[String] = []

	for id in tmp:
		var key := _mix_answer_id_for_spawned_id(String(id)) # np. AsO33- -> "As"
		if used.has(key):
			continue
		used[key] = true
		out.append(String(id))
		if out.size() >= n:
			break

	return out


# =================================================================
# Buduje listę poprawnych odpowiedzi do EX2/egzaminu na bazie spawn_id
# - mapuje AsO33-/AsO43- -> As, Sb3+/Sb5+ -> Sb, Sn2+/Sn4+ -> Sn
# - usuwa duplikaty
# =================================================================
func _build_mix_answers_from_spawn_ids(spawn_ids: Array[String]) -> Array[String]:
	var out: Array[String] = []
	var seen: Dictionary = {}

	for spawn_id in spawn_ids:
		var ans := _mix_answer_id_for_spawned_id(String(spawn_id))
		if not seen.has(ans):
			seen[ans] = true
			out.append(ans)

	return out


# =================================================================
# KONFIGURACJA LEVELU – SANDBOX / EX1 / EX2
# =================================================================

## Ustawia tryb sandbox: beakery są wyłączone, tylko puste probówki robocze na stojakach.
func _setup_sandbox() -> void:
	if probe_beaker1:
		probe_beaker1.visible = false
	if probe_beaker2:
		probe_beaker2.visible = false
	if probe_beaker3:
		probe_beaker3.visible = false

	_spawn_work_tubes()


## Przygotowuje EX1 – probówki startowe z pojedynczym jonem (kation lub anion) w beakerze.
## - starter_count <= 3   → ProbeBeaker1 (3 sloty, Normal)
## - starter_count >  3   → ProbeBeaker2 (5 slotów, Hard)
func _setup_exercise_single() -> void:
	# EX1 nie używa ProbeBeaker3.
	if probe_beaker3:
		probe_beaker3.visible = false

	var use_big_beaker: bool = starter_count > 3
	var active_beaker_name := ""

	# Ustawia widoczność zlewek startowych i wybiera aktywną.
	if use_big_beaker:
		if probe_beaker1:
			probe_beaker1.visible = false
		if probe_beaker2:
			probe_beaker2.visible = true
		active_beaker_name = "ProbeBeaker2"
	else:
		if probe_beaker1:
			probe_beaker1.visible = true
		if probe_beaker2:
			probe_beaker2.visible = false
		active_beaker_name = "ProbeBeaker1"

	# Wybiera tylko sloty starter_slots należące do aktywnej zlewki.
	var starter_slots: Array = _get_slots("starter_slots")
	if starter_slots.is_empty():
		return

	var filtered_slots: Array = []
	for slot in starter_slots:
		var parent_node: Variant = slot.get_parent()
		if parent_node and String(parent_node.name) == active_beaker_name:
			filtered_slots.append(slot)

	starter_slots = filtered_slots
	if starter_slots.is_empty():
		return

	if branch == Branch.ANIONS:
		# Ścieżka anionowa – probówki z pojedynczym anionem.
		var group_anions: Array[String] = _get_group_anions(group_id)
		if group_anions.is_empty():
			push_error("[LevelManager] Brak anionów dla grupy %d" % group_id)
			return

		var selected_anions: Array[String] = _pick_distinct(group_anions, starter_count)
		var tube_count: int = min(starter_slots.size(), selected_anions.size())

		for i in tube_count:
			var anion_id: String = String(selected_anions[i])
			var solution: Mixture = _make_simple_anion_solution(anion_id)
			var tube: Node2D = _instantiate_probe_as_starter(solution, false)
			if tube:
				_snap_to_slot(tube, starter_slots[i])
				_single_answer_map[i] = anion_id
	else:
		# Ścieżka kationowa – probówki z pojedynczym kationem.
		var group_cations: Array[String] = _get_group_cations(group_id)
		if group_cations.is_empty():
			push_error("[LevelManager] Brak kationów dla grupy %d" % group_id)
			return

		var selected_cations: Array[String] = _pick_distinct(group_cations, starter_count)
		var tube_count_cations: int = min(starter_slots.size(), selected_cations.size())

		for i in tube_count_cations:
			var spawn_id: String = String(selected_cations[i]) # to co spawnuje się do Mixture (np. AsO33-)
			var solution_cation: Mixture = _make_simple_cation_solution(spawn_id)
			var tube_cation: Node2D = _instantiate_probe_as_starter(solution_cation, false)
			if tube_cation:
				_snap_to_slot(tube_cation, starter_slots[i])

			# do odpowiedzi zapisuje formę "kationową"
			_single_answer_map[i] = _answer_id_for_spawned_id(spawn_id)

	# Po ustawieniu probówek startowych uruchamia probówki robocze na stojakach.
	_spawn_work_tubes()


## Przygotowuje EX2 / egzamin – jedną większą probówkę startową z mieszaniną jonów w ProbeBeaker3.
func _setup_exercise_mix() -> void:
	# W EX2/egzaminie używany jest tylko ProbeBeaker3.
	if probe_beaker1:
		probe_beaker1.visible = false
	if probe_beaker2:
		probe_beaker2.visible = false
	if probe_beaker3:
		probe_beaker3.visible = true

	var beaker_node: Node2D = probe_beaker3
	if beaker_node == null:
		push_error("[LevelManager] Brak węzła ProbeBeaker3 (zlewka EX2/egzamin).")
		return

	var first_slot := beaker_node.get_node_or_null("ProbeSlot1")
	if first_slot == null:
		push_error("[LevelManager] Brak węzła '%s/ProbeSlot1'." % beaker_node.name)
		return

	var chosen_ids: Array[String] = []
	var mix_solution: Mixture = null

	if branch == Branch.ANIONS:
		# Ścieżka anionowa – mieszanina kilku anionów.
		var group_anions: Array[String] = _get_group_anions(group_id)
		if group_anions.is_empty():
			push_error("[LevelManager] Brak anionów dla grupy %d" % group_id)
			return

		if group_id == 0:
			# Egzamin anionowy: dobiera aniony z różnych grup (1..5), bez powtórzeń grup.
			var shuffled_anions := group_anions.duplicate()
			shuffled_anions.shuffle()

			var used_anion_groups: Dictionary = {}
			var max_anion_count: Variant = min(mix_difficulty, 5)

			for anion_candidate_id in shuffled_anions:
				if chosen_ids.size() >= max_anion_count:
					break
				var group_index := _group_for_anion(String(anion_candidate_id))
				if group_index <= 0:
					continue
				if used_anion_groups.has(group_index):
					continue
				used_anion_groups[group_index] = true
				chosen_ids.append(String(anion_candidate_id))

			# Awaryjnie: gdyby zła konfiguracja, losuje zwykłą listę z puli.
			if chosen_ids.is_empty():
				chosen_ids = _pick_distinct(group_anions, mix_difficulty)
		else:
			# Zwykłe EX2 – kilka anionów z jednej zadanej grupy.
			chosen_ids = _pick_distinct(group_anions, mix_difficulty)

		_mix_answer_list = chosen_ids
		mix_solution = _make_multi_anion_solution(chosen_ids)
	else:
		# Ścieżka kationowa – mieszanina kationów.
		var group_cations: Array[String] = _get_group_cations(group_id)
		if group_cations.is_empty():
			push_error("[LevelManager] Brak kationów dla grupy %d" % group_id)
			return

		if group_id == 0:
			# Egzamin: po jednym kationie z każdej grupy (G1..G4), bez powtórzeń grup.
			var shuffled_cations := group_cations.duplicate()
			shuffled_cations.shuffle()

			var used_cation_groups: Dictionary = {}
			var max_cation_count: Variant = min(mix_difficulty, 4)

			for cation_candidate_id in shuffled_cations:
				if chosen_ids.size() >= max_cation_count:
					break
				var group_index_cation := _group_for_cation(String(cation_candidate_id))
				if group_index_cation <= 0:
					continue
				if used_cation_groups.has(group_index_cation):
					continue
				used_cation_groups[group_index_cation] = true
				chosen_ids.append(String(cation_candidate_id))

			# Awaryjnie: gdyby nic nie weszło, losuje zwykłą listę z puli.
			if chosen_ids.is_empty():
				chosen_ids = _pick_distinct(group_cations, mix_difficulty)

		else:
			# Zwykłe EX2 – kilka kationów z jednej zadanej grupy.
			# Tu blokujemy sytuację AsO33-+AsO43- / Sb3+ + Sb5+ / Sn2+ + Sn4+ w jednej mieszaninie.
			chosen_ids = _pick_distinct_for_mix(group_cations, mix_difficulty)

		# EX2 + EGZAMIN: odpowiedzi uproszczone (As/Sb/Sn), reszta bez zmian
		_mix_answer_list = _build_mix_answers_from_spawn_ids(chosen_ids)
		mix_solution = _make_multi_cation_solution(chosen_ids)


	if mix_solution == null:
		return

	# Tworzy jedną dużą probówkę startową z mieszaniną i przypina do first_slot.
	var starter_tube: Node2D = _instantiate_probe_as_starter(mix_solution, true)
	if starter_tube:
		_snap_to_slot(starter_tube, first_slot)

	# Tworzy probówki robocze na stojakach.
	_spawn_work_tubes()


# =================================================================
# REAGENTY – listy na półkę (sandbox / kationy / aniony)
# =================================================================

## Zwraca listę identyfikatorów reagentów dla aktualnego poziomu.
func _get_reagent_ids_for_current_level() -> Array[String]:
	if branch == Branch.SANDBOX:
		return _get_reagent_ids_for_sandbox()
	elif branch == Branch.CATIONS:
		return _get_reagent_ids_for_cations()
	elif branch == Branch.ANIONS:
		return _get_reagent_ids_for_anions()
	return []


## Zwraca listę odczynników do sandboxa.
func _get_reagent_ids_for_sandbox() -> Array[String]:
	return ["HCl", "HCl_3M", "AKT", "HNO3", "HNO2", "NaOH", "NaOH_3M", "NH4OH", "KI", "KBr", "K2CrO4", "Na2CO3","NH3NH4Cl","KCN", "KSCN", "K(Sb(OH)6)", "K2(HgI4)", "magnezon", 
			"AgNO3", "Ba(NO3)2", "H2SO4", "FeCl3", "CuSO4", "Pb(NO3)2", "Cd(NO3)2"]


## Zwraca listę odczynników dla ścieżki kationowej dla danej grupy.
func _get_reagent_ids_for_cations() -> Array[String]:
	var ids: Array[String] = []

	match group_id:
		1:
			ids = ["HCl", "HCl_3M", "AKT", "HNO3", "HNO2", "NaOH", "NaOH_3M", "NH4OH", "KI", "KBr", "K2CrO4", "Na2CO3","NH3NH4Cl","KCN", "KSCN", "K(Sb(OH)6)", "K2(HgI4)", "magnezon", 
			"AgNO3", "Ba(NO3)2", "H2SO4", "FeCl3", "CuSO4", "Pb(NO3)2", "Cd(NO3)2"]
		2:
			ids = ["HCl", "HCl_3M", "AKT", "HNO3", "HNO2", "NaOH", "NaOH_3M", "NH4OH", "KI", "KBr", "K2CrO4", "Na2CO3","NH3NH4Cl","KCN", "KSCN", "K(Sb(OH)6)", "K2(HgI4)", "magnezon", 
			"AgNO3", "Ba(NO3)2", "H2SO4", "FeCl3", "CuSO4", "Pb(NO3)2", "Cd(NO3)2"]
		3:
			ids = ["HCl", "HCl_3M", "AKT", "HNO3", "HNO2", "NaOH", "NaOH_3M", "NH4OH", "KI", "KBr", "K2CrO4", "Na2CO3","NH3NH4Cl","KCN", "KSCN", "K(Sb(OH)6)", "K2(HgI4)", "magnezon", 
			"AgNO3", "Ba(NO3)2", "H2SO4", "FeCl3", "CuSO4", "Pb(NO3)2", "Cd(NO3)2"]
		4:
			ids = ["HCl", "HCl_3M", "AKT", "HNO3", "HNO2", "NaOH", "NaOH_3M", "NH4OH", "KI", "KBr", "K2CrO4", "Na2CO3","NH3NH4Cl","KCN", "KSCN", "K(Sb(OH)6)", "K2(HgI4)", "magnezon", 
			"AgNO3", "Ba(NO3)2", "H2SO4", "FeCl3", "CuSO4", "Pb(NO3)2", "Cd(NO3)2"]
		0:
			# Sprawdzian z kationów
			ids = ["HCl", "HCl_3M", "AKT", "HNO3", "HNO2", "NaOH", "NaOH_3M", "NH4OH", "KI", "KBr", "K2CrO4", "Na2CO3","NH3NH4Cl","KCN", "KSCN", "K(Sb(OH)6)", "K2(HgI4)", "magnezon", 
			"AgNO3", "Ba(NO3)2", "H2SO4", "FeCl3", "CuSO4", "Pb(NO3)2", "Cd(NO3)2"]
		_:
			ids = []

	return ids


## Zwraca listę odczynników dla ścieżki anionowej dla danej grupy.
func _get_reagent_ids_for_anions() -> Array[String]:
	var ids: Array[String] = []

	match group_id:
		1:
			# Grupa I: Cl-, Br-, I-, CN-, SCN-
			ids = ["HCl", "HCl_3M", "AKT", "HNO3", "HNO2", "NaOH", "NaOH_3M", "NH4OH", "KI", "KBr", "K2CrO4", "Na2CO3","NH3NH4Cl","KCN", "KSCN", "K(Sb(OH)6)", "K2(HgI4)", "magnezon", 
			"AgNO3", "Ba(NO3)2", "H2SO4", "FeCl3", "CuSO4", "Pb(NO3)2", "Cd(NO3)2"]
		2:
			# Grupa II: S2-, CH3COO-, NO2-
			ids = ["HCl", "HCl_3M", "AKT", "HNO3", "HNO2", "NaOH", "NaOH_3M", "NH4OH", "KI", "KBr", "K2CrO4", "Na2CO3","NH3NH4Cl","KCN", "KSCN", "K(Sb(OH)6)", "K2(HgI4)", "magnezon", 
			"AgNO3", "Ba(NO3)2", "H2SO4", "FeCl3", "CuSO4", "Pb(NO3)2", "Cd(NO3)2"]
		3:
			# Grupa III: SO32-, CO32-, BO2-
			ids = ["HCl", "HCl_3M", "AKT", "HNO3", "HNO2", "NaOH", "NaOH_3M", "NH4OH", "KI", "KBr", "K2CrO4", "Na2CO3","NH3NH4Cl","KCN", "KSCN", "K(Sb(OH)6)", "K2(HgI4)", "magnezon", 
			"AgNO3", "Ba(NO3)2", "H2SO4", "FeCl3", "CuSO4", "Pb(NO3)2", "Cd(NO3)2"]
		4:
			# Grupa IV: CrO42-, AsO33-, AsO43-, PO43-
			ids = ["HCl", "HCl_3M", "AKT", "HNO3", "HNO2", "NaOH", "NaOH_3M", "NH4OH", "KI", "KBr", "K2CrO4", "Na2CO3","NH3NH4Cl","KCN", "KSCN", "K(Sb(OH)6)", "K2(HgI4)", "magnezon", 
			"AgNO3", "Ba(NO3)2", "H2SO4", "FeCl3", "CuSO4", "Pb(NO3)2", "Cd(NO3)2"]
		5:
			# Grupa V+VI: NO3-, ClO3-, ClO4-, MnO4-, SO42-, F-
			ids = ["HCl", "HCl_3M", "AKT", "HNO3", "HNO2", "NaOH", "NaOH_3M", "NH4OH", "KI", "KBr", "K2CrO4", "Na2CO3","NH3NH4Cl","KCN", "KSCN", "K(Sb(OH)6)", "K2(HgI4)", "magnezon", 
			"AgNO3", "Ba(NO3)2", "H2SO4", "FeCl3", "CuSO4", "Pb(NO3)2", "Cd(NO3)2"]
		0:
			# Sprawdzian anionowy
			ids = ["HCl", "HCl_3M", "AKT", "HNO3", "HNO2", "NaOH", "NaOH_3M", "NH4OH", "KI", "KBr", "K2CrO4", "Na2CO3","NH3NH4Cl","KCN", "KSCN", "K(Sb(OH)6)", "K2(HgI4)", "magnezon", 
			"AgNO3", "Ba(NO3)2", "H2SO4", "FeCl3", "CuSO4", "Pb(NO3)2", "Cd(NO3)2"]
		_:
			ids = []

	return ids


## Zwraca listę butelek z półki, posortowaną wg numeru w nazwie (Bottle1, Bottle2...).
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


## Czyści wszystkie butelki: ukrywa je i usuwa przypisane reagenty.
func _clear_reagent_bottles() -> void:
	for bottle in _get_reagent_bottles():
		bottle.reagent = null
		bottle.visible = false


## Ładuje zasób Reagent na podstawie jego identyfikatora (np. "HCl").
func _load_reagent_by_id(id: String) -> Reagent:
	var safe_id := id.strip_edges()
	if safe_id == "":
		return null

	var path := REAGENT_PATH_PREFIX + safe_id + REAGENT_PATH_SUFFIX
	var res := ResourceLoader.load(path)
	if res == null:
		return null

	return res as Reagent


## Ustawia reagenty w butelkach na półce zgodnie z aktualną listą.
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

## Tworzy puste probówki robocze we wszystkich wolnych slotach stojaków.
func _spawn_work_tubes() -> void:
	var work_slots: Array = []
	for slot in get_tree().get_nodes_in_group("work_slots"):
		if slot is Node and slot.has_method("accept_probe"):
			work_slots.append(slot)

	if work_slots.is_empty():
		return

	# Porządkuje sloty po X – ułatwia numerację probówek.
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
			
			if slot.has_method("on_probe_returned"):
				slot.call("on_probe_returned", tube)

		_label_probe_for_slot(tube, slot)


# =================================================================
# SPAWN PROBÓWEK STARTOWYCH
# =================================================================

## Tworzy probówkę startową (małą lub dużą) z podaną mieszaniną.
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
	tube.draggable = false   # startery w zlewce są nieruchome

	if tube.has_method("_apply_liquid_fill_visual"):
		tube._apply_liquid_fill_visual()

	return tube


## Tworzy pustą probówkę roboczą.
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

## Zwraca listę slotów z podanej grupy (starter_slots / work_slots).
func _get_slots(group_name: String) -> Array:
	var slot_list: Array = []
	for node in get_tree().get_nodes_in_group(group_name):
		if node is Node and node.has_method("accept_probe"):
			slot_list.append(node)
	return slot_list


## Przypina probówkę do slotu, ustawia jej pozycję i etykietę.
func _snap_to_slot(probe: Node2D, slot: Node) -> void:
	if probe == null or slot == null:
		return

	# Gdy slot jest zajęty i nie dopuszcza duplikatów – wybiera inny wolny slot z tej samej grupy.
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


## Usuwa wszystkie probówki z danej grupy slotów.
func _clear_all_slots(group_name: String) -> void:
	for slot in _get_slots(group_name):
		for child in slot.get_children():
			if child is Node and child.is_in_group("probes"):
				child.queue_free()


## Nadaje probówce etykietę zależnie od stojaka i indeksu slotu.
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
			_set_probe_num_label(probe, str(6 + slot_index), WORK_LABEL_FONT_SIZE, false)
		"ProbeBeaker1", "ProbeBeaker2", "ProbeBeaker3":
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


## Wyciąga numer z nazwy slotu (np. „ProbeSlot3” → 3).
func _parse_slot_index(slot_name: String) -> int:
	var re := RegEx.new()
	re.compile("(\\d+)$")
	var match := re.search(slot_name)
	if match:
		return int(match.get_string(1))
	return -1


## Przelicza etykiety dla wszystkich slotów z danej grupy.
func _relabel_group(group_name: String) -> void:
	for slot in _get_slots(group_name):
		var tube := _find_probe_in_slot(slot)
		if tube:
			_label_probe_for_slot(tube, slot)


## Szuka probówki w danym slocie (przez get_probe lub dzieci grupy „probes”).
func _find_probe_in_slot(slot: Node) -> Node2D:
	if slot.has_method("get_probe"):
		return slot.call("get_probe") as Node2D
	for child in slot.get_children():
		if child is Node and child.is_in_group("probes"):
			return child as Node2D
	return null


## Ustawia tekst etykiety probówki, rozmiar fontu i widoczność.
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


## Ukrywa etykietę probówki.
func _hide_probe_label(probe: Node2D) -> void:
	var lbl: Label = probe.get_node_or_null("NumLabel") as Label
	if lbl == null:
		var any := probe.find_child("NumLabel", true, false)
		if any is Label:
			lbl = any as Label
	if lbl:
		lbl.visible = false


## Zamienia indeks (1,2,3,...) na literę (A,B,C,...) do oznaczania probówek w zlewce.
func _index_to_letter(index: int) -> String:
	var letters := ["A", "B", "C", "D", "E"]
	if index >= 1 and index <= letters.size():
		return letters[index - 1]
	return str(index)



# =================================================================
# LISTY KATIONÓW + LOSOWANIE
# =================================================================

## Zwraca listę kationów z danej grupy Freseniusa (lub wszystkie, gdy group == 0).
func _get_group_cations(group: int) -> Array[String]:
	var g1: Array[String] = ["Ag+", "Hg22+", "Pb2+"]
	var g2: Array[String] = ["Hg2+", "Pb2+", "Cu2+", "Cd2+", "Bi3+", "AsO33-", "AsO43-", "Sb3+", "Sb5+", "Sn2+", "Sn4+"]
	var g3: Array[String] = ["Zn2+", "Ni2+", "Co2+", "Mn2+", "Fe2+", "Fe3+", "Al3+", "Cr3+"]
	var g4: Array[String]= ["Ca2+", "Sr2+", "Ba2+", "Mg2+", "K+", "Na+", "NH4+"]

	if group == 0:
		var all: Array[String] = []
		all.append_array(g1)
		all.append_array(g2)
		all.append_array(g3)
		all.append_array(g4)
		return all

	match group:
		1:
			return g1
		2:
			return g2
		3:
			return g3
		4:
			return g4
		_:
			return []


## Losuje n różnych pozycji z danej listy (bez powtórzeń).
func _pick_distinct(pool: Array[String], n: int) -> Array[String]:
	var tmp: Array[String] = pool.duplicate()
	tmp.shuffle()
	var count: int = min(n, tmp.size())
	var out: Array[String] = []
	for i in count:
		out.append(tmp[i])
	return out


## Zwraca numer grupy (1–4) dla danego kationu.
func _group_for_cation(cation_id: String) -> int:
	if cation_id in ["Ag+", "Hg22+", "Pb2+"]:
		return 1
	elif cation_id in ["Hg2+", "Cu2+", "Cd2+", "Bi3+", "AsO33-", "AsO43-", "Sb3+", "Sb5+", "Sn2+", "Sn4+"]:
		return 2
	elif cation_id in ["Zn2+", "Ni2+", "Co2+", "Mn2+", "Fe2+", "Fe3+", "Al3+", "Cr3+"]:
		return 3
	elif cation_id in ["Ca2+", "Sr2+", "Ba2+", "Mg2+", "K+", "Na+", "NH4+"]:
		return 4
	return -1


## Tworzy prosty roztwór dla EX1: pojedynczy kation.
func _make_simple_cation_solution(cation_id: String) -> Mixture:
	var mix := Mixture.new()
	mix.add_ions({
		cation_id: STARTER_CATION_AMOUNT
	})
	return mix


## Tworzy mieszaninę kationów dla EX2 / egzaminu.
func _make_multi_cation_solution(cation_ids: Array[String]) -> Mixture:
	var mix := Mixture.new()
	var ions_dict: Dictionary = {}

	for cation_id in cation_ids:
		ions_dict[cation_id] = MIX_CATION_AMOUNT

	mix.add_ions(ions_dict)
	return mix


# =================================================================
# LISTY ANIONÓW + ROZTWORY DO ANALIZY
# =================================================================

## Zwraca listę anionów zgodnie z podziałem na grupy (1–5) używanym w ścieżce anionowej.
func _get_group_anions(group: int) -> Array[String]:
	var g1: Array[String] = ["Cl-","Br-","I-","CN-","SCN-"]
	var g2: Array[String] = ["S2-","CH3COO-","NO2-"]
	var g3: Array[String] = ["SO32-","CO32-","BO2-"]
	var g4: Array[String] = ["CrO42-","AsO33-","AsO43-","PO43-"]
	var g5: Array[String] = ["NO3-","ClO3-","ClO4-","MnO4-","SO42-","F-"]

	if group == 0:
		var all: Array[String] = []
		all.append_array(g1)
		all.append_array(g2)
		all.append_array(g3)
		all.append_array(g4)
		all.append_array(g5)
		return all

	match group:
		1:
			return g1
		2:
			return g2
		3:
			return g3
		4:
			return g4
		5:
			return g5
		_:
			return []


## Zwraca numer grupy (1–5) dla danego anionu.
func _group_for_anion(anion_id: String) -> int:
	if anion_id in ["Cl-","Br-","I-","CN-","SCN-"]:
		return 1
	elif anion_id in ["S2-","CH3COO-","NO2-"]:
		return 2
	elif anion_id in ["SO32-","CO32-","BO2-"]:
		return 3
	elif anion_id in ["CrO42-","AsO33-","AsO43-","PO43-"]:
		return 4
	elif anion_id in ["NO3-","ClO3-","ClO4-","MnO4-","SO42-","F-"]:
		return 5
	return -1


## Tworzy prosty roztwór do analizy pojedynczego anionu (EX1).
func _make_simple_anion_solution(anion_id: String) -> Mixture:
	var mix := Mixture.new()
	mix.add_ions({
		anion_id: STARTER_CATION_AMOUNT
	})
	return mix


## Tworzy mieszaninę anionów do analizy (EX2 / egzamin).
func _make_multi_anion_solution(anion_ids: Array[String]) -> Mixture:
	var mix := Mixture.new()
	var ions_dict: Dictionary = {}

	for anion_id in anion_ids:
		ions_dict[anion_id] = MIX_CATION_AMOUNT

	mix.add_ions(ions_dict)
	return mix
