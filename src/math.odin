package game

// f32
Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32

Mat4x4 :: matrix[4, 4]f32
Mat4x3 :: matrix[4, 3]f32
Mat4x2 :: matrix[4, 2]f32

Mat3x4 :: matrix[3, 4]f32
Mat3x3 :: matrix[3, 3]f32
Mat3x2 :: matrix[3, 2]f32

Mat2x4 :: matrix[2, 4]f32
Mat2x3 :: matrix[2, 3]f32
Mat2x2 :: matrix[2, 2]f32

Quat :: quaternion128

// f64
DVec2 :: [2]f64
DVec3 :: [3]f64
DVec4 :: [4]f64

DMat4x4 :: matrix[4, 4]f64
DMat4x3 :: matrix[4, 3]f64
DMat4x2 :: matrix[4, 2]f64

DMat3x4 :: matrix[3, 4]f64
DMat3x3 :: matrix[3, 3]f64
DMat3x2 :: matrix[3, 2]f64

DMat2x4 :: matrix[2, 4]f64
DMat2x3 :: matrix[2, 3]f64
DMat2x2 :: matrix[2, 2]f64

DQuat :: quaternion256

// i32
IVec2 :: [2]i32
IVec3 :: [3]i32
IVec4 :: [4]i32

IMat4x4 :: matrix[4, 4]i32
IMat4x3 :: matrix[4, 3]i32
IMat4x2 :: matrix[4, 2]i32

IMat3x4 :: matrix[3, 4]i32
IMat3x3 :: matrix[3, 3]i32
IMat3x2 :: matrix[3, 2]i32

IMat2x4 :: matrix[2, 4]i32
IMat2x3 :: matrix[2, 3]i32
IMat2x2 :: matrix[2, 2]i32

// u32
UVec2 :: [2]u32
UVec3 :: [3]u32
UVec4 :: [4]u32

UMat4x4 :: matrix[4, 4]u32
UMat4x3 :: matrix[4, 3]u32
UMat4x2 :: matrix[4, 2]u32

UMat3x4 :: matrix[3, 4]u32
UMat3x3 :: matrix[3, 3]u32
UMat3x2 :: matrix[3, 2]u32

UMat2x4 :: matrix[2, 4]u32
UMat2x3 :: matrix[2, 3]u32
UMat2x2 :: matrix[2, 2]u32

Aabb :: struct {
	min: Vec3,
	max: Vec3,
}

aabb_center :: proc(box: Aabb) -> Vec3 {
	offset := (box.max - box.min) / 2.0
	return box.min + offset
}

debug_draw_aabb :: proc(box: Aabb) {
	offset := box.max - box.min

	debug_draw_dot(box.min)

	debug_draw_dot(box.min + {offset.x, 0, 0})
	debug_draw_dot(box.min + {0, offset.y, 0})
	debug_draw_dot(box.min + {0, 0, offset.z})

	debug_draw_dot(box.min + {offset.x, offset.y, 0})
	debug_draw_dot(box.min + {0, offset.y, offset.z})
	debug_draw_dot(box.min + {offset.x, 0, offset.z})

	debug_draw_dot(box.max)
}
