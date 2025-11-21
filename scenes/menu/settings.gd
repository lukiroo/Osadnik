extends Node
signal changed

## =========================================================================
## Settings.gd – autoload z ustawieniami i progresem
## -------------------------------------------------------------------------
## - Przechowuje ustawienia UI (podświetlenia, etykiety, tryb trudności).
## - Trzyma progres leveli (zaliczone, najlepszy wynik, gwiazdki) i zapisuje
##   wszystko do pliku konfiguracyjnego.
## - Wylicza parametry zadań (ile probówek startowych, trudność mieszanin).
## - Przekazuje konfigurację „następnego poziomu” między scenami (Lab → Lab).
## - Udostępnia kontekst ostatniego podejścia do ćwiczenia (Lab → Results).
## =========================================================================

const PATH: String = "user://settings.cfg"  ## Plik z zapisanymi ustawieniami i progresem.

# ───────────────────────── USTAWIENIA UI ─────────────────────────
var highlights_enabled: bool = true   ## Podświetlenia probówek/narzędzi.
var show_tube_labels: bool = true     ## Numerki/etykiety na probówkach.
var difficulty_mode: int = 0          ## 0 = normalny, 1 = trudny.

# ───────────────────────── NEXT LEVEL CONFIG ─────────────────────
## Bufor z konfiguracją następnego poziomu – trzymany tylko w pamięci.
var _pending_level_config: Dictionary = {}

# ───────────────────────── KOLEJNOŚĆ LEVELI ──────────────────────
## Kolejność poziomów używana przy odblokowywaniu (następny po zaliczeniu).
const LEVEL_ORDER: Array[String] = [
	"G1_EX1","G1_EX2",
	"G2_EX1","G2_EX2",
	"G3_EX1","G3_EX2",
	"G45_EX1","G45_EX2",
	"EXAM"
]

## Mapa: level_key -> { "passed": bool, "best_mistakes": int, "best_stars": int }
var level_progress: Dictionary = {}

## Kontekst ostatniego podejścia do ćwiczenia (lab → ekran wyników).
var _last_run_ctx: Dictionary = {}


# ───────────────────────── ŁADOWANIE STARTOWE ─────────────────────────
func _ready() -> void:
	## Wczytanie ustawień z pliku i dopełnienie brakujących wpisów progresu.
	_load()
	for key in LEVEL_ORDER:
		if not level_progress.has(key):
			level_progress[key] = {
				"passed": false,
				"best_mistakes": 9999,
				"best_stars": 0
			}
	changed.emit()


# ───────────────────────── PUBLICZNE SETTERY UI ─────────────────────────
func set_difficulty_mode(value: int) -> void:
	## Ustawia tryb trudności (0/1) i zapisuje do pliku.
	value = clamp(value, 0, 1)
	if difficulty_mode == value:
		return
	difficulty_mode = value
	_save()
	changed.emit()


func set_highlight_enabled(is_enabled: bool) -> void:
	## Globalne włączenie/wyłączenie highlightów.
	if highlights_enabled == is_enabled:
		return
	highlights_enabled = is_enabled
	_save()
	changed.emit()


func set_show_tube_labels(is_enabled: bool) -> void:
	## Globalne włączenie/wyłączenie etykiet probówek.
	if show_tube_labels == is_enabled:
		return
	show_tube_labels = is_enabled
	_save()
	changed.emit()


# ───────────────────────── HELPERY DLA UI ─────────────────────────
func are_highlights_enabled() -> bool:
	## Prosty getter dla innych scen (Lab, Menu itp.).
	return highlights_enabled


func should_show_tube_labels(mode_str: String, container_name: String) -> bool:
	## W EXERCISE_SINGLE litery w ProbeBeaker są zawsze widoczne (A,B,C,...).
	if mode_str == "EXERCISE_SINGLE" and container_name == "ProbeBeaker":
		return true
	return show_tube_labels


# ───────────────────────── KONFIGURACJA LEVELI ─────────────────────────
func set_next_level_config(cfg: Dictionary) -> void:
	## Zapamiętuje konfigurację „następnego poziomu” przed przejściem do labu.
	_pending_level_config = cfg.duplicate(true)


func get_and_clear_next_level_config() -> Dictionary:
	## Pobiera i czyści zapisany wcześniej config kolejnego poziomu.
	var out_cfg: Dictionary = _pending_level_config.duplicate(true)
	_pending_level_config.clear()
	return out_cfg


# ───────────────────────── PARAMETRY ZADAŃ ─────────────────────────
func compute_level_counts(_mode_str: String, exam: bool = false) -> Dictionary:
	## Wylicza „rozmiar” zadania:
	## - ile probówek startowych w EX1,
	## - ilu kationów spodziewamy się w mieszaninie EX2.
	var starter_count: int = 3
	var mix_difficulty: int = 2

	if difficulty_mode == 1:
		starter_count = 5
		mix_difficulty = 3

	if exam:
		## Egzamin ma trochę większe mieszanki.
		mix_difficulty = (3 if difficulty_mode == 0 else 5)

	return {
		"starter_count": starter_count,
		"mix_difficulty": mix_difficulty
	}


