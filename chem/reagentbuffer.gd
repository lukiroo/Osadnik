extends Reagent
class_name ReagentBuffer
# Odczynnik, który zachowuje się jak bufor pH (neutralizuje nadmiar H+ / OH-),

# Flaga reagent / bufor
@export var is_buffer: bool = false

# Pojemność 1 porcji bufora (ile łącznie H+/OH- może zneutralizować)
@export var buffer_cap_per_click: float = 2.0

# Charakter pH na jednostkę objętości:
#   < 0  lekko kwaśny (lekki nadmiar H+),
#   > 0  lekko zasadowy (lekki nadmiar OH-),
#   = 0  obojętny (równowaga H+/OH-).
@export var buffer_bias: float = 0.0
