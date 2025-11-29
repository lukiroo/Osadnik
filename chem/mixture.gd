extends Resource
class_name Mixture

## =========================================================================
## mixture.gd – model mieszaniny w probówce
## -------------------------------------------------------------------------
## Reprezentuje stan chemiczny pojedynczej probówki:
## - ions   : jony w roztworze (np. "H+", "Cl-", "Pb2+"),
## - solids : osady w ilościach stechiometrycznych (np. "PbCl2_s": 3.0),
## - tags   : dodatkowe informacje (vol_u, pH, precip_mode, pellet_ready,
##            cooling_ready, cooling_t_s, cooled_enough itd.).
## =========================================================================

const EPS: float = 1e-6

## Słownik jonów w roztworze.
var ions: Dictionary = {}

## Słownik osadów (solids) – ilości w „jednostkach” modelowych.
var solids: Dictionary = {}

## Dodatkowe tagi (pH, vol_u, pellet_ready, cooling_* itd.).
var tags: Dictionary = {}


# =========================================================================
# HELPERY NUMERYCZNE
# =========================================================================

## Zwraca wartość float z danego słownika (lub 0.0 gdy brak/niepoprawne).
static func _get_float(data: Dictionary, key: Variant) -> float:
	if data == null or not (data is Dictionary) or not data.has(key):
		return 0.0
	var value: Variant = data[key]
	if value is float:
		return value
	if value is int:
		return float(value)
	return 0.0


## Konwertuje dowolny Variant na float (jeśli jest int/float), w innym wypadku 0.0.
static func _float_num(value: Variant) -> float:
	return float(value) if (value is float or value is int) else 0.0


# =========================================================================
# TAGI I OBJĘTOŚĆ
# =========================================================================

## Upewnia się, że tags jest słownikiem.
func ensure_tags() -> void:
	if not (tags is Dictionary):
		tags = {}


## Zwraca objętość mieszaniny w jednostkach vol_u.
func get_vol() -> float:
	return _float_num(tags.get("vol_u", 0.0))


## Ustawia objętość mieszaniny (nie ujemną).
func set_vol(volume: float) -> void:
	ensure_tags()
	tags["vol_u"] = max(0.0, volume)


## Zwiększa lub zmniejsza objętość mieszaniny o podaną wartość.
func add_vol(delta_volume: float) -> void:
	if absf(delta_volume) <= EPS:
		return
	set_vol(max(0.0, get_vol() + delta_volume))


# =========================================================================
# DEBUG: ACID_EQ / BASE_EQ
# =========================================================================

## Przelicza pomocnicze wartości acid_eq i base_eq na podstawie H+ i OH-.
func recompute_acid_base_eq_from_ions() -> void:
	ensure_tags()
	var h_val: float = _get_float(ions, "H+")
	var oh_val: float = _get_float(ions, "OH-")
	tags["acid_eq"] = max(h_val - oh_val, 0.0)
	tags["base_eq"] = max(oh_val - h_val, 0.0)


# =========================================================================
# OPERACJE NA JONACH
# =========================================================================

## Dodaje jony z podanego słownika (sumuje ilości).
func add_ions(ions_to_add: Dictionary) -> void:
	if ions_to_add == null or not (ions_to_add is Dictionary):
		return
	for ion_name in ions_to_add.keys():
		var add_val: float = _float_num(ions_to_add[ion_name])
		if absf(add_val) <= EPS:
			continue
		var current_val: float = _get_float(ions, ion_name)
		ions[ion_name] = current_val + add_val


## Odejmuje jony z podanego słownika (nie pozwala spaść poniżej zera).
func remove_ions(ions_to_remove: Dictionary) -> void:
	if ions_to_remove == null or not (ions_to_remove is Dictionary):
		return
	for ion_name in ions_to_remove.keys():
		var sub_val: float = _float_num(ions_to_remove[ion_name])
		if absf(sub_val) <= EPS:
			continue
		var current_val: float = _get_float(ions, ion_name)
		var new_val: float = max(0.0, current_val - sub_val)
		if new_val <= EPS:
			ions.erase(ion_name)
		else:
			ions[ion_name] = new_val


