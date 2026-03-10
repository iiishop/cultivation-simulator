extends Node

@export var terrain_generator: TerrainGenerator
@export var progress_bar: ProgressBar
@export var status_label: Label


func _ready() -> void:
	if terrain_generator == null:
		terrain_generator = get_parent().get_node_or_null("TerrainMap") as TerrainGenerator
	if progress_bar == null:
		progress_bar = get_parent().get_node_or_null("UI/GenerationProgress") as ProgressBar
	if status_label == null:
		status_label = get_parent().get_node_or_null("UI/GenerationStatus") as Label

	if terrain_generator:
		terrain_generator.generation_started.connect(_on_generation_started)
		terrain_generator.generation_progress.connect(_on_generation_progress)
		terrain_generator.generation_completed.connect(_on_generation_completed)

	if progress_bar:
		progress_bar.hide()
	if status_label:
		status_label.hide()


func _on_generation_started(_size: int) -> void:
	if progress_bar:
		progress_bar.value = 0.0
		progress_bar.show()
	if status_label:
		status_label.text = "生成中..."
		status_label.show()


func _on_generation_progress(stage: String, progress: float) -> void:
	if progress_bar:
		progress_bar.value = progress * 100.0
	if status_label:
		status_label.text = "生成中: %s (%d%%)" % [stage, int(progress * 100.0)]


func _on_generation_completed(_report: Dictionary) -> void:
	if progress_bar:
		progress_bar.value = 100.0
		progress_bar.hide()
	if status_label:
		status_label.hide()
