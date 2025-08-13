extends Control

@export var color_picker: ColorPickerButton
@export var size_slider: Slider
@export var size_label: Label
@export var rot_slider: Slider
@export var rot_label: Label
@export var painter: Painter

func _ready() -> void:

    painter.paint_color = Color.ORANGE
    color_picker.color = painter.paint_color

    color_picker.color_changed.connect(func(color: Color):
        painter.paint_color = color
    )

    ######

    painter.brush_size_px = 25
    size_slider.value = float(painter.brush_size_px)
    size_label.text = "%d px" % painter.brush_size_px

    size_slider.value_changed.connect(func(value: float): 
        painter.brush_size_px = int(value)
        size_label.text = "%d px" % int(value)
    )

    ######

    painter.brush_rotation = 0.0
    rot_slider.value = painter.brush_rotation
    rot_label.text = "%d deg" % rad_to_deg(painter.brush_rotation)

    rot_slider.value_changed.connect(func(value: float):
        painter.brush_rotation = value
        rot_label.text = "%d deg" % rad_to_deg(value)
    )