# =========================================================================
# OPERACJE NA OSADACH (STECHIOMETRIA)
# =========================================================================

## Dodaje osady z podanego słownika (sumuje ilości stechiometryczne).
func add_solids(solids_to_add: Dictionary) -> void:
	if solids_to_add == null or not (solids_to_add is Dictionary):
		return
	for solid_name in solids_to_add.keys():
		var add_val: float = _float_num(solids_to_add[solid_name])
		if absf(add_val) <= EPS:
			continue
		var current_val: float = _get_float(solids, solid_name)
		var new_val: float = current_val + add_val
		if new_val > EPS:
			solids[String(solid_name)] = new_val
		else:
			solids.erase(String(solid_name))


## Odejmuje osady z podanego słownika (nie pozwala spaść poniżej zera).
func remove_solids(solids_to_remove: Dictionary) -> void:
	if solids_to_remove == null or not (solids_to_remove is Dictionary):
		return
	for solid_name in solids_to_remove.keys():
		var sub_val: float = _float_num(solids_to_remove[solid_name])
		if absf(sub_val) <= EPS:
			continue
		var current_val: float = _get_float(solids, solid_name)
		var new_val: float = max(0.0, current_val - sub_val)
		if new_val <= EPS:
			solids.erase(String(solid_name))
		else:
			solids[String(solid_name)] = new_val


# =========================================================================
# ZAPYTANIA DLA QUALENGINE
# =========================================================================

## Sprawdza, czy mieszanina zawiera wymagane jony:
## - wartości dodatnie → sprawdza ilość (cur >= required),
## - wartości <= 0 → traktuje jako „musi być obecny” (cur > 0).
func has_ions(need: Dictionary) -> bool:
	if need == null or not (need is Dictionary):
		return true
	for ion_name in need.keys():
		var required_val: float = _float_num(need[ion_name])
		var current_val: float = _get_float(ions, ion_name)
		if required_val > EPS:
			if current_val + EPS < required_val:
				return false
		else:
			if current_val <= EPS:
				return false
	return true


## Sprawdza, czy mieszanina zawiera wymagane osady:
## - wartości dodatnie → sprawdza ilość (cur >= required),
## - wartości <= 0 → traktuje jako „musi być obecny”.
func has_solids(need: Dictionary) -> bool:
	if need == null or not (need is Dictionary):
		return true
	for solid_name in need.keys():
		var required_val: float = _float_num(need[solid_name])
		var current_val: float = _get_float(solids, solid_name)
		if required_val > EPS:
			if current_val + EPS < required_val:
				return false
		else:
			if current_val <= EPS:
				return false
	return true


## Sprawdza, czy mieszanina jest pusta (brak jonów, brak osadów, objętość ≈ 0).
func is_empty() -> bool:
	return ions.is_empty() and solids.is_empty() and get_vol() <= EPS


# =========================================================================
# KOPIE I SCALANIE MIESZANIN
# =========================================================================

## Tworzy głęboką kopię mieszaniny (jonów, osadów i tagów).
func clone() -> Mixture:
	var copy: Mixture = Mixture.new()
	copy.ions = ions.duplicate(true)
	copy.solids = solids.duplicate(true)
	copy.tags = tags.duplicate(true)
	return copy


