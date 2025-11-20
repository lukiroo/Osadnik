extends Resource
class_name Mixture
# Skrypt opisujący mieszaninę w jednej probówce.
# Stan chemiczny: jony (ions), osady (solids)
# Inne parametry: objętość, pH, dodatkowe tagi.

# EPS - wartość progowa / tolerancja błędu (jeżeli mniejsze od 10^-6, to jakościowo można pominąć)
const EPS: float = 1e-6

var ions: Dictionary = {}
var solids: Dictionary = {}
var tags: Dictionary = {}

# -----------------------------
# Helpery numeryczne
# -----------------------------

static func _get_float(d: Dictionary, k: Variant) -> float:
	# Pobieranie float ze słownika z kluczem k
	if d == null or not (d is Dictionary) or not d.has(k):
		return 0.0

	var v: Variant = d[k]
	if v is float:
		return v
	if v is int:
		return float(v)
	return 0.0


static func _float_num(v: Variant) -> float:
	# Przekształcenie int/float na float
	return float(v) if (v is float or v is int) else 0.0


static func _is_present(v: Variant) -> bool:
	# Sprawdzanie obecności (liczba > EPS lub bool true)
	return ((v is float or v is int) and float(v) > EPS) or (v is bool and v)


# -----------------------------
# Tagi i objętość
# -----------------------------

func ensure_tags() -> void:
	# Sprawdza czy tags jest słownikiem
	if not (tags is Dictionary):
		tags = {}


func get_vol() -> float:
	# Zwraca aktualną objętość roztworu
	return _float_num(tags.get("vol_u", 0.0))


func set_vol(v: float) -> void:
	# Ustawia objętość roztworu
	ensure_tags()
	tags["vol_u"] = max(0.0, v)


func add_vol(dv: float) -> void:
	# Dodaje/odejmuje objętości
	if absf(dv) <= EPS:
		return

	set_vol(max(0.0, get_vol() + dv))


# -----------------------------
# Debug: ekwiwalenty acid_eq / base_eq na podstawie H+ i OH-
# -----------------------------

func recompute_acid_base_eq_from_ions() -> void:

	ensure_tags()

	var h_val: float = _get_float(ions, "H+")
	var oh_val: float = _get_float(ions, "OH-")

	tags["acid_eq"] = max(h_val - oh_val, 0.0)
	tags["base_eq"] = max(oh_val - h_val, 0.0)


# -----------------------------
# Operacje na jonach
# -----------------------------

func add_ions(ions_to_add: Dictionary) -> void:
	# Dodaje jony z podanego słownika do bieżącej mieszaniny w probówce
	if ions_to_add == null or not (ions_to_add is Dictionary):
		return

	for ion_name in ions_to_add.keys():
		var add_val: float = _float_num(ions_to_add[ion_name])
		if absf(add_val) <= EPS:
			continue

		var cur_val: float = _get_float(ions, ion_name)
		ions[ion_name] = cur_val + add_val


func remove_ions(ions_to_remove: Dictionary) -> void:
	# Odejmuje ilości jonów według słownika
	if ions_to_remove == null or not (ions_to_remove is Dictionary):
		return

	for ion_name in ions_to_remove.keys():
		var sub_val: float = _float_num(ions_to_remove[ion_name])
		if absf(sub_val) <= EPS:
			continue

		var cur_val: float = _get_float(ions, ion_name)
		var new_val: float = max(0.0, cur_val - sub_val)

		if new_val <= EPS:
			# Jeśli zostały wartości śladowe -> przyjmuje że nic nie zostało
			ions.erase(ion_name)
		else:
			ions[ion_name] = new_val


# -----------------------------
# Operacje na osadach
# -----------------------------

func add_solids(solids_to_add: Dictionary) -> void:
	# Dodaje osady do mieszaniny
	if solids_to_add == null or not (solids_to_add is Dictionary):
		return

	for solid_name in solids_to_add.keys():
		if not _is_present(solids_to_add[solid_name]):
			continue
		solids[String(solid_name)] = 1.0


func remove_solids(solids_to_remove: Dictionary) -> void:
	# Usuwa podane osady z mieszaniny
	if solids_to_remove == null or not (solids_to_remove is Dictionary):
		return

	for solid_name in solids_to_remove.keys():
		solids.erase(String(solid_name))


# -----------------------------
# Zapytania do Qualengine
# -----------------------------

func has_ions(need: Dictionary) -> bool:
	# Sprawdza czy mieszanina spełnia wymagania jonowe dla reakcji
	if need == null or not (need is Dictionary):
		return true

	for ion_name in need.keys():
		var required_val: float = _float_num(need[ion_name])
		var cur_val: float = _get_float(ions, ion_name)

		if required_val > EPS:
			if cur_val + EPS < required_val:
				return false
		else:
			if cur_val <= EPS:
				return false

	return true


func has_solids(need: Dictionary) -> bool:
	# Sprawdza wszystkie wymagane osady są obecne w solids
	if need == null or not (need is Dictionary):
		return true

	for solid_name in need.keys():
		if not solids.has(String(solid_name)):
			return false

	return true


func is_empty() -> bool:
	# „Pusta” probówka: brak jonów, osadów, objętość 0
	return ions.is_empty() and solids.is_empty() and get_vol() <= EPS


# -----------------------------
# Kopie i scalanie
# -----------------------------

func clone() -> Mixture:
	# Robi kopię mieszaniny (duplikat probówki)
	var m: Mixture = Mixture.new()
	m.ions = ions.duplicate(true)
	m.solids = solids.duplicate(true)
	m.tags = tags.duplicate(true)
	return m