# ───────────────────────── KLUCZE LEVELI ─────────────────────────
func level_key(group_id: int, mode_str: String) -> String:
	## Buduje klucz progresu na podstawie grupy i trybu:
	##   G1_EX1, G2_EX2, G45_EX1, EXAM itd.
	var suffix: String = ("EX1" if mode_str == "EXERCISE_SINGLE" else "EX2")
	if group_id == 0:
		return "EXAM"
	elif group_id == 4:
		return "G45_%s" % suffix
	else:
		return "G%d_%s" % [group_id, suffix]


## Nowa wersja – „limit błędów” zależny od grupy, ćwiczenia i trudności.
func max_errors_allowed_for(group_id: int, exercise_id: String, difficulty_now: int) -> int:
	# Grupa 1: 0 błędów = 3★, 1 błąd = 1★, >=2 = 0★ → limit błędów = 1
	if group_id == 1:
		return 1

	# Pozostałe grupy:
	if difficulty_now == 0:
		# tryb normalny: 0 błędów = 2★, 1 błąd = 1★, >=2 = 0★ → limit = 1
		return 1
	else:
		# tryb trudny
		if exercise_id == "EX1":
			# hard EX1: 0 → 3★, 1 → 2★, 2 → 1★, >=3 → 0★ → limit = 2
			return 2
		else:
			# hard EX2 (w tym EXAM): 0 → 3★, 1 → 2★, >=2 → 0★ → limit = 1
			return 1


func is_unlocked(level_key_str: String) -> bool:
	## Czy poziom jest odblokowany (poprzedni zaliczony).
	var idx: int = LEVEL_ORDER.find(level_key_str)
	if idx == -1:
		return false
	if idx == 0:
		return true  ## pierwszy poziom jest zawsze dostępny

	var previous_key: String = String(LEVEL_ORDER[idx - 1])
	var prev_rec: Dictionary = level_progress.get(previous_key, {"passed": false})
	return bool(prev_rec.get("passed", false))


func get_next_level_key(current_key: String) -> String:
	## Zwraca klucz kolejnego poziomu lub pusty string, jeśli to był ostatni.
	var idx: int = LEVEL_ORDER.find(current_key)
	if idx == -1 or idx == LEVEL_ORDER.size() - 1:
		return ""
	return String(LEVEL_ORDER[idx + 1])


# ───────────────────────── LICZENIE BŁĘDÓW ─────────────────────────
func count_mistakes_single(correct_map: Dictionary, user_map: Dictionary) -> int:
	## Ćwiczenie 1 – każda probówka ma dokładnie jeden poprawny kation.
	## Błąd liczy za:
	## - brak odpowiedzi,
	## - błędną odpowiedź.
	var mistakes: int = 0
	for key in correct_map.keys():
		var expected: String = String(correct_map[key])
		var got: String = String(user_map.get(key, ""))
		if got == "" or got != expected:
			mistakes += 1
	return mistakes


func count_mistakes_mix(correct_list: Array, user_list: Array) -> int:
	## Ćwiczenie 2 – mieszanka z kilkoma kationami.
	## Definicje:
	## - brakujący kation: był w mieszaninie, użytkownik go nie zaznaczył,
	## - nadmiarowy kation: użytkownik zaznaczył kation, którego nie było w mieszaninie,
	## - całkowity błąd = max(liczba brakujących, liczba nadmiarowych).
	var correct_set: Dictionary = {}
	for ion in correct_list:
		correct_set[ion] = true

	var user_set: Dictionary = {}
	for ion in user_list:
		user_set[ion] = true

	var missing_count: int = 0
	for ion in correct_set.keys():
		if not user_set.has(ion):
			missing_count += 1

	var extra_count: int = 0
	for ion in user_set.keys():
		if not correct_set.has(ion):
			extra_count += 1

	return max(missing_count, extra_count)


# ───────────────────────── GWIAZDKI I PROGRES ─────────────────────────
## group_id, exercise_id, difficulty_now
func compute_stars(	mistakes: int, difficulty_now: int, group_id: int, exercise_id: String) -> int:
	# Grupa 1 (EX1 i EX2):
	# 0 błędów = 3★
	# 1 błąd   = 1★
	# ≥2 błędów = 0★ (niezaliczone)
	if group_id == 1:
		if mistakes == 0:
			return 3
		elif mistakes == 1:
			return 1
		else:
			return 0

	# Pozostałe grupy:
	if difficulty_now == 0:
		# tryb normalny:
		# 0 błędów = 2★
		# 1 błąd   = 1★
		# ≥2 błędów = 0★
		if mistakes == 0:
			return 2
		elif mistakes == 1:
			return 1
		else:
			return 0
	else:
		# tryb trudny
		if exercise_id == "EX1":
			# hard EX1:
			# 0 błędów = 3★
			# 1 błąd   = 2★
			# 2 błędy  = 1★
			# ≥3 błędów = 0★
			if mistakes == 0:
				return 3
			elif mistakes == 1:
				return 2
			elif mistakes == 2:
				return 1
			else:
				return 0
		else:
			# hard EX2 (w tym egzamin, jeśli chcesz):
			# 0 błędów = 3★
			# 1 błąd   = 2★
			# ≥2 błędów = 0★
			if mistakes == 0:
				return 3
			elif mistakes == 1:
				return 2
			else:
				return 0


