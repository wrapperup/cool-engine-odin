import bindless;
import types;

struct Vertex {
  Vec3 position;
  f32 uv_x;
  Vec3 normal;
  f32 uv_y;
  Vec4 color;
  Vec4 tangent;
};

struct PointLight {
	Vec3 color;
	f32 radius;
  Vec3 world_pos;
	f32 lumens;
}

struct ShCoefficients {
  Vec4 coeffs[9];
}

struct ShCoefficientVolume {
  u32 sh_0_3_id;
  u32 sh_4_7_id;
  u32 sh_8_9_id;
}

struct Environment {
	ShCoefficients *sh_volume;
  PointLight *point_lights;
  u32 num_point_lights;
}

struct GlobalData {
  Mat4x4 view_projection_matrix;
  Mat4x4 view_projection_i_matrix;
  Mat4x4 sun_view_projection_matrix;
  Mat4x4 sun_view_projection_i_matrix;
  Vec3 sun_color;
  f32 bias;
  Vec3 sky_color;
  f32 pad_0;
  Vec3 camera_pos;
  f32 pad_1;
  Vec3 sun_pos;
  f32 pad_2;
	Environment environment;
};

struct PBRMaterial {
  Tex2D base_color_id;
  Tex2D normal_map_id;
  Tex2D ao_roughness_metallic;
}

Vec3 srgb_to_linear(Vec3 color) {
  return pow(color, 2.2);
}

Vec3 linear_to_srgb(Vec3 color) {
  return pow(color, 1.0 / 2.2);
}

// General inner products

// scalar-vector and vector-scalar
__generic<T : __BuiltinArithmeticType, let N : int>
vector<T, N> operator*(vector<T, N> x, T y) {
  return mul(x, y);
}

__generic<T : __BuiltinArithmeticType, let N : int>
vector<T, N> operator*(T x, vector<T, N> y) {
  return mul(x, y);
}

// scalar-matrix and matrix-scalar
__generic<T : __BuiltinArithmeticType, let N : int, let M :int>
matrix<T, N, M> operator*(matrix<T, N, M> x, T y) {
  return mul(x, y);
}

__generic<T : __BuiltinArithmeticType, let N : int, let M :int>
matrix<T, N, M> operator*(T x, matrix<T, N, M> y) {
  return mul(x, y);
}

// vector-vector (dot product)
/// @category math
__generic<T : __BuiltinFloatingPointType, let N : int>
T operator*(vector<T, N> x, vector<T, N> y) {
  return mul(x, y);
}

__generic<T : __BuiltinIntegerType, let N : int>
T operator*(vector<T, N> x, vector<T, N> y) {
  return mul(x, y);
}

// vector-matrix
__generic<T : __BuiltinFloatingPointType, let N : int, let M : int>
vector<T, M> operator*(vector<T, N> left, matrix<T, N, M> right) {
  return mul(left, right);
}

__generic<T : __BuiltinIntegerType, let N : int, let M : int>
vector<T, M> operator*(vector<T, N> left, matrix<T, N, M> right) {
  return mul(left, right);
}

__generic<T : __BuiltinLogicalType, let N : int, let M : int>
vector<T, M> operator*(vector<T, N> left, matrix<T, N, M> right) {
  return mul(left, right);
}

// matrix-vector
__generic<T : __BuiltinFloatingPointType, let N : int, let M : int>
vector<T,N> operator*(matrix<T,N,M> left, vector<T,M> right) {
  return mul(left, right);
}
__generic<T : __BuiltinIntegerType, let N : int, let M : int>
vector<T,N> operator*(matrix<T,N,M> left, vector<T,M> right) {
  return mul(left, right);
}
__generic<T : __BuiltinLogicalType, let N : int, let M : int>
[OverloadRank(-1)]
vector<T,N> operator*(matrix<T,N,M> left, vector<T,M> right) {
  return mul(left, right);
}

// matrix-matrix
__generic<T : __BuiltinFloatingPointType, let R : int, let N : int, let C : int>
matrix<T,R,C> operator*(matrix<T,R,N> left, matrix<T,N,C> right) {
    return mul(left, right);
}
__generic<T : __BuiltinIntegerType, let R : int, let N : int, let C : int>
matrix<T,R,C> operator*(matrix<T,R,N> left, matrix<T,N,C> right) {
  return mul(left, right);
}
__generic<T : __BuiltinLogicalType, let R : int, let N : int, let C : int>
matrix<T,R,C> operator*(matrix<T,R,N> left, matrix<T,N,C> right) {
  return mul(left, right);
}

