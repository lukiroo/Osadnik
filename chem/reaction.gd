extends Resource
class_name Reaction
# Reguła reakcji chemicznej obsługiwana przez Qualengine (substraty -> produkty)

# Id reakcji (np. AgCl_precip)
@export var id: String = ""

# Priority - która reakcja ma pierwszeństwo i zachodzi wcześniej
@export var priority: int = 0

# Substraty reakcji obecne w mieszaninie, np. jony, nadmiary bufora, osady
@export var reactants_ions: Dictionary = {}
@export var reactants_solids: Dictionary = {}

# Produkty, które pojawią się po zadziałaniu reakcji, np jony, osady
@export var products_ions: Dictionary = {}
@export var products_solids: Dictionary = {}


# Warunki pH - w jakim środowisku dozwolona jest reakcja (pH z Qualengine)
@export var require_pH: Array[String] = []


# Warunki termiczne - zagotowanie
@export var require_boiling: bool = false

# Czy probówka ma być po prostu „gorąca”.
#@export var require_is_hot: bool = false

# Minimalny czas gotowania (sekundy)
@export var min_boil_time: float = 0.0


# Inne warunki reakcji
@export var require_tags_all: Dictionary = {} # tagi wymagane do zajścia reakcji
@export var forbid_tags_any: Array[String] = [] # tagi niedozwolone blokujące reakcje 

@export var set_tags: Dictionary = {} # tagi dodawane po zadziałaniu reakcji
@export var clear_tags: Array[String] = [] # tagi usuwane po zadziałaniu reakcji


# Wygląd osadu (log) - opis
@export var note: String = ""

# Kolor osadu / mętności
#@export var precip_color: Color = Color.WHITE

# Rodzaj osadu
@export_enum("floc", "crystal", "cloudy")
var precip_mode: String = "floc"

# Intensywność efektu wizualnego (0-1)
@export_range(0.0, 1.0, 0.01)
var intensity: float = 0.6