func get_best_stars(level_key_str: String) -> int:
	## Zwraca najlepszą (maksymalną) liczbę gwiazdek uzyskaną na danym poziomie.
	var rec: Dictionary = level_progress.get(level_key_str, {"best_stars": 0})
	return int(rec.get("best_stars", 0))


func submit_result(level_key_str: String, mistakes: int) -> Dictionary:
	## Aktualizuje zapis progresu dla danego poziomu po jednym podejściu.

	# Rozkodowanie group_id i exercise_id z level_key_str.
	var group_id: int = 0
	var exercise_id: String = "EX1"

	if level_key_str == "EXAM":
		group_id = 0
		exercise_id = "EX2"
	else:
		# "G1_EX1", "G2_EX2", "G45_EX1", ...
		var parts: Array = level_key_str.split("_")
		if parts.size() >= 2 and String(parts[0]).begins_with("G"):
			var num_str: String = String(parts[0]).substr(1) # "1"/"2"/"3"/"45"
			group_id = 4 if num_str == "45" else int(num_str)
			exercise_id = String(parts[1])  # "EX1" / "EX2"

	var rec: Dictionary = level_progress.get(level_key_str, {
		"passed": false,
		"best_mistakes": 9999,
		"best_stars": 0
	})

	# Minimalna liczba błędów (najlepszy wynik).
	if mistakes < int(rec.get("best_mistakes", 9999)):
		rec["best_mistakes"] = mistakes

	# Gwiazdki dla aktualnego podejścia wg nowych zasad.
	var stars_now: int = compute_stars(mistakes, difficulty_mode, group_id, exercise_id)
	if stars_now > int(rec.get("best_stars", 0)):
		rec["best_stars"] = stars_now

	# Zaliczenie poziomu = >=1 gwiazdka.
	var passed_now: bool = (stars_now > 0)
	if passed_now:
		rec["passed"] = true

	level_progress[level_key_str] = rec
	_save()
	changed.emit()

	var next_key: String = ""
	if passed_now:
		next_key = get_next_level_key(level_key_str)

	return {
		"passed": passed_now,
		"mistakes": mistakes,
		"next_unlocked": next_key
	}


# ───────────────────────── SAVE / LOAD ─────────────────────────
func _save() -> void:
	## Zapisuje ustawienia i progres do pliku konfiguracyjnego.
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "highlights_enabled", highlights_enabled)
	cfg.set_value("ui", "show_tube_labels", show_tube_labels)
	cfg.set_value("ui", "difficulty_mode", difficulty_mode)
	cfg.set_value("progress", "map", level_progress)
	cfg.save(PATH)


func _load() -> void:
	## Wczytuje ustawienia i progres z pliku (lub tworzy domyślny zapis).
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		level_progress = {}
		_save()
		return

	highlights_enabled = bool(cfg.get_value("ui", "highlights_enabled", highlights_enabled))
	show_tube_labels   = bool(cfg.get_value("ui", "show_tube_labels", show_tube_labels))
	difficulty_mode    = int(cfg.get_value("ui", "difficulty_mode", difficulty_mode))
	level_progress     = cfg.get_value("progress", "map", {}) as Dictionary


# ───────────────────────── KONTEKST PODEJŚCIA (Lab → Results) ─────────────────────────
func set_last_run_context(ctx: Dictionary) -> void:
	## Lab zapisuje tutaj „kontekst ostatniego podejścia” (tryb, grupa, odpowiedzi),
	## a ekran wyników (Results) tylko to odczytuje.
	_last_run_ctx = ctx.duplicate(true)
	changed.emit()


func get_last_run_context() -> Dictionary:
	## Zwraca kopię kontekstu ostatniego podejścia do ćwiczenia.
	return _last_run_ctx.duplicate(true)


# ───────────────────────── DODATKOWE NARZĘDZIA ─────────────────────────
func reset_progress() -> void:
	## Czyści progres wszystkich poziomów (dev / test).
	level_progress.clear()
	for key in LEVEL_ORDER:
		level_progress[key] = {
			"passed": false,
			"best_mistakes": 9999,
			"best_stars": 0
		}
	_save()
	changed.emit()
