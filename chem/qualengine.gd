extends Node
class_name QualEngine

## =========================================================================
## qualengine.gd – autoload, silnik chemiczny mieszanin
## -------------------------------------------------------------------------
## Odpowiada za:
## - rejestrację reagentów, osadów i reakcji (Resource .tres),
## - dodawanie porcji reagentów do probówek (jony, objętość, bufory),
## - przeliczanie kubełków pH na podstawie H+ / OH- i vol_u,
## - wykonywanie reakcji do ustalenia stanu (fixpoint),
## - informowanie probówek o powstaniu/zaniku osadu (FX).
## =========================================================================

const DEBUG_CORE: bool = true          ## Flaga debugowa – ogólne logi pętli reakcji, pH itd.
const DEBUG_REACTIONS: bool = false    ## Flaga debugowa – logi dopasowanych reakcji.
const DEDUPE_SAME_FX_COLOR: bool = true  ## Czy unikać powtarzania tych samych FX.

# Progi pH: c = |H - OH| / vol_u 
const NEUTRAL_C_EPS: float    = 25.0
const PH_THRESH_STRONG: float = 400.0
const PH_THRESH_VERY: float   = 1000.0

# Minimalny przyrost objętości z dolewki, po którym przelicza się reakcje.
const SQUIRT_RECOMPUTE_STEP: float = 0.05

## Mapa id->reagent (Reagent lub ReagentBuffer).
var reagents: Dictionary = {}

## Mapa id->Solid (osady).
var solids: Dictionary = {}

## Lista reguł reakcji (Reaction).
var reactions: Array = []

## Sygnał informujący, że konkretna reakcja została zastosowana do probówki.
signal reaction_applied(reaction: Resource, tube: Node)


# =========================================================================
# REJESTRACJA REAGENTÓW, OSADÓW I REAKCJI
# =========================================================================

## Rejestruje pojedynczy reagent (na podstawie jego pola "id").
func register_reagent(reagent: Resource) -> void:
	if reagent == null:
		push_warning("register_reagent(): got null")
		return

	var reagent_id: String = str(reagent.get("id"))
	if reagent_id == "":
		push_warning("register_reagent(): resource has empty id")
		return

	reagents[reagent_id] = reagent


## Rejestruje pojedynczy Solid (osad) na podstawie pola "id".
func register_solid(solid_res: Resource) -> void:
	if solid_res == null:
		push_warning("register_solid(): got null")
		return

	var solid_id: String = str(solid_res.get("id"))
	if solid_id == "":
		push_warning("register_solid(): resource has empty id")
		return

	solids[solid_id] = solid_res


## Rejestruje pojedynczą reakcję, sortując listę po polu "priority".
func register_reaction(reaction_res: Resource) -> void:
	if reaction_res == null:
		push_warning("register_reaction(): got null")
		return

	reactions.append(reaction_res)
	reactions.sort_custom(
		func(a: Resource, b: Resource) -> bool:
			return int(a.get("priority")) < int(b.get("priority"))
	)


# =========================================================================
# AUTOLOAD – ŁADOWANIE ZASOBÓW Z KATALOGÓW
# =========================================================================

## Inicjalizuje silnik po starcie jako autoload:
## - ładuje reagenty, osady i reakcje z katalogów /data,
## - wypisuje listę zarejestrowanych zasobów (jeśli DEBUG_CORE).
func _ready() -> void:
	_register_reagents_from_folder("res://data/reagents")
	_register_solids_from_folder("res://data/solids")
	_register_reactions_from_folder("res://data/reactions")

	if DEBUG_CORE:
		# print("[QE] reagents:  ", reagents.keys())
		# print("[QE] solids:    ", solids.keys())
		# print("[QE] reactions: ", str(reactions.size()))
		pass


## Ładuje pojedynczy Resource i rejestruje go przez przekazaną funkcję.
func _register_res(path: String, register_func: Callable) -> void:
	var res: Resource = load(path)
	if res == null:
		push_warning("[QE] load failed: " + path)
		return
	register_func.call(res)