## Scala inną mieszaninę z bieżącą:
## - sumuje jony i osady,
## - sumuje vol_u,
## - przepisuje pozostałe tagi (z wyjątkiem pH/acid_eq/base_eq).
func merge_from(other: Mixture) -> void:
	if other == null:
		return

	# jony
	if other.ions is Dictionary:
		for ion_name in other.ions.keys():
			var current_val: float = _get_float(ions, ion_name)
			var other_val: float = _get_float(other.ions, ion_name)
			ions[ion_name] = current_val + other_val

	# osady
	if other.solids is Dictionary:
		for solid_name in other.solids.keys():
			var current_val: float = _get_float(solids, solid_name)
			var other_val: float = _get_float(other.solids, solid_name)
			var new_val: float = current_val + other_val
			if new_val > EPS:
				solids[String(solid_name)] = new_val
			else:
				solids.erase(String(solid_name))

	# tagi / objętość
	if other.tags is Dictionary:
		for key in other.tags.keys():
			var key_str := String(key)
			match key_str:
				"pH", "ph_grade7", "acid_eq", "base_eq":
					continue
				"vol_u":
					var add_vol_val: float = _float_num(other.tags[key])
					var my_vol_val: float = _float_num(tags.get(key_str, 0.0))
					tags[key_str] = my_vol_val + add_vol_val
				_:
					tags[key_str] = other.tags[key]

	recompute_acid_base_eq_from_ions()


## Dodaje inną mieszaninę „in-place” i czyści ją po scaleniu.
func add_inplace(other: Mixture) -> void:
	if other == null:
		return
	merge_from(other)
	other.clear_all()


# =========================================================================
# PRZELEWANIE (FRAGMENTY MIESZANINY)
# =========================================================================

## Tworzy nową mieszaninę będącą ułamkiem bieżącej:
## - skaluje ilości jonów i osadów proporcjonalnie do frac,
## - kopiuje vol_u, precip_mode i tagi chłodzenia (cooling_*),
## - przelicza acid_eq/base_eq tylko dla porcji.
func scaled_fraction(frac: float, _move_solids: bool = false) -> Mixture:
	var f: float = clamp(frac, 0.0, 1.0)
	var out_mix: Mixture = Mixture.new()

	# jony
	for ion_name in ions.keys():
		var current_val: float = _get_float(ions, ion_name)
		var part_val: float = current_val * f
		if part_val > EPS:
			out_mix.ions[ion_name] = part_val

	# osady
	if solids is Dictionary and solids.size() > 0:
		for solid_name in solids.keys():
			var current_val: float = _get_float(solids, solid_name)
			var part_val: float = current_val * f
			if part_val > EPS:
				out_mix.solids[String(solid_name)] = part_val

	# tagi – objętość i wybrane tagi (precip_mode, cooling_*).
	out_mix.ensure_tags()
	if tags is Dictionary:
		var src_tags: Dictionary = tags

		# objętość porcji
		var vol_val: float = _float_num(src_tags.get("vol_u", 0.0))
		out_mix.tags["vol_u"] = vol_val * f

		# typ osadu (floc / crystal / cloudy)
		if src_tags.has("precip_mode"):
			out_mix.tags["precip_mode"] = src_tags["precip_mode"]

		# stan chłodzenia: cooling_ready / cooling_t_s / cooled_enough
		for tag_name in ["cooling_ready", "cooling_t_s", "cooled_enough"]:
			if src_tags.has(tag_name):
				out_mix.tags[tag_name] = src_tags[tag_name]

	out_mix.recompute_acid_base_eq_from_ions()
	return out_mix


## Odejmuje z mieszaniny ułamek wolumenu:
## - skaluje ilości jonów i osadów przez (1 - frac),
## - skaluje vol_u,
## - przelicza acid_eq/base_eq po zmianie.
func subtract_fraction_in_place(frac: float) -> void:
	var f: float = clamp(frac, 0.0, 1.0)
	var keep: float = 1.0 - f
	if f <= EPS:
		return

	# jony
	var ion_keys: Array = ions.keys()
	for ion_name in ion_keys:
		var current_val: float = _get_float(ions, ion_name)
		var new_val: float = current_val * keep
		if new_val <= EPS:
			ions.erase(ion_name)
		else:
			ions[ion_name] = new_val

	# osady
	var solid_keys: Array = solids.keys()
	for solid_name in solid_keys:
		var current_val: float = _get_float(solids, solid_name)
		var new_val: float = current_val * keep
		if new_val <= EPS:
			solids.erase(solid_name)
		else:
			solids[String(solid_name)] = new_val

	# objętość
	if tags is Dictionary:
		var vol_val: float = _float_num(tags.get("vol_u", 0.0))
		tags["vol_u"] = vol_val * keep

	recompute_acid_base_eq_from_ions()


