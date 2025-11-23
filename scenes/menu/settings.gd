extends Node

signal changed

## =========================================================================
## Settings.gd – autoload z ustawieniami i progresem
## -------------------------------------------------------------------------
## Odpowiada za:
## - przechowywanie ustawień UI (podświetlenia, etykiety, trudność),
## - zapisywanie/odczytywanie progresu poziomów do pliku,
## - wyliczanie parametrów zadań (liczba probówek, trudność mieszanin),
## - przekazywanie konfiguracji następnego levelu między scenami,
## - udostępnianie ostatniego podejścia do zapisu wyników.
## =========================================================================

const PATH: String = "user://settings.cfg"

# -------- USTAWIENIA UI --------
var highlights_enabled: bool = true      # podświetlanie narzędzi / probówek
var show_tube_labels: bool = true        # literki/numerki probówek
var difficulty_mode: int = 0             # 0 = normalny, 1 = trudny

# -------- KONFIGURACJA LEVELU --------
var _pending_level_config: Dictionary = {}

# -------- KOLEJNOŚĆ I PROGRES LEVELI --------
const LEVEL_ORDER: Array[String] = [
	"G1_EX1","G1_EX2",
	"G2_EX1","G2_EX2",
	"G3_EX1","G3_EX2",
	"G45_EX1","G45_EX2",
	"EXAM"
]

# level_key -> { passed, best_mistakes, best_stars }
var level_progress: Dictionary = {}

# Ostatni „run” – do przekazania danych do Results
var _last_run_ctx: Dictionary = {}


## Przy starcie gry wczytuje zapis z pliku, uzupełnia brakujące wpisy poziomów i emituje sygnał changed.
func _ready() -> void:
	_load()

	for key in LEVEL_ORDER:
		if not level_progress.has(key):
			level_progress[key] = {
				"passed": false,
				"best_mistakes": 999,
				"best_stars": 0
			}
	changed.emit()


# ======================= SETTERY UI ===============================

## Ustawia tryb trudności (0/1), zapisuje go do pliku i emituje sygnał changed.
func set_difficulty_mode(value: int) -> void:
	value = clamp(value, 0, 1)
	if difficulty_mode == value:
		return
	difficulty_mode = value
	_save()
	changed.emit()


## Włącza lub wyłącza globalne podświetlenia i zapisuje ten stan do pliku.
func set_highlight_enabled(is_enabled: bool) -> void:
	if highlights_enabled == is_enabled:
		return
	highlights_enabled = is_enabled
	_save()
	changed.emit()


## Włącza lub wyłącza etykiety probówek i zapisuje ten stan do pliku.
func set_show_tube_labels(is_enabled: bool) -> void:
	if show_tube_labels == is_enabled:
		return
	show_tube_labels = is_enabled
	_save()
	changed.emit()


# ===================== HELPERY DLA SCEN ===========================

## Zwraca, czy podświetlenia są aktualnie włączone.
func are_highlights_enabled() -> bool:
	return highlights_enabled


## Decyduje, czy kontener z probówkami ma pokazywać etykiety; w EX1 w ProbeBeaker zawsze wymusza true.
func should_show_tube_labels(mode_str: String, container_name: String) -> bool:
	if mode_str == "EXERCISE_SINGLE" and container_name == "ProbeBeaker":
		return true
	return show_tube_labels


# ==================== KONFIGURACJA NAST. LEVELU ==================

## Zapisuje w pamięci konfigurację następnego poziomu (tryb, grupa, liczby probówek).
func set_next_level_config(cfg: Dictionary) -> void:
	_pending_level_config = cfg.duplicate(true)


## Zwraca kopię zapisanej konfiguracji następnego poziomu i czyści bufor.
func get_and_clear_next_level_config() -> Dictionary:
	var out_cfg := _pending_level_config.duplicate(true)
	_pending_level_config.clear()
	return out_cfg


# =================== PARAMETRY ZADAŃ (rozmiary) ==================

