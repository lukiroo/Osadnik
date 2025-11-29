extends Resource
class_name Reaction
# Jedna reguła reakcji: reagenty -> produkty + proste warunki.

@export var id: String = ""          # np. "PbCl2_precip"
@export var priority: int = 0        # niższy = szybciej

@export var reactants_ions: Dictionary = {}
@export var reactants_solids: Dictionary = {}

@export var products_ions: Dictionary = {}
@export var products_solids: Dictionary = {}

@export var require_pH: Array[String] = []   # np. ["acidic"], ["basic"], itp.

@export var require_boiling: bool = false
@export var min_boil_time: float = 0.0       # w sekundach, 0 = bez limitu

@export var require_tags_all: Dictionary = {}
@export var forbid_tags_any: Array[String] = []

@export var set_tags: Dictionary = {}
@export var clear_tags: Array[String] = []

@export var note: String = ""                # opis do logów / UI

# Jak wygląda osad: zwykły "floc" albo "crystal" (PbCl2 po ochłodzeniu).
@export_enum("floc", "crystal", "cloudy")
var precip_mode: String = "floc"