## Pobiera określoną objętość z mieszaniny (take_volume):
## - zwraca nowy Mixture zawierający pobraną porcję,
## - skaluje jony proporcjonalnie do objętości,
## - dla osadów:
##   - przy pełnym pobraniu i braku pelletu – przenosi wszystkie solids,
##   - przy pellet_ready – supernatant nie niesie solids.
func take_volume(vol: float) -> Mixture:
	var out_mix: Mixture = Mixture.new()
	var src_vol: float = get_vol()
	if src_vol <= EPS or vol <= EPS:
		return out_mix

	var take_vol: float = clamp(vol, 0.0, src_vol)
	var frac: float = take_vol / src_vol

	var pellet_ready: bool = false
	if tags is Dictionary:
		pellet_ready = bool(tags.get("pellet_ready", false))

	# jony – proporcjonalnie
	var ion_keys: Array = ions.keys()
	for ion_name in ion_keys:
		var current_val: float = _get_float(ions, ion_name)
		var part_val: float = current_val * frac
		if part_val > EPS:
			out_mix.ions[ion_name] = part_val
			var left_val: float = current_val - part_val
			if left_val <= EPS:
				ions.erase(ion_name)
			else:
				ions[ion_name] = left_val

	# osady – normalnie tylko przy pełnym pobraniu, przy pellecie supernatant nie niesie solids.
	var full_take: bool = (1.0 - frac) <= EPS
	if full_take and not pellet_ready:
		for solid_name in solids.keys():
			out_mix.solids[String(solid_name)] = solids[solid_name]
		solids.clear()
	elif pellet_ready:
		out_mix.solids.clear()
		out_mix.ensure_tags()
		(out_mix.tags as Dictionary).erase("precip_mode")

	# objętość + proste tagi
	ensure_tags()
	out_mix.ensure_tags()
	var vol_val: float = _float_num(tags.get("vol_u", 0.0))
	var out_vol: float = vol_val * frac
	out_mix.tags["vol_u"] = out_vol
	tags["vol_u"] = vol_val - out_vol

	# jeżeli to nie jest supernatant znad pelletu i przelewamy całą probówkę,
	# przenosimy też precip_mode do porcji
	if not pellet_ready and full_take and (tags is Dictionary) and (tags as Dictionary).has("precip_mode"):
		out_mix.tags["precip_mode"] = (tags as Dictionary)["precip_mode"]

	# stan chłodzenia: cooling_ready / cooling_t_s / cooled_enough
	if tags is Dictionary:
		var src_tags: Dictionary = tags
		for tag_name in ["cooling_ready", "cooling_t_s", "cooled_enough"]:
			if src_tags.has(tag_name):
				out_mix.tags[tag_name] = src_tags[tag_name]

	recompute_acid_base_eq_from_ions()
	out_mix.recompute_acid_base_eq_from_ions()
	return out_mix


## Pobiera ułamek objętości mieszanki (take_fraction) i zwraca nowy Mixture.
func take_fraction(frac: float) -> Mixture:
	var clamped_frac: float = clamp(frac, 0.0, 1.0)
	return take_volume(get_vol() * clamped_frac)


# =========================================================================
# CZYSZCZENIE
# =========================================================================

## Czyści wszystkie dane mieszaniny (jony, osady, tagi).
func clear_all() -> void:
	ions.clear()
	solids.clear()
	tags.clear()