# Wlicza ile probówek startowych i ile jonów ma mieć mieszanka, na podstawie trudności i tego, czy to egzamin.
func compute_level_counts(_mode_str: String, exam: bool = false) -> Dictionary:
	var starter_count := 3
	var mix_difficulty := 2

	if difficulty_mode == 1:
		starter_count = 5
		mix_difficulty = 3

	if exam:
		# egzamin: większe mieszanki
		mix_difficulty = (3 if difficulty_mode == 0 else 5)

	return {
		"starter_count": starter_count,
		"mix_difficulty": mix_difficulty
	}


# ====================== KLUCZE LEVELI ============================

## Buduje klucz poziomu na podstawie grupy i trybu, np. G1_EX1, G45_EX2, EXAM.
func level_key(group_id: int, mode_str: String) -> String:
	var suffix := ("EX1" if mode_str == "EXERCISE_SINGLE" else "EX2")
	if group_id == 0:
		return "EXAM"
	elif group_id == 4:
		return "G45_%s" % suffix
	else:
		return "G%d_%s" % [group_id, suffix]


## Sprawdza, czy dany poziom jest odblokowany na podstawie kolejności LEVEL_ORDER i flagi „passed” poprzedniego levelu.
func is_unlocked(level_key_str: String) -> bool:
	var idx := LEVEL_ORDER.find(level_key_str)
	if idx == -1:
		return false
	if idx == 0:
		return true   # pierwszy level zawsze dostępny

	var previous_key: String = LEVEL_ORDER[idx - 1]
	var prev_rec: Dictionary = level_progress.get(previous_key, {"passed": false})
	return bool(prev_rec.get("passed", false))


## Zwraca klucz następnego poziomu albo pusty string, jeśli to był ostatni.
func get_next_level_key(current_key: String) -> String:
	var idx := LEVEL_ORDER.find(current_key)
	if idx == -1 or idx == LEVEL_ORDER.size() - 1:
		return ""
	return LEVEL_ORDER[idx + 1]


# ====================== LICZENIE BŁĘDÓW ==========================

## Liczy błędy w ćwiczeniu 1: brak odpowiedzi lub zły jon w probówce liczy się jako błąd.
func count_mistakes_single(correct_map: Dictionary, user_map: Dictionary) -> int:
	var mistakes := 0
	for key in correct_map.keys():
		var expected: String = correct_map[key]
		var got: String = String(user_map.get(key, ""))
		if got == "" or got != expected:
			mistakes += 1
	return mistakes


## Liczy błędy w mieszaninie: zwraca max(brakujących jonów, nadmiarowych jonów).
func count_mistakes_mix(correct_list: Array, user_list: Array) -> int:
	var correct_set: Dictionary = {}
	for ion in correct_list:
		correct_set[ion] = true

	var user_set: Dictionary = {}
	for ion in user_list:
		user_set[ion] = true

	var missing := 0
	for ion in correct_set.keys():
		if not user_set.has(ion):
			missing += 1

	var extra := 0
	for ion in user_set.keys():
		if not correct_set.has(ion):
			extra += 1

	return max(missing, extra)


# ====================== GWIAZDKI / PROGRES =======================

## Określa maksymalną liczbę błędów, po której poziom jest jeszcze zaliczony.
func max_errors_allowed_for(group_id: int, exercise_id: String, difficulty_now: int) -> int:
	if group_id == 1:
		return 1

	if difficulty_now == 0:
		return 1
	else:
		if exercise_id == "EX1":
			return 2
		else:
			return 1


## Wylicza liczbę gwiazdek na podstawie liczby błędów, grupy, ćwiczenia i trybu trudności.
func compute_stars(mistakes: int, difficulty_now: int, group_id: int, exercise_id: String) -> int:
	if group_id == 1:
		if mistakes == 0:
			return 3
		elif mistakes == 1:
			return 1
		else:
			return 0

	if difficulty_now == 0:
		if mistakes == 0:
			return 2
		elif mistakes == 1:
			return 1
		else:
			return 0
	else:
		if exercise_id == "EX1":
			if mistakes == 0:
				return 3
			elif mistakes == 1:
				return 2
			elif mistakes == 2:
				return 1
			else:
				return 0
		else:
			if mistakes == 0:
				return 3
			elif mistakes == 1:
				return 2
			else:
				return 0


