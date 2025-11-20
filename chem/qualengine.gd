extends Node
class_name QualEngine
# Silnik chemiczny aplikacji:
# - trzyma listę reagentów, osadów i reakcji,
# - obsługuje butelki z odczynnikami i dolewanie wody,
# - liczy przedziały pH i wpływ buforów,
# - rozpoczyna reakcje chemiczne - pojawianie się nowych substancji i osadów.

# ----------------------------
# Debug / parametry
# ----------------------------

@export var debug_core: bool = true            # ogólne logi (pH, wejście do pętli itp.)
@export var debug_reactions: bool = false      # wypisywanie, które Reaction się odpalają
@export var dedupe_same_fx_color: bool = true  # nie puszczaj tego samego FX w kółko

# progi do przedziałów (kubełków) pH, c = |H - OH| / vol_u
@export var neutral_c_eps: float    = 0.5
@export var ph_thresh_strong: float = 8.0
@export var ph_thresh_very: float   = 19.0

# dolewanie wody strumieniem – krok do przeliczania pH/reakcji
@export var squirt_recompute_step: float = 0.05


# ----------------------------
# Rejestry zasobów
# ----------------------------

var reagents: Dictionary = {}
var solids: Dictionary = {}
var reactions: Array = []


# ----------------------------
# Sygnały
# ----------------------------

signal reaction_applied(reaction: Resource, tube: Node)


# ----------------------------
# Rejestracja zasobów
# ----------------------------

func register_reagent(reagent: Resource) -> void:
	if reagent == null:
		push_warning("register_reagent(): got null")
		return

	var reagent_id := ""
	if reagent.has_method("get"):
		reagent_id = str(reagent.get("id"))

	if reagent_id == "":
		push_warning("register_reagent(): resource has empty id")
		return

	reagents[reagent_id] = reagent


func register_solid(solid_res: Resource) -> void:
	if solid_res == null:
		push_warning("register_solid(): got null")
		return

	var solid_id := ""
	if solid_res.has_method("get"):
		solid_id = str(solid_res.get("id"))

	if solid_id == "":
		push_warning("register_solid(): resource has empty id")
		return

	solids[solid_id] = solid_res


# niższy priority = pierwszeństwo
func register_reaction(reaction_res: Resource) -> void:
	if reaction_res == null:
		push_warning("register_reaction(): got null")
		return

	reactions.append(reaction_res)
	reactions.sort_custom(func(a, b): return int(a.get("priority")) < int(b.get("priority")))


# ----------------------------
# Autoload
# ----------------------------

func _ready() -> void:
	_register_reagents_from_folder("res://data/reagents")
	_register_solids_from_folder("res://data/solids")
	_register_reactions_from_folder("res://data/reactions")

	if debug_core:
		print("[QE] reagents:  ", reagents.keys())
		print("[QE] solids:    ", solids.keys())
		print("[QE] reactions: ", str(reactions.size()))


func _register_res(path: String, reg_func: Callable) -> void:
	var res: Resource = load(path)
	if res == null:
		push_warning("[QE] load failed: " + path)
		return
	reg_func.call(res)


