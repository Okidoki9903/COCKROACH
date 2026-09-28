class_name HumanTuning
extends Resource
## Every number that shapes the human, in one place (data/tuning/*.tres).
## Distances in metres, times in seconds, angles in degrees.

@export_group("Movement")
@export var walk_speed := 0.5
@export var approach_speed := 0.6
@export var turn_speed := 5.0          ## rad/s
@export var arrive_distance := 0.03
@export var stride_length := 0.45      ## one footstep event per stride

@export_group("Perception")
@export var eye_height := 1.6
@export var view_range := 1.6          ## horizontal, from the body centre
@export var view_half_angle := 60.0
@export var near_blind := 0.15         ## too close under the body to be seen
@export var confirm_time := 0.8        ## continuous sight to confirm
@export var forget_time := 1.5         ## time for a full doubt to fade
@export var lose_time := 0.4           ## unseen time before searching

@export_group("Search")
@export var search_duration := 4.0     ## looking around once at the spot
@export var search_max := 10.0         ## hard limit for the whole search
@export var search_sweep := 45.0       ## head sweep either side

@export_group("Capture")
@export var capture_reach := 0.4       ## human centre to target, horizontal
@export var capture_radius := 0.035    ## zone around the frozen point
@export var windup_time := 0.7
@export var lead := 0.6                ## fraction of the move during windup aimed ahead
@export var capture_cooldown := 1.0

@export_group("Player cues")
@export var cue_range := 0.8           ## footsteps felt within this distance
