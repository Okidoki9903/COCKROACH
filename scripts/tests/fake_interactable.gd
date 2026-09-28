extends Interactable
## Test-only target with a fixed prompt (tie-break and selection checks).

@export var prompt := "Test"
var uses := 0


func get_prompt(_interactor: PlayerInteractor) -> String:
	return prompt


func interact(_interactor: PlayerInteractor) -> bool:
	uses += 1
	return true