func _register_reagents_from_folder(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("[QE] cannot open folder: " + dir_path)
		return

	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name == "":
			break
		if dir.current_is_dir():
			continue
		if not file_name.ends_with(".tres"):
			continue

		_register_res(dir_path + "/" + file_name, register_reagent)
	dir.list_dir_end()


func _register_solids_from_folder(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("[QE] cannot open folder: " + dir_path)
		return

	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name == "":
			break
		if dir.current_is_dir():
			continue
		if not file_name.ends_with(".tres"):
			continue

		_register_res(dir_path + "/" + file_name, register_solid)
	dir.list_dir_end()


func _register_reactions_from_folder(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("[QE] cannot open folder: " + dir_path)
		return

	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name == "":
			break
		if dir.current_is_dir():
			continue
		if not file_name.ends_with(".tres"):
			continue

		_register_res(dir_path + "/" + file_name, register_reaction)
	dir.list_dir_end()


# ----------------------------
# Akcje użytkownika
# ----------------------------

# Główna funkcja dla butelek z odczynnikami:
# - dodaje jony reagentów,
# - aktualizuje objętość,
# - liczy nadmiary, bufory i pH,
# - odpala pętlę reakcji.
func add_drop_to_tube(tube: Node, reagent_id: String) -> void:
	if tube == null:
		return

	var reagent_res: Resource = reagents.get(reagent_id) as Resource
	if reagent_res == null:
		push_warning("[QE] unknown reagent_id: " + reagent_id)
		return

	var mixture: Mixture = tube.get("mixture") as Mixture
	if mixture == null:
		push_warning("[QE] tube has no 'mixture'")
		return

	# 1) jony z reagenta
	var ions_from_reagent: Dictionary = {}
	if reagent_res.has_method("get"):
		var ions_val: Variant = reagent_res.get("ions")
		if ions_val is Dictionary:
			ions_from_reagent = ions_val

	if ions_from_reagent.size() > 0:
		mixture.add_ions(ions_from_reagent)

	# 2) liczniki nadmiaru „excess”
	if reagent_res.has_method("get"):
		var excess_key_raw: Variant = reagent_res.get("excess_key")
		if excess_key_raw != null and str(excess_key_raw) != "":
			var excess_key: String = str(excess_key_raw)
			var excess_amount: float = 1.0
			var excess_amount_raw: Variant = reagent_res.get("excess_per_click")

			if excess_amount_raw is float or excess_amount_raw is int:
				excess_amount = max(0.0, float(excess_amount_raw))

			_add_excess(mixture, "_excess_" + excess_key, excess_amount)

			# para „H/OH” – neutralizacja licznikami
			if excess_key == "OH" or excess_key == "H":
				_neutralize_excess_pair(mixture, "_excess_OH", "_excess_H")

	# 3) objętość z vol_per_click
	var added_vol: float = 0.0
	if reagent_res.has_method("get"):
		var vol_raw: Variant = reagent_res.get("vol_per_click")
		if vol_raw is float or vol_raw is int:
			added_vol = max(0.0, float(vol_raw))

	if added_vol > 0.0:
		mixture.add_vol(added_vol)

	# 4) neutralizacja H+/OH−
	_neutralize_strong_acid_base_ions(mixture)

	# 5) obsługa bufora
	_buffer_accumulate_from_reagent(mixture, reagent_res)
	_apply_buffer_passive(mixture)

	# pomocnicze acid_eq/base_eq (do debugu)
	mixture.recompute_acid_base_eq_from_ions()

	# 6) odczyn pH dla osadów typu pellet
	if tube.has_method("_has_pellet_ready") and tube._has_pellet_ready():
		_update_pH_bucket_from_state(mixture)
		return

	if debug_core:
		print("[QE DBG] drop → ", _dbg_probe_name(tube))

	_apply_reactions_until_fixpoint(tube)


# Obsługa ciągłego dolewania wody z tryskawki
func add_water_volume_step(tube: Node, vol_delta: float, step: float = -1.0) -> void:
	if tube == null or vol_delta <= 0.0:
		return

	var mixture: Mixture = tube.get("mixture") as Mixture
	if mixture == null:
		return

	mixture.ensure_tags()

	var step_size: float = squirt_recompute_step if step <= 0.0 else step
	step_size = max(0.0001, step_size)

	var pending_before_vol: float = 0.0
	if mixture.tags.has("pending_vol"):
		var pending_raw: Variant = mixture.tags["pending_vol"]
		if pending_raw is float or pending_raw is int:
			pending_before_vol = float(pending_raw)

	var pending_now: float = pending_before_vol + vol_delta

	if pending_now >= step_size:
		var current_vol_u: float = 0.0
		var vol_u_raw: Variant = mixture.tags.get("vol_u", 0.0)
		if vol_u_raw is float or vol_u_raw is int:
			current_vol_u = float(vol_u_raw)

		mixture.tags["vol_u"] = current_vol_u + pending_now
		mixture.tags["pending_vol"] = 0.0

		if debug_core:
			print("[QE DBG] squirt ", _dbg_probe_name(tube), "  +vol=", str(pending_now))

		_apply_reactions_until_fixpoint(tube)
	else:
		mixture.tags["pending_vol"] = pending_now
		if debug_core:
			print("[QE DBG] squirt(accu) ", _dbg_probe_name(tube), "  pend=", str(pending_now))


func on_mixture_changed(tube: Node) -> void:
	_apply_reactions_until_fixpoint(tube)


# ----------------------------
# Rdzeń - reakcje chemiczne
# ----------------------------

func _apply_reactions_until_fixpoint(tube: Node) -> void:
	if tube == null:
		return

	var mix_start: Mixture = tube.get("mixture") as Mixture
	if mix_start == null:
		return

	_update_pH_bucket_from_state(mix_start)

	if debug_core:
		print("[QE DBG] fixpoint ENTER ", _dbg_probe_name(tube), "  ", _dbg_mix_snap(mix_start))

	const MAX_ITERS := 256
	var iter_count := 0
	var any_reaction: bool = false
	var fx_intensities_per_tick: Array[float] = []

	while iter_count < MAX_ITERS:
		var did_any_reaction_this_loop := false
		iter_count += 1

		for reaction_res in reactions:
			if not _reaction_matches(tube, reaction_res):
				continue

			if debug_reactions:
				print("[QE DBG] reaction MATCH: ", str(reaction_res.get("id")))

			var result: Dictionary = _apply_reaction(tube, reaction_res)

			reaction_applied.emit(reaction_res, tube)

			if tube.has_method("on_rule_applied"):
				tube.on_rule_applied(reaction_res)

			did_any_reaction_this_loop = true
			any_reaction = true

			if _is_truthy(result.get("made_precip")):
				var inten_raw: Variant = result.get("intensity")
				if inten_raw is float or inten_raw is int:
					fx_intensities_per_tick.append(float(inten_raw))

		if not did_any_reaction_this_loop:
			break

	if iter_count >= MAX_ITERS:
		push_warning("QualEngine: reached max iterations (possible reaction loop).")

	var mix_end: Mixture = tube.get("mixture") as Mixture
	var solids_dict: Dictionary = {}
	if mix_end != null and (mix_end.solids is Dictionary):
		solids_dict = mix_end.solids

	if any_reaction:
		if solids_dict.size() > 0:
			var fx_color: Color = _color_from_solids_exact(solids_dict, Color.WHITE)
			var avg_intensity: float = _average_float_list(fx_intensities_per_tick, 0.6)
			_emit_fx(tube, fx_color, avg_intensity, "fixpoint")

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


# ----------------------------
# Dopasowanie reakcji
# ----------------------------

func _reaction_matches(tube: Node, reaction_res: Resource) -> bool:
	var mixture: Mixture = tube.get("mixture") as Mixture
	if mixture == null:
		return false

	# require_pH
	var ph_raw: Variant = reaction_res.get("require_pH")
	var ph_list: Array = ph_raw if ph_raw is Array else []
	if ph_list.size() > 0:
		var current_ph_label: String = ""
		if mixture.tags is Dictionary:
			var tag_val: Variant = (mixture.tags as Dictionary).get("pH", "")
			if tag_val != null:
				current_ph_label = str(tag_val)

		var ph_ok: bool = false
		for allowed_label in ph_list:
			if str(allowed_label) == current_ph_label:
				ph_ok = true
				break
		if not ph_ok:
			return false

	# require_tags_all
	var req_all_raw: Variant = reaction_res.get("require_tags_all")
	if req_all_raw is Dictionary and (req_all_raw as Dictionary).size() > 0:
		var must_have_tags: Dictionary = req_all_raw
		for tag_key in must_have_tags.keys():
			if not (mixture.tags is Dictionary) or not (mixture.tags as Dictionary).has(tag_key):
				return false
			if (mixture.tags as Dictionary)[tag_key] != must_have_tags[tag_key]:
				return false

	# forbid_tags_any
	var forbid_raw: Variant = reaction_res.get("forbid_tags_any")
	if forbid_raw is Array and (forbid_raw as Array).size() > 0:
		for forbidden_tag in (forbid_raw as Array):
			if (mixture.tags is Dictionary) and (mixture.tags as Dictionary).has(forbidden_tag):
				var val: Variant = (mixture.tags as Dictionary)[forbidden_tag]
				if _is_truthy(val):
					return false

	# warunki temperaturowe
	var needs_boiling: bool = _get_rxn_bool(reaction_res, "require_boiling")
	if needs_boiling and not _get_bool(mixture, "bath_boiling", false):
		return false

	var min_boil_time: float = _get_rxn_float(reaction_res, "min_boil_time", 0.0)
	if min_boil_time > 0.0:
		var cur_boil_time: float = _get_float_time(mixture, "bath_boil_time", 0.0)
		if cur_boil_time + 1e-6 < min_boil_time:
			return false

	# jony i osady
	var need_ions: Dictionary = reaction_res.get("reactants_ions")
	if need_ions.size() > 0 and not mixture.has_ions(need_ions):
		return false

	var need_solids: Dictionary = reaction_res.get("reactants_solids")
	if need_solids.size() > 0 and not mixture.has_solids(need_solids):
		return false

	return true


# ----------------------------
# Zastosowanie reakcji
# ----------------------------

func _apply_reaction(tube: Node, reaction_res: Resource) -> Dictionary:
	var mixture: Mixture = tube.get("mixture") as Mixture

	var react_ions: Dictionary   = reaction_res.get("reactants_ions")
	var react_solids: Dictionary = reaction_res.get("reactants_solids")
	var prod_ions: Dictionary    = reaction_res.get("products_ions")
	var prod_solids: Dictionary  = reaction_res.get("products_solids")

	mixture.remove_ions(react_ions)
	mixture.remove_solids(react_solids)
	mixture.add_ions(prod_ions)
	mixture.add_solids(prod_solids)

	_ensure_tags_dict(mixture)

	var set_tags_raw: Variant = reaction_res.get("set_tags")
	if set_tags_raw is Dictionary:
		var tags_to_set: Dictionary = set_tags_raw
		for tag_key in tags_to_set.keys():
			mixture.tags[str(tag_key)] = tags_to_set[tag_key]

	var clear_tags_raw: Variant = reaction_res.get("clear_tags")
	if clear_tags_raw is Array:
		for tag_to_clear in (clear_tags_raw as Array):
			mixture.tags.erase(str(tag_to_clear))

	var made_precip: bool = prod_solids.size() > 0
	var result: Dictionary = { "made_precip": made_precip }

	if made_precip:
		if tube.has_method("set_meta"):
			var mode_str: String = "floc"
			var mode_raw: Variant = reaction_res.get("precip_mode")
			if mode_raw != null:
				mode_str = String(mode_raw)
			tube.set_meta("last_precip_mode", mode_str)

		result["turb_color"] = reaction_res.get("precip_color")
		result["intensity"] = reaction_res.get("intensity")

	return result


# ----------------------------
# Fallback FX z bieżącego stanu
# ----------------------------

func _play_fx_from_current_mixture_if_any(tube: Node) -> void:
	if tube and tube.has_method("_has_pellet_ready") and tube._has_pellet_ready():
		return

	if tube.has_meta("skip_fallback_fx") and tube.get_meta("skip_fallback_fx"):
		tube.set_meta("skip_fallback_fx", false)
		return

	if not tube.has_method("play_precip"):
		return

	var mixture: Mixture = tube.get("mixture") as Mixture
	if mixture == null or not (mixture.solids is Dictionary) or (mixture.solids as Dictionary).size() == 0:
		return

	var mix_color: Color = _color_from_solids_exact(mixture.solids, Color.WHITE)
	_emit_fx(tube, mix_color, 0.6, "fallback")


# ----------------------------
# Emit fx (z deduplikacją)
# ----------------------------

func _emit_fx(tube: Node, c: Color, intensity: float, source: String) -> void:
	if tube and tube.has_method("_has_pellet_ready") and tube._has_pellet_ready():
		if debug_core:
			print("[QE FX] skip (pellet_ready, source=", source, ")")
		return

	var mode: String = "floc"
	if tube.has_meta("last_precip_mode"):
		var mode_raw: Variant = tube.get_meta("last_precip_mode")
		if mode_raw != null:
			mode = String(mode_raw)

	if tube.has_method("set_meta"):
		tube.set_meta("last_precip_mode", mode)

	if dedupe_same_fx_color:
		var sig: Dictionary = { "c": c, "m": mode }
		if tube.has_meta("last_precip_fx"):
			var prev_sig: Variant = tube.get_meta("last_precip_fx")
			if prev_sig is Dictionary and not debug_core:
				var prev_dict: Dictionary = prev_sig
				if prev_dict.get("c") == c and String(prev_dict.get("m")) == mode:
					return
		tube.set_meta("last_precip_fx", sig)

	if debug_core:
		print("[QE FX] ", source, "  mode=", mode, "  intensity=", str(intensity))

	if not tube.has_method("play_precip"):
		if debug_core:
			print("[QE FX] tube has no play_precip(), skipping FX")
		return

	tube.play_precip(mode, c, c, intensity)


# ----------------------------
# Kolory i średnie
# ----------------------------

func _color_from_solids_exact(solids_dict: Dictionary, fallback_color: Color) -> Color:
	var sum_r: float = 0.0
	var sum_g: float = 0.0
	var sum_b: float = 0.0
	var sum_w: float = 0.0

	for solid_key in solids_dict.keys():
		var solid_id: String = str(solid_key)
		var amount_raw: Variant = solids_dict[solid_key]
		var w: float = 0.0

		if amount_raw is float or amount_raw is int:
			w = max(0.0, float(amount_raw))
		if w <= 0.0:
			continue

		var solid_res: Resource = solids.get(solid_id) as Resource
		if solid_res == null:
			push_warning("[QE] unknown solid id in mixture: " + solid_id)
			continue

		var col: Color = (solid_res as Solid).color
		sum_r += col.r * w
		sum_g += col.g * w
		sum_b += col.b * w
		sum_w += w

	if sum_w <= 0.0:
		return fallback_color

	var inv: float = 1.0 / sum_w
	return Color(
		clamp(sum_r * inv, 0.0, 1.0),
		clamp(sum_g * inv, 0.0, 1.0),
		clamp(sum_b * inv, 0.0, 1.0),
		1.0
	)


func _average_float_list(values: Array[float], fallback_val: float) -> float:
	if values.size() == 0:
		return fallback_val

	var sum_val: float = 0.0
	var count: int = 0

	for v in values:
		sum_val += float(v)
		count += 1

	return (sum_val / float(count)) if count > 0 else fallback_val


# ----------------------------
# Helpery tagów / odczytów
# ----------------------------

func _ensure_tags_dict(mix: Mixture) -> void:
	if not (mix.tags is Dictionary):
		mix.tags = {}


func _get_bool(mix: Mixture, key: String, def: bool) -> bool:
	if not (mix and (mix.tags is Dictionary) and (mix.tags as Dictionary).has(key)):
		return def
	return _is_truthy((mix.tags as Dictionary)[key])


func _get_float_time(mix: Mixture, key: String, def: float) -> float:
	if not (mix and (mix.tags is Dictionary) and (mix.tags as Dictionary).has(key)):
		return def
	var raw_val: Variant = (mix.tags as Dictionary)[key]
	return float(raw_val) if (raw_val is float or raw_val is int) else def


func _get_string(mix: Mixture, key: String, def: String) -> String:
	if not (mix and (mix.tags is Dictionary) and (mix.tags as Dictionary).has(key)):
		return def
	return str((mix.tags as Dictionary)[key])


func _get_rxn_bool(rx: Resource, field_name: String) -> bool:
	if rx and rx.has_method("get"):
		var raw_val: Variant = rx.get(field_name)
		if raw_val is bool:
			return raw_val
		return _is_truthy(raw_val)
	return false


func _get_rxn_float(rx: Resource, field: String, def: float) -> float:
	if rx and rx.has_method("get"):
		var raw_val: Variant = rx.get(field)
		if raw_val is float or raw_val is int:
			return float(raw_val)
	return def


func _get_rxn_string(rx: Resource, field: String, def: String) -> String:
	if rx and rx.has_method("get"):
		var raw_val: Variant = rx.get(field)
		if raw_val != null:
			return str(raw_val)
	return def


func _is_truthy(v: Variant) -> bool:
	if v is bool:
		return v
	if v is int or v is float:
		return absf(float(v)) > 0.0
	if v is String:
		return v != ""
	return v != null


# ----------------------------
# Progi pH
# ----------------------------

func _update_pH_bucket_from_state(mix: Mixture) -> void:
	mix.ensure_tags()

	var H: float = Mixture._get_float(mix.ions, "H+")
	var OH: float = Mixture._get_float(mix.ions, "OH-")
	var vol: float = max(1e-6, float(mix.tags.get("vol_u", 0.0)))
	var c: float = absf(H - OH) / vol

	var label: String

	if c <= neutral_c_eps:
		label = "neutral"
	else:
		var very_strong: bool = c >= ph_thresh_very
		var strong: bool = (not very_strong) and (c >= ph_thresh_strong)

		if (H - OH) > 0.0:
			label = ("very_strong_acid" if very_strong else ("strong_acid" if strong else "acidic"))
		else:
			label = ("very_strong_base" if very_strong else ("strong_base" if strong else "basic"))

	mix.tags["pH"] = label
	mix.tags["ph_grade7"] = _label_to_grade7(label)

	if debug_core:
		print("[QE pH] H=", H, " OH=", OH,
			" vol_u=", mix.tags.get("vol_u", 0.0),
			" c=", c,
			" -> label=", label, " grade7=", mix.tags.get("ph_grade7"))


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


# ----------------------------
# Liczniki nadmiaru
# ----------------------------

func _add_excess(mix: Mixture, key: String, amount: float) -> void:
	if mix == null or amount <= 0.0:
		return

	if not (mix.ions is Dictionary):
		mix.ions = {}

	var cur: float = 0.0
	if mix.ions.has(key):
		var raw_val: Variant = mix.ions[key]
		if raw_val is float or raw_val is int:
			cur = float(raw_val)

	mix.ions[key] = cur + amount

	if debug_core:
		print("[QE EXCESS] +", key, " = +", amount, "  → ", mix.ions[key])


func _neutralize_excess_pair(mix: Mixture, key_a: String, key_b: String) -> void:
	if mix == null or not (mix.ions is Dictionary):
		return

	var va: float = 0.0
	var vb: float = 0.0

	if mix.ions.has(key_a):
		var raw_a: Variant = mix.ions[key_a]
		if raw_a is float or raw_a is int:
			va = float(raw_a)

	if mix.ions.has(key_b):
		var raw_b: Variant = mix.ions[key_b]
		if raw_b is float or raw_b is int:
			vb = float(raw_b)

	var neutralized: float = min(va, vb)
	if neutralized <= 0.0:
		return

	var new_a: float = va - neutralized
	var new_b: float = vb - neutralized

	if new_a <= Mixture.EPS:
		mix.ions.erase(key_a)
	else:
		mix.ions[key_a] = new_a

	if new_b <= Mixture.EPS:
		mix.ions.erase(key_b)
	else:
		mix.ions[key_b] = new_b

	if debug_core:
		print("[QE EXCESS] neutralize ", key_a, " vs ", key_b, "  Δ=", neutralized,
			"  → ", key_a, "=", mix.ions.get(key_a, 0.0), "  ", key_b, "=", mix.ions.get(key_b, 0.0))


# ----------------------------
# Neutralizacja H+/OH− w roztworze
# ----------------------------

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


# ----------------------------
# Bufory
# ----------------------------

func _buffer_accumulate_from_reagent(mix: Mixture, reagent: Resource) -> void:
	if reagent == null or not reagent.has_method("get"):
		return
	if not (reagent is ReagentBuffer):
		return

	mix.ensure_tags()

	var add_cap: float = 0.0
	var cap_raw: Variant = reagent.get("buffer_cap_per_click")
	if cap_raw is float or cap_raw is int:
		add_cap = max(0.0, float(cap_raw))

	var cur_cap: float = 0.0
	if mix.tags.has("buffer_cap"):
		var cap_existing: Variant = mix.tags["buffer_cap"]
		if cap_existing is float or cap_existing is int:
			cur_cap = float(cap_existing)

	mix.tags["buffer_cap"] = cur_cap + add_cap

	var vol_added: float = 0.1
	var vol_raw: Variant = reagent.get("vol_per_click")
	if vol_raw is float or vol_raw is int:
		vol_added = max(0.0, float(vol_raw))

	var signed_bias: float = 0.0
	var bias_raw: Variant = reagent.get("buffer_bias")
	if bias_raw is float or bias_raw is int:
		signed_bias = float(bias_raw)

	var bias_amount: float = absf(signed_bias) * vol_added
	if bias_amount > Mixture.EPS:
		if signed_bias > 0.0:
			mix.ions["OH-"] = Mixture._get_float(mix.ions, "OH-") + bias_amount
		elif signed_bias < 0.0:
			mix.ions["H+"] = Mixture._get_float(mix.ions, "H+") + bias_amount


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

	var eat: float = min(excess, cap)

	if H >= OH:
		H -= eat
	else:
		OH -= eat

	if H <= Mixture.EPS:
		mix.ions.erase("H+")
	else:
		mix.ions["H+"] = H

	if OH <= Mixture.EPS:
		mix.ions.erase("OH-")
	else:
		mix.ions["OH-"] = OH

	mix.tags["buffer_cap"] = cap - eat


# ----------------------------
# Debug log
# ----------------------------

func _dbg_probe_name(tube: Node) -> String:
	if tube == null:
		return "<null>"
	if "name" in tube:
		return str(tube.name)
	return str(tube.get_instance_id())


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