func merge_from(other: Mixture) -> void:
	# Wlewanie jednej mieszaniny do drugiej (dodawanie zawartości).
	if other == null:
		return

	# jony – suma ilości
	if other.ions is Dictionary:
		for ion_name in other.ions.keys():
			var cur_val: float = _get_float(ions, ion_name)
			var other_val: float = _get_float(other.ions, ion_name)
			ions[ion_name] = cur_val + other_val

	# osady – suma presence-only
	if other.solids is Dictionary:
		for solid_name in other.solids.keys():
			if _is_present(other.solids[solid_name]):
				solids[String(solid_name)] = 1.0

	# objętość - suma volume
	if other.tags is Dictionary:
		for k in other.tags.keys():
			var key_str := String(k)

			if key_str == "pH":
				continue
			elif key_str == "vol_u":
				var add_vol_val: float = _float_num(other.tags[k])
				var my_vol_val: float = _float_num(tags.get(key_str, 0.0))
				tags[key_str] = my_vol_val + add_vol_val
			elif key_str == "acid_eq" or key_str == "base_eq":
				continue
			else:
				tags[key_str] = other.tags[k]

	recompute_acid_base_eq_from_ions()


func add_inplace(other: Mixture) -> void:
	# Dolewa pełną zawartość z jednej do drugiej probówki i zostawia ją czystą
	if other == null:
		return

	merge_from(other)
	other.clear_all()


# -----------------------------
# Przelewanie
# -----------------------------

func scaled_fraction(frac: float, move_solids: bool = false) -> Mixture:
	# Zwraca nową mieszaninę będącą ułamkiem tej oryginalnej
	var f: float = clamp(frac, 0.0, 1.0)
	var out_mix: Mixture = Mixture.new()

	# jony – proporcja f
	for ion_name in ions.keys():
		var cur_val: float = _get_float(ions, ion_name)
		var part_val: float = cur_val * f
		if part_val > EPS:
			out_mix.ions[ion_name] = part_val

	# osady – jeśli bierzemy całość
	if move_solids and f >= 1.0 - EPS:
		for solid_name in solids.keys():
			out_mix.solids[String(solid_name)] = 1.0

	# objętość – proporcja f
	out_mix.ensure_tags()
	if tags is Dictionary:
		var vol_val: float = _float_num(tags.get("vol_u", 0.0))
		out_mix.tags["vol_u"] = vol_val * f

	recompute_acid_base_eq_from_ions()
	out_mix.recompute_acid_base_eq_from_ions()
	return out_mix


func subtract_fraction_in_place(frac: float, move_solids: bool = false) -> void:
	# Zostawia w probówce 1 - frac zawartości
	var f: float = clamp(frac, 0.0, 1.0)
	var keep: float = 1.0 - f

	if f <= EPS:
		return

	# jony – skalowane w dół
	var ion_keys: Array = ions.keys()
	for ion_name in ion_keys:
		var cur_val: float = _get_float(ions, ion_name)
		var new_val: float = cur_val * keep

		if new_val <= EPS:
			ions.erase(ion_name)
		else:
			ions[ion_name] = new_val

	# osady –  usuwane przy wylaniu całości
	if move_solids and f >= 1.0 - EPS:
		solids.clear()

	# objętość – też skala keep
	if tags is Dictionary:
		var vol_val: float = _float_num(tags.get("vol_u", 0.0))
		tags["vol_u"] = vol_val * keep

	recompute_acid_base_eq_from_ions()


func take_volume(vol: float) -> Mixture:
	# Pobiera z probówki konkretną objętość do nowej mieszaniny.
	var out_mix: Mixture = Mixture.new()
	var src_vol: float = get_vol()

	if src_vol <= EPS or vol <= EPS:
		return out_mix

	var take_vol: float = clamp(vol, 0.0, src_vol)
	var f: float = take_vol / src_vol

	# jony – cprzenoszenie części do out_mix, reszta zostaje
	var ion_keys: Array = ions.keys()
	for ion_name in ion_keys:
		var cur_val: float = _get_float(ions, ion_name)
		var part_val: float = cur_val * f

		if part_val > EPS:
			out_mix.ions[ion_name] = part_val

			var left_val: float = cur_val - part_val
			if left_val <= EPS:
				ions.erase(ion_name)
			else:
				ions[ion_name] = left_val

	# osady – przenoszenie tylko jeśli bierzemy całą zawartość
	var full_take: bool = (1.0 - f) <= EPS
	if full_take:
		for solid_name in solids.keys():
			out_mix.solids[String(solid_name)] = 1.0
		solids.clear()

	# objętość - tak jak jony
	ensure_tags()
	out_mix.ensure_tags()
	var vol_val: float = _float_num(tags.get("vol_u", 0.0))
	out_mix.tags["vol_u"] = vol_val * f
	tags["vol_u"] = vol_val - out_mix.tags["vol_u"]

	recompute_acid_base_eq_from_ions()
	out_mix.recompute_acid_base_eq_from_ions()
	return out_mix


func take_fraction(frac: float) -> Mixture:
	# Wersja „na procent”: bierzemy część aktualnej objętości.
	var f: float = clamp(frac, 0.0, 1.0)
	return take_volume(get_vol() * f)


# -----------------------------
# Czyszczenie - reset mieszaniny lub wypłukanie probówki
# -----------------------------
func clear_all() -> void:
	ions.clear()
	solids.clear()
	tags.clear()