## Ładuje wszystkie Reagent (.tres) z podanego folderu.
func _register_reagents_from_folder(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("[QE] cannot open folder: " + dir_path)
		return

	dir.list_dir_begin()
	while true:
		var file_name: String = dir.get_next()
		if file_name == "":
			break
		if dir.current_is_dir():
			continue
		if not file_name.ends_with(".tres"):
			continue

		_register_res(dir_path + "/" + file_name, register_reagent)
	dir.list_dir_end()


## Ładuje wszystkie Solid (.tres) z podanego folderu.
func _register_solids_from_folder(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("[QE] cannot open folder: " + dir_path)
		return

	dir.list_dir_begin()
	while true:
		var file_name: String = dir.get_next()
		if file_name == "":
			break
		if dir.current_is_dir():
			continue
		if not file_name.ends_with(".tres"):
			continue

		_register_res(dir_path + "/" + file_name, register_solid)
	dir.list_dir_end()


## Ładuje wszystkie Reaction (.tres) z podanego folderu.
func _register_reactions_from_folder(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("[QE] cannot open folder: " + dir_path)
		return

	dir.list_dir_begin()
	while true:
		var file_name: String = dir.get_next()
		if file_name == "":
			break
		if dir.current_is_dir():
			continue
		if not file_name.ends_with(".tres"):
			continue

		_register_res(dir_path + "/" + file_name, register_reaction)
	dir.list_dir_end()


# =========================================================================
# AKCJE UŻYTKOWNIKA – DODAWANIE REAGENTÓW I WODY
# =========================================================================

## Dodaje porcję reagentu do probówki:
## - dodaje jony z „ions” reagentu,
## - zwiększa objętość vol_u o vol_per_click,
## - aktualizuje liczniki „excess_…”,
## - uwzględnia bufory ReagentBuffer,
## - na końcu odpala reakcje aż do ustalenia stanu.
func add_drop_to_tube(tube: Node, reagent_id: String) -> void:
	if tube == null:
		return

	var reagent_resource := reagents.get(reagent_id, null) as Resource
	if reagent_resource == null:
		push_warning("[QE] unknown reagent_id: " + reagent_id)
		return

	var mixture := tube.get("mixture") as Mixture
	if mixture == null:
		push_warning("[QE] tube has no 'mixture'")
		return

	# 1) Jony z reagenta.
	var ions_from_reagent: Dictionary = {}
	var ions_val: Variant = reagent_resource.get("ions")
	if ions_val is Dictionary:
		ions_from_reagent = ions_val
	if ions_from_reagent.size() > 0:
		mixture.add_ions(ions_from_reagent)

	# 2) Liczniki nadmiaru „excess_…”.
	var excess_key_raw: Variant = reagent_resource.get("excess_key")
	if excess_key_raw != null and str(excess_key_raw) != "":
		var excess_key: String = str(excess_key_raw)
		var excess_amount: float = 1.0
		var excess_amount_raw: Variant = reagent_resource.get("excess_per_click")
		if excess_amount_raw is float or excess_amount_raw is int:
			excess_amount = max(0.0, float(excess_amount_raw))

		_add_excess(mixture, "_excess_" + excess_key, excess_amount)

		# Specjalnie traktuje parę H/OH – liczniki wzajemnie się wygaszają.
		if excess_key == "OH" or excess_key == "H":
			_neutralize_excess_pair(mixture, "_excess_OH", "_excess_H")

	# 3) Objętość z vol_per_click.
	var added_volume: float = 0.0
	var vol_raw: Variant = reagent_resource.get("vol_per_click")
	if vol_raw is float or vol_raw is int:
		added_volume = max(0.0, float(vol_raw))
	if added_volume > 0.0:
		mixture.add_vol(added_volume)

	# 4) Neutralizacja silnego kwasu/zasady (H+/OH-).
	_neutralize_strong_acid_base_ions(mixture)

	# 5) Obsługa buforów – akumulacja i pasywne „zjadanie” nadmiaru.
	_buffer_accumulate_from_reagent(mixture, reagent_resource)
	_apply_buffer_passive(mixture)

	if DEBUG_CORE:
		# print("[QE DBG] drop → ", _dbg_probe_name(tube))
		pass

	_apply_reactions_until_fixpoint(tube)


## Dodaje wodę porcjami (strumień z butelki):
## - akumuluje pending_vol,
## - gdy przekroczy próg SQUIRT_RECOMPUTE_STEP, dodaje do vol_u,
## - po dodaniu objętości uruchamia reakcje i pH.
func add_water_volume_step(tube: Node, volume_delta: float, step: float = -1.0) -> void:
	if tube == null or volume_delta <= 0.0:
		return

	var mixture := tube.get("mixture") as Mixture
	if mixture == null:
		return

	mixture.ensure_tags()

	var step_size: float = SQUIRT_RECOMPUTE_STEP if step <= 0.0 else step
	step_size = max(0.0001, step_size)

	var pending_before: float = 0.0
	if mixture.tags.has("pending_vol"):
		var pending_raw: Variant = mixture.tags["pending_vol"]
		if pending_raw is float or pending_raw is int:
			pending_before = float(pending_raw)

	var pending_now: float = pending_before + volume_delta

	if pending_now >= step_size:
		var current_volume: float = 0.0
		var vol_raw: Variant = mixture.tags.get("vol_u", 0.0)
		if vol_raw is float or vol_raw is int:
			current_volume = float(vol_raw)

		mixture.tags["vol_u"] = current_volume + pending_now
		mixture.tags["pending_vol"] = 0.0

		if DEBUG_CORE:
			# print("[QE DBG] squirt ", _dbg_probe_name(tube), "  +vol=", str(pending_now))
			pass

		_apply_reactions_until_fixpoint(tube)
	else:
		mixture.tags["pending_vol"] = pending_now
		if DEBUG_CORE:
			# print("[QE DBG] squirt(accu) ", _dbg_probe_name(tube), "  pend=", str(pending_now))
			pass


## Reaguje na informację „mieszanina się zmieniła” z probówki:
## - uruchamia pętlę reakcji aż do ustalenia stanu.
func on_mixture_changed(tube: Node) -> void:
	_apply_reactions_until_fixpoint(tube)


# =========================================================================
# RDZEŃ – PĘTLA REAKCJI DO USTALENIA STANU
# =========================================================================

## Wykonuje reakcje chemiczne na probówce aż do ustalenia stanu (fixpoint):
## - przelicza kubełek pH,
## - w pętli sprawdza reakcje po kolei wg priority,
## - jeśli w danej iteracji żadna reakcja nie zaszła, kończy,
## - po wszystkim odświeża FX osadów (kolor i tryb).
func _apply_reactions_until_fixpoint(tube: Node) -> void:
	if tube == null:
		return

	var mixture := tube.get("mixture") as Mixture
	if mixture == null:
		return

	_update_pH_bucket_from_state(mixture)

	const MAX_ITERS := 256
	var iteration_count: int = 0
	var any_reaction: bool = false

	while iteration_count < MAX_ITERS:
		var did_any_this_loop: bool = false
		iteration_count += 1

		for reaction_res in reactions:
			if not _reaction_matches(tube, reaction_res):
				continue

			if DEBUG_REACTIONS:
				# print("[QE DBG] reaction MATCH: ", str(reaction_res.get("id")))
				pass

			_apply_reaction(tube, reaction_res)
			reaction_applied.emit(reaction_res, tube)

			if tube.has_method("on_rule_applied"):
				tube.on_rule_applied(reaction_res)

			did_any_this_loop = true
			any_reaction = true

		if not did_any_this_loop:
			break

	if iteration_count >= MAX_ITERS:
		push_warning("QualEngine: reached max iterations (possible reaction loop).")

	var mixture_end := tube.get("mixture") as Mixture
	#if DEBUG_CORE and mixture_end != null:
		#print("[QE DBG] AFTER LOOP  ", _dbg_probe_name(tube), "  ", _dbg_mix_snap(mixture_end))

	var solids_dict: Dictionary = {}
	if mixture_end != null and (mixture_end.solids is Dictionary):
		solids_dict = mixture_end.solids

	if any_reaction:
		if solids_dict.size() > 0:
			var fx_color: Color = _color_from_solids_exact(solids_dict, Color.WHITE)
			_emit_fx(tube, fx_color, 1.0, "fixpoint")
			if tube.has_method("set_meta"):
				tube.set_meta("skip_fallback_fx", true)
		else:
			if tube.has_method("clear_precip_fx"):
				tube.clear_precip_fx(0.35)
			if tube.has_method("set_meta"):
				tube.set_meta("last_precip_mode", null)
				tube.set_meta("last_precip_fx", null)
	else:
		_play_fx_from_current_mixture_if_any(tube)


# =========================================================================
# DOPASOWANIE REAKCJI DO AKTUALNEJ MIESZANINY
# =========================================================================

## Sprawdza, czy dana reakcja może zadziać w aktualnym stanie probówki:
## - sprawdza wymagane przedziały pH (require_pH),
## - sprawdza wymagane tagi i tagi zakazane,
## - uwzględnia warunki termiczne (boiling, min_boil_time),
## - sprawdza, czy są wymagane jony i osady.
func _reaction_matches(tube: Node, reaction_res: Resource) -> bool:
	var mixture := tube.get("mixture") as Mixture
	if mixture == null:
		return false

	# Wymagania pH (bucket z tags["pH"]).
	var ph_raw: Variant = reaction_res.get("require_pH")
	var ph_list: Array = ph_raw if ph_raw is Array else []
	if ph_list.size() > 0:
		var current_ph_label: String = ""
		if mixture.tags is Dictionary:
			var tag_val: Variant = (mixture.tags as Dictionary).get("pH", "")
			if tag_val != null:
				current_ph_label = str(tag_val)

		var is_ok_pH := false
		for allowed_label in ph_list:
			if str(allowed_label) == current_ph_label:
				is_ok_pH = true
				break
		if not is_ok_pH:
			return false

	# Wymagane tagi (require_tags_all).
	var req_all_raw: Variant = reaction_res.get("require_tags_all")
	if req_all_raw is Dictionary and (req_all_raw as Dictionary).size() > 0:
		var must_have: Dictionary = req_all_raw as Dictionary
		if not (mixture.tags is Dictionary):
			return false
		var tags_dict: Dictionary = mixture.tags
		for tag_key in must_have.keys():
			if not tags_dict.has(tag_key):
				return false
			if tags_dict[tag_key] != must_have[tag_key]:
				return false

	# Tagów zakazanych (forbid_tags_any) nie może być włączonych.
	var forbid_raw: Variant = reaction_res.get("forbid_tags_any")
	if forbid_raw is Array and (forbid_raw as Array).size() > 0 and (mixture.tags is Dictionary):
		var tags_dict2: Dictionary = mixture.tags
		for forbidden_tag in (forbid_raw as Array):
			var forbidden_str: String = String(forbidden_tag)
			if tags_dict2.has(forbidden_str):
				var val: Variant = tags_dict2[forbidden_str]
				if _is_truthy(val):
					return false

	# Warunki termiczne (wrzenie i minimalny czas gotowania).
	var needs_boiling: bool = _get_rxn_bool(reaction_res, "require_boiling")
	if needs_boiling and not _get_bool(mixture, "bath_boiling", false):
		return false

	var min_boil_time: float = _get_rxn_float(reaction_res, "min_boil_time", 0.0)
	if min_boil_time > 0.0:
		var cur_boil_time: float = _get_float_time(mixture, "bath_boil_time", 0.0)
		if cur_boil_time + 1e-6 < min_boil_time:
			return false

	# Wymagane jony i osady (reactants_ions, reactants_solids).
	var need_ions: Dictionary = reaction_res.get("reactants_ions") as Dictionary
	if need_ions.size() > 0 and not mixture.has_ions(need_ions):
		return false

	var need_solids: Dictionary = reaction_res.get("reactants_solids") as Dictionary
	if need_solids.size() > 0:
	# Jeżeli mamy pellet na dnie, to osad jest „związany” i nie reaguje,
	# dopóki użytkownik nie rozmiesza go bagietką (hide_pellet() usuwa pellet_ready).
		if mixture.tags is Dictionary and bool((mixture.tags as Dictionary).get("pellet_ready", false)):
			return false

		if not mixture.has_solids(need_solids):
			return false

	return true


# =========================================================================
# ZASTOSOWANIE REAKCJI DO MIESZANINY
# =========================================================================

## Zastosowuje pojedynczą reakcję do probówki:
## - odejmuje jony i osady substratów,
## - dodaje jony i osady produktów,
## - ustawia/usuwa tagi z Reaction.set_tags / clear_tags,
## - jeśli są produkty stałe (solids), zapisuje tryb osadu (precip_mode).
func _apply_reaction(tube: Node, reaction_res: Resource) -> void:
	var mixture := tube.get("mixture") as Mixture
	if mixture == null:
		return

	var react_ions: Dictionary   = reaction_res.get("reactants_ions")   as Dictionary
	var react_solids: Dictionary = reaction_res.get("reactants_solids") as Dictionary
	var prod_ions: Dictionary    = reaction_res.get("products_ions")    as Dictionary
	var prod_solids: Dictionary  = reaction_res.get("products_solids")  as Dictionary

	mixture.remove_ions(react_ions)
	mixture.remove_solids(react_solids)
	mixture.add_ions(prod_ions)
	mixture.add_solids(prod_solids)

	_ensure_tags_dict(mixture)

	# set_tags z Reaction (.tres).
	var set_tags_raw: Variant = reaction_res.get("set_tags")
	if set_tags_raw is Dictionary:
		var tags_to_set: Dictionary = set_tags_raw as Dictionary
		for tag_key in tags_to_set.keys():
			(mixture.tags as Dictionary)[str(tag_key)] = tags_to_set[tag_key]

	# clear_tags z Reaction (.tres).
	var clear_tags_raw: Variant = reaction_res.get("clear_tags")
	if clear_tags_raw is Array:
		for tag_to_clear in (clear_tags_raw as Array):
			(mixture.tags as Dictionary).erase(str(tag_to_clear))

	# Jeżeli reakcja wytwarza osad – zapamiętuje tryb osadu (floc/crystal/cloudy) w mixture.tags["precip_mode"].
	if prod_solids.size() > 0:
		var mode_str: String = "floc"
		var mode_raw: Variant = reaction_res.get("precip_mode")
		if mode_raw != null:
			mode_str = String(mode_raw)
		(mixture.tags as Dictionary)["precip_mode"] = mode_str


# =========================================================================
# FALLBACK FX Z BIEŻĄCEGO STANU (GDY NIE BYŁO NOWYCH REAKCJI)
# =========================================================================

## Odpala FX na podstawie aktualnego stanu mieszanki,
## jeżeli w tej iteracji pętli nie zaszły żadne nowe reakcje.
func _play_fx_from_current_mixture_if_any(tube: Node) -> void:
	if tube and tube.has_method("_has_pellet_ready") and tube._has_pellet_ready():
		# Dla pelletu nie wymuszamy fallback FX – pellet ma osobny wygląd.
		return

	if tube.has_meta("skip_fallback_fx") and tube.get_meta("skip_fallback_fx"):
		tube.set_meta("skip_fallback_fx", false)
		return

	if not tube.has_method("play_precip"):
		return

	var mixture := tube.get("mixture") as Mixture
	if mixture == null or not (mixture.solids is Dictionary) or (mixture.solids as Dictionary).size() == 0:
		return

	var mix_color: Color = _color_from_solids_exact(mixture.solids, Color.WHITE)
	_emit_fx(tube, mix_color, 1.0, "fallback")


# =========================================================================
# EMITOWANIE FX
# =========================================================================

## Wysyła do probówki informację o osadzie:
## - wybiera tryb FX na podstawie mixture.tags["precip_mode"],
## - opcjonalnie deduplikuje identyczne FX (ten sam kolor i tryb),
## - wywołuje Probe.play_precip(mode, turb_color, sed_color, intensity).
func _emit_fx(tube: Node, color: Color, intensity: float, _source: String) -> void:
	if tube == null:
		return

	var mode: String = "floc"
	var mixture := tube.get("mixture") as Mixture
	if mixture != null and (mixture.tags is Dictionary):
		var pm_raw: Variant = (mixture.tags as Dictionary).get("precip_mode", "floc")
		if pm_raw is String:
			mode = pm_raw as String

	if DEDUPE_SAME_FX_COLOR:
		var signature: Dictionary = { "c": color, "m": mode }
		if tube.has_meta("last_precip_fx"):
			var previous_signature: Variant = tube.get_meta("last_precip_fx")
			if previous_signature is Dictionary and not DEBUG_CORE:
				var prev_dict: Dictionary = previous_signature as Dictionary
				if prev_dict.get("c") == color and String(prev_dict.get("m")) == mode:
					return
		tube.set_meta("last_precip_fx", signature)

	if DEBUG_CORE:
		#print("[QE FX] ", source, "  mode=", mode, "  intensity=", str(intensity))
		pass

	if not tube.has_method("play_precip"):
		if DEBUG_CORE:
			# print("[QE FX] tube has no play_precip(), skipping FX")
			pass
		return

	tube.play_precip(mode, color, color, intensity)


# =========================================================================
# KOLORY OSADÓW – MODEL DOMINACJI
# =========================================================================

## Wylicza kolor mieszaniny osadów:
## - jeżeli brak osadów → zwraca kolor domyślny (fallback_color),
## - jeżeli wszystkie ilości są < 1.0 → zwraca zwykłą średnią ważoną,
## - jeżeli istnieje osad z największą „ilością całkowitą” (int(amount)):
##   - jeśli jest jeden dominujący → jego kolor,
##   - jeśli jest kilka z remisem → średnia ważona tylko między nimi.
func _color_from_solids_exact(solids_dict: Dictionary, fallback_color: Color) -> Color:
	if solids_dict == null or solids_dict.size() == 0:
		return fallback_color

	var amount_map: Dictionary = {}  # solid_id -> float amount
	var max_int_amount: int = 0
	var candidate_ids: Array[String] = []

	# Przelicza ilości osadów na float i szuka dominującego po int(amount).
	for solid_key in solids_dict.keys():
		var solid_id: String = str(solid_key)
		var amount_raw: Variant = solids_dict[solid_key]
		var color_weight: float = 0.0

		if amount_raw is float or amount_raw is int:
			color_weight = max(0.0, float(amount_raw))
		if color_weight <= 0.0:
			continue

		amount_map[solid_id] = color_weight

		var int_amount: int = int(color_weight)
		if int_amount > max_int_amount:
			max_int_amount = int_amount
			candidate_ids.clear()
			candidate_ids.append(solid_id)
		elif int_amount == max_int_amount:
			candidate_ids.append(solid_id)

	if amount_map.size() == 0:
		return fallback_color

	# Gdy wszystkie ilości < 1.0 → zwykła średnia ważona po wszystkich osadach.
	if max_int_amount <= 0:
		var sum_r_all: float = 0.0
		var sum_g_all: float = 0.0
		var sum_b_all: float = 0.0
		var sum_w_all: float = 0.0

		for solid_id in amount_map.keys():
			var solid_res: Solid = solids.get(solid_id) as Solid
			if solid_res == null:
				push_warning("[QE] unknown solid id in mixture: " + solid_id)
				continue

			var col: Color = solid_res.color
			var weight_all: float = float(amount_map[solid_id])

			sum_r_all += col.r * weight_all
			sum_g_all += col.g * weight_all
			sum_b_all += col.b * weight_all
			sum_w_all += weight_all

		if sum_w_all <= 0.0:
			return fallback_color

		var inv_all: float = 1.0 / sum_w_all
		return Color(
			clamp(sum_r_all * inv_all, 0.0, 1.0),
			clamp(sum_g_all * inv_all, 0.0, 1.0),
			clamp(sum_b_all * inv_all, 0.0, 1.0),
			1.0
		)

	# max_int_amount > 0:
	# - jeśli jeden kandydat z najwyższą ilością całkowitą → jego kolor,
	# - jeśli kilku (remis) → mieszanka tylko między nimi.
	if candidate_ids.size() == 1:
		var dominant_id: String = candidate_ids[0]
		var dominant_res: Solid = solids.get(dominant_id) as Solid
		if dominant_res == null:
			push_warning("[QE] unknown dominant solid id: " + dominant_id)
			return fallback_color
		return dominant_res.color
	else:
		var sum_r: float = 0.0
		var sum_g: float = 0.0
		var sum_b: float = 0.0
		var sum_w: float = 0.0

		for solid_id in candidate_ids:
			var solid_res: Solid = solids.get(solid_id) as Solid
			if solid_res == null:
				push_warning("[QE] unknown solid id in tie: " + solid_id)
				continue

			var col: Color = solid_res.color
			var weight: float = float(amount_map.get(solid_id, 0.0))

			sum_r += col.r * weight
			sum_g += col.g * weight
			sum_b += col.b * weight
			sum_w += weight

		if sum_w <= 0.0:
			return fallback_color

		var inv: float = 1.0 / sum_w
		return Color(
			clamp(sum_r * inv, 0.0, 1.0),
			clamp(sum_g * inv, 0.0, 1.0),
			clamp(sum_b * inv, 0.0, 1.0),
			1.0
		)



# =========================================================================
# HELPERY TAGÓW / ODCZYTÓW
# =========================================================================

## Zapewnia, że mix.tags jest słownikiem (Dictionary).
func _ensure_tags_dict(mix: Mixture) -> void:
	if not (mix.tags is Dictionary):
		mix.tags = {}


## Odczytuje wartość bool z mix.tags, z domyślną wartością def.
func _get_bool(mix: Mixture, key: String, def: bool) -> bool:
	if not (mix and (mix.tags is Dictionary) and (mix.tags as Dictionary).has(key)):
		return def
	return _is_truthy((mix.tags as Dictionary)[key])


## Odczytuje wartość czasu (float) z mix.tags, z domyślną wartością def.
func _get_float_time(mix: Mixture, key: String, def: float) -> float:
	if not (mix and (mix.tags is Dictionary) and (mix.tags as Dictionary).has(key)):
		return def
	var raw_val: Variant = (mix.tags as Dictionary)[key]
	return float(raw_val) if (raw_val is float or raw_val is int) else def


## Odczytuje pole logiczne z Reaction (.tres), uwzględniając „truthy” wartości.
func _get_rxn_bool(rx: Resource, field_name: String) -> bool:
	if rx and rx.has_method("get"):
		var raw_val: Variant = rx.get(field_name)
		if raw_val is bool:
			return raw_val
		return _is_truthy(raw_val)
	return false


## Odczytuje pole float z Reaction (.tres), z wartością domyślną.
func _get_rxn_float(rx: Resource, field: String, def: float) -> float:
	if rx and rx.has_method("get"):
		var raw_val: Variant = rx.get(field)
		if raw_val is float or raw_val is int:
			return float(raw_val)
	return def


## Sprawdza, czy wartość jest prawdziwa:
## - liczby niezerowe,
## - niepuste stringi,
## - nie-null.
func _is_truthy(v: Variant) -> bool:
	if v is bool:
		return v
	if v is int or v is float:
		return absf(float(v)) > 0.0
	if v is String:
		return v != ""
	return v != null


# =========================================================================
# PROGI pH – KONWERSJA NA ETYKIETY I SKALĘ 7 ST.
# =========================================================================

## Przelicza kubełek pH na podstawie H+, OH- i vol_u:
## - zapisuje etykietę pH (acidic/basic/strong/very_strong),
## - zapisuje ph_grade7 w zakresie [-3..+3] (do papierka wskaźnikowego).
func _update_pH_bucket_from_state(mix: Mixture) -> void:
	mix.ensure_tags()

	var H: float = Mixture._get_float(mix.ions, "H+")
	var OH: float = Mixture._get_float(mix.ions, "OH-")
	var vol: float = max(1e-6, float(mix.tags.get("vol_u", 0.0)))
	var c: float = absf(H - OH) / vol

	var label: String

	if c <= NEUTRAL_C_EPS:
		label = "neutral"
	else:
		var very_strong: bool = c >= PH_THRESH_VERY
		var strong: bool = (not very_strong) and (c >= PH_THRESH_STRONG)

		if (H - OH) > 0.0:
			label = ("very_strong_acid" if very_strong else ("strong_acid" if strong else "acidic"))
		else:
			label = ("very_strong_base" if very_strong else ("strong_base" if strong else "basic"))

	mix.tags["pH"] = label
	mix.tags["ph_grade7"] = _label_to_grade7(label)

	if DEBUG_CORE:
		# print("[QE pH] H=", H, " OH=", OH,
		# 	" vol_u=", mix.tags.get("vol_u", 0.0),
		# 	" c=", c,
		# 	" -> label=", label, " grade7=", mix.tags.get("ph_grade7"))
		pass


## Zamienia etykietę pH na liczbę z zakresu [-3..+3].
func _label_to_grade7(label: String) -> int:
	match label:
		"very_strong_acid":
			return -3
		"strong_acid":
			return -2
		"acidic":
			return -1
		"neutral":
			return 0
		"basic":
			return 1
		"strong_base":
			return 2
		"very_strong_base":
			return 3
		_:
			return 0


# =========================================================================
# LICZNIKI NADMIARU / BUFORY / DEBUG
# =========================================================================

## Dodaje licznik nadmiaru (np. "_excess_H") do mix.ions.
func _add_excess(mix: Mixture, key: String, amount: float) -> void:
	if mix == null or amount <= 0.0:
		return

	if not (mix.ions is Dictionary):
		mix.ions = {}

	var current_amount: float = 0.0
	if mix.ions.has(key):
		var raw_val: Variant = mix.ions[key]
		if raw_val is float or raw_val is int:
			current_amount = float(raw_val)

	mix.ions[key] = current_amount + amount

	if DEBUG_CORE:
		# print("[QE EXCESS] +", key, " = +", amount, "  → ", mix.ions[key])
		pass


## Neutralizuje parę liczników nadmiaru (np. "_excess_H" z "_excess_OH").
func _neutralize_excess_pair(mix: Mixture, key_a: String, key_b: String) -> void:
	if mix == null or not (mix.ions is Dictionary):
		return

	var value_a: float = 0.0
	var value_b: float = 0.0

	if mix.ions.has(key_a):
		var raw_a: Variant = mix.ions[key_a]
		if raw_a is float or raw_a is int:
			value_a = float(raw_a)

	if mix.ions.has(key_b):
		var raw_b: Variant = mix.ions[key_b]
		if raw_b is float or raw_b is int:
			value_b = float(raw_b)

	var neutralized: float = min(value_a, value_b)
	if neutralized <= 0.0:
		return

	var new_a: float = value_a - neutralized
	var new_b: float = value_b - neutralized

	if new_a <= Mixture.EPS:
		mix.ions.erase(key_a)
	else:
		mix.ions[key_a] = new_a

	if new_b <= Mixture.EPS:
		mix.ions.erase(key_b)
	else:
		mix.ions[key_b] = new_b

	if DEBUG_CORE:
		# print("[QE EXCESS] neutralize ", key_a, " vs ", key_b, "  Δ=", neutralized,
		# 	"  → ", key_a, "=", mix.ions.get(key_a, 0.0), "  ", key_b, "=", mix.ions.get(key_b, 0.0))
		pass


## Neutralizuje silny kwas i silną zasadę (H+ z OH-) w mix.ions.
func _neutralize_strong_acid_base_ions(mix: Mixture) -> void:
	var H: float = Mixture._get_float(mix.ions, "H+")
	var OH: float = Mixture._get_float(mix.ions, "OH-")
	var to_neutralize: float = min(H, OH)

	if to_neutralize <= Mixture.EPS:
		return

	var new_H: float = H - to_neutralize
	var new_OH: float = OH - to_neutralize

	if new_H <= Mixture.EPS:
		mix.ions.erase("H+")
	else:
		mix.ions["H+"] = new_H

	if new_OH <= Mixture.EPS:
		mix.ions.erase("OH-")
	else:
		mix.ions["OH-"] = new_OH


## Akumuluje pojemność buforową z ReagentBuffer do mieszanki (buffer_cap, buffer_bias).
func _buffer_accumulate_from_reagent(mix: Mixture, reagent: Resource) -> void:
	if reagent == null or not (reagent is ReagentBuffer):
		return

	mix.ensure_tags()

	var add_cap: float = 0.0
	var cap_raw: Variant = reagent.get("buffer_cap_per_click")
	if cap_raw is float or cap_raw is int:
		add_cap = max(0.0, float(cap_raw))

	var current_cap: float = 0.0
	if mix.tags.has("buffer_cap"):
		var cap_existing: Variant = mix.tags["buffer_cap"]
		if cap_existing is float or cap_existing is int:
			current_cap = float(cap_existing)

	mix.tags["buffer_cap"] = current_cap + add_cap

	var volume_added: float = 0.1
	var vol_raw: Variant = reagent.get("vol_per_click")
	if vol_raw is float or vol_raw is int:
		volume_added = max(0.0, float(vol_raw))

	var signed_bias: float = 0.0
	var bias_raw: Variant = reagent.get("buffer_bias")
	if bias_raw is float or bias_raw is int:
		signed_bias = float(bias_raw)

	var bias_amount: float = absf(signed_bias) * volume_added
	if bias_amount > Mixture.EPS:
		if signed_bias > 0.0:
			mix.ions["OH-"] = Mixture._get_float(mix.ions, "OH-") + bias_amount
		elif signed_bias < 0.0:
			mix.ions["H+"] = Mixture._get_float(mix.ions, "H+") + bias_amount


## Zjada nadmiar H+/OH- z pojemności buforowej mieszanki.
func _apply_buffer_passive(mix: Mixture) -> void:
	if mix == null:
		return

	mix.ensure_tags()

	var cap: float = 0.0
	if mix.tags.has("buffer_cap"):
		var cap_raw: Variant = mix.tags["buffer_cap"]
		if cap_raw is float or cap_raw is int:
			cap = float(cap_raw)

	if cap <= Mixture.EPS:
		return

	var H: float = Mixture._get_float(mix.ions, "H+")
	var OH: float = Mixture._get_float(mix.ions, "OH-")
	var excess: float = absf(H - OH)

	if excess <= Mixture.EPS:
		return

	var eaten: float = min(excess, cap)

	if H >= OH:
		H -= eaten
	else:
		OH -= eaten

	if H <= Mixture.EPS:
		mix.ions.erase("H+")
	else:
		mix.ions["H+"] = H

	if OH <= Mixture.EPS:
		mix.ions.erase("OH-")
	else:
		mix.ions["OH-"] = OH

	mix.tags["buffer_cap"] = cap - eaten


## Zwraca czytelną nazwę probówki do logów (nazwa lub instance_id).
func _dbg_probe_name(tube: Node) -> String:
	if tube == null:
		return "<null>"
	return str(tube.name)


## Zwraca snapshot mieszaniny (jony, osady, tagi) jako string do debugowania.
func _dbg_mix_snap(mix: Mixture) -> String:
	if mix == null:
		return "<m:null>"

	var tags_copy: Dictionary = {}
	var ions_copy: Dictionary = {}
	var solids_copy: Dictionary = {}

	if mix.tags is Dictionary:
		tags_copy = mix.tags
	if mix.ions is Dictionary:
		ions_copy = mix.ions
	if mix.solids is Dictionary:
		solids_copy = mix.solids

	return "IONS=" + str(ions_copy) + "  SOLIDS=" + str(solids_copy) + "  TAGS=" + str(tags_copy)
