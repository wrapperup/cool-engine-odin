package game

import "gfx"

GPU_Point_Light :: struct {
	color:     Vec3,
	radius:    f32,
	world_pos: Vec3,
	lumens:    f32,
}

Point_Light :: struct {
	using entity: ^Entity,
	color:        Vec3,
	radius:       f32,
	lumens:       f32,
}

point_light_to_gpu :: proc(light: Point_Light) -> GPU_Point_Light {
    // odinfmt: disable
	return GPU_Point_Light{
        color = light.color,
        radius = light.radius,
        world_pos = light.translation,
        lumens = light.lumens
    }
    // odinfmt: enable
}

init_point_light :: proc(light: ^Point_Light, position: Vec3, color: Vec3, radius: f32, lumens: f32) {
    light.translation = position
    light.color = color
    light.radius = radius
    light.lumens = lumens
}