## Zwraca najlepszą liczbę gwiazdek zdobytą dotychczas na danym poziomie.
func get_best_stars(level_key_str: String) -> int:
	var rec: Dictionary = level_progress.get(level_key_str, {"best_stars": 0})
	return int(rec.get("best_stars", 0))


## Aktualizuje progres dla poziomu po podejściu, liczy gwiazdki, zapisuje do pliku i zwraca prosty podsumowujący słownik.
func submit_result(level_key_str: String, mistakes: int) -> Dictionary:
	var group_id := 0
	var exercise_id := "EX1"

	if level_key_str == "EXAM":
		group_id = 0
		exercise_id = "EX2"
	else:
		var parts: Array = level_key_str.split("_")  # "G1_EX1"
		var num_str: String = String(parts[0]).substr(1)  # "1", "2", "45"
		group_id = 4 if num_str == "45" else int(num_str)
		exercise_id = String(parts[1])

	var rec: Dictionary = level_progress.get(level_key_str, {
		"passed": false,
		"best_mistakes": 999,
		"best_stars": 0
	})

	if mistakes < int(rec.get("best_mistakes", 999)):
		rec["best_mistakes"] = mistakes

	var stars_now := compute_stars(mistakes, difficulty_mode, group_id, exercise_id)
	if stars_now > int(rec.get("best_stars", 0)):
		rec["best_stars"] = stars_now

	var passed_now := (stars_now > 0)
	if passed_now:
		rec["passed"] = true

	level_progress[level_key_str] = rec
	_save()
	changed.emit()

	var next_key := ""
	if passed_now:
		next_key = get_next_level_key(level_key_str)

	return {
		"passed": passed_now,
		"mistakes": mistakes,
		"next_unlocked": next_key
	}


# ====================== SAVE / LOAD ==============================

## Zapisuje ustawienia i progres do pliku ConfigFile pod ścieżką PATH.
func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "highlights_enabled", highlights_enabled)
	cfg.set_value("ui", "show_tube_labels", show_tube_labels)
	cfg.set_value("ui", "difficulty_mode", difficulty_mode)
	cfg.set_value("progress", "map", level_progress)
	cfg.save(PATH)


## Wczytuje ustawienia i progres z pliku, a gdy plik nie istnieje, tworzy domyślny zapis.
func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		level_progress = {}
		_save()
		return

	highlights_enabled = bool(cfg.get_value("ui", "highlights_enabled", highlights_enabled))
	show_tube_labels   = bool(cfg.get_value("ui", "show_tube_labels", show_tube_labels))
	difficulty_mode    = int(cfg.get_value("ui", "difficulty_mode", difficulty_mode))
	level_progress     = cfg.get_value("progress", "map", {}) as Dictionary


# ================== KONTEKST LAB → RESULTS =======================

## Zapisuje kontekst ostatniego podejścia z labu (tryb, grupa, poprawne odpowiedzi itp.).
func set_last_run_context(ctx: Dictionary) -> void:
	_last_run_ctx = ctx.duplicate(true)
	changed.emit()


## Zwraca kopię kontekstu ostatniego podejścia do ćwiczenia.
func get_last_run_context() -> Dictionary:
	return _last_run_ctx.duplicate(true)


# ==================== NARZĘDZIE DO RESETU ========================

## Czyści progres wszystkich poziomów i ustawia im domyślne wartości.
func reset_progress() -> void:
	level_progress.clear()
	for key in LEVEL_ORDER:
		level_progress[key] = {
			"passed": false,
			"best_mistakes": 999,
			"best_stars": 0
		}
	_save()
	changed.emit()
