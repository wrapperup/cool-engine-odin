package game

import "core:fmt"
import "core:os/os2"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:time"

import vk "vendor:vulkan"

import sp "deps:odin-slang/slang"

import "gfx"

ShaderCreatePipelineCallback :: #type proc(shader_module: vk.ShaderModule) -> (vk.Pipeline, bool)

Shader :: struct {
	pipeline:                 vk.Pipeline,
	path:                     cstring,
	extra_files:              []string,
	last_compile_time:        time.Time,
	needs_recompile:          bool,
	pipeline_create_callback: ShaderCreatePipelineCallback,
}

init_shader :: proc(path: cstring, pipeline_create_callback: ShaderCreatePipelineCallback) -> Shader {
	assert(os2.exists(string(path)))

	extra_files := get_dependency_file_paths(path)

	shader := Shader {
		path                     = path,
		extra_files              = extra_files,
		last_compile_time        = time.now(),
		pipeline_create_callback = pipeline_create_callback,
	}

	// Load shader on demand.
	// TODO: Since this is at startup, we'll assert... for now
	assert(reload_shader_pipeline(&shader))

	return shader
}

defer_destroy_shader :: proc(arena: ^gfx.VulkanArena, shader: Shader) {
	gfx.defer_destroy(arena, shader.pipeline)
}

get_cached_shader_path :: proc(path: string) -> string {
	return filepath.join({"shaders", ".cache", filepath.base(path)})
}

get_last_write_time :: proc(shader: ^Shader) -> time.Time {
	max_last_write_time: i64
	last_write_time, ok := os2.last_write_time_by_name(string(shader.path))
	max_last_write_time = last_write_time._nsec

	for path in shader.extra_files {
		last, k := os2.last_write_time_by_name(string(path))
		if last._nsec > max_last_write_time {
			max_last_write_time = last._nsec
		}
	}

	return time.Time{max_last_write_time}
}

reload_shader_pipeline :: proc(shader: ^Shader) -> bool {
	cached_path := get_cached_shader_path(string(shader.path))

	use_cached_spirv := false

	if os2.exists(cached_path) {
		shader_last_time := get_last_write_time(shader)
		cache_time, time_ok := os2.last_write_time_by_name(cached_path)
		assert(time_ok == nil, "This shouldn't be hit...?")

		if shader_last_time._nsec < cache_time._nsec {
			use_cached_spirv = true
		}
	}

	code: []u8

	if use_cached_spirv {
		spirv_code, err := os2.read_entire_file_from_path(string(cached_path), context.allocator)
		if err != nil {
			return false
		}

		code = spirv_code
	} else {
		code = compile_slang_to_spirv(shader) or_return
		err := os2.write_entire_file(string(cached_path), code)
		if err != nil {
			fmt.println("Warning: Shader couldn't be cached.", err, cached_path)
		}
	}

	shader_module, f_ok := gfx.load_shader_module_from_bytes(code)
	assert(f_ok, "Failed to load shaders.")

	pipeline := shader.pipeline_create_callback(shader_module) or_return

	if shader.pipeline != 0 {
		vk.DestroyPipeline(gfx.renderer().device, shader.pipeline, nil)
	}

	shader.pipeline = pipeline

	gfx.destroy_shader_module(shader_module)

	return true
}

slang_check :: #force_inline proc(#any_int result: int, loc := #caller_location) {
	result := -sp.Result(result)
	if sp.FAILED(result) {
		code := sp.GET_RESULT_CODE(result)
		facility := sp.GET_RESULT_FACILITY(result)
		estr: string
		switch sp.Result(result) {
		case:
			estr = "Unknown error"
		case sp.E_NOT_IMPLEMENTED():
			estr = "E_NOT_IMPLEMENTED"
		case sp.E_NO_INTERFACE():
			estr = "E_NO_INTERFACE"
		case sp.E_ABORT():
			estr = "E_ABORT"
		case sp.E_INVALID_HANDLE():
			estr = "E_INVALID_HANDLE"
		case sp.E_INVALID_ARG():
			estr = "E_INVALID_ARG"
		case sp.E_OUT_OF_MEMORY():
			estr = "E_OUT_OF_MEMORY"
		case sp.E_BUFFER_TOO_SMALL():
			estr = "E_BUFFER_TOO_SMALL"
		case sp.E_UNINITIALIZED():
			estr = "E_UNINITIALIZED"
		case sp.E_PENDING():
			estr = "E_PENDING"
		case sp.E_CANNOT_OPEN():
			estr = "E_CANNOT_OPEN"
		case sp.E_NOT_FOUND():
			estr = "E_NOT_FOUND"
		case sp.E_INTERNAL_FAIL():
			estr = "E_INTERNAL_FAIL"
		case sp.E_NOT_AVAILABLE():
			estr = "E_NOT_AVAILABLE"
		case sp.E_TIME_OUT():
			estr = "E_TIME_OUT"
		}

		fmt.panicf("Failed with error: %v (%v) Facility: %v", estr, code, facility, loc = loc)
	}
}

diagnostics_check :: #force_inline proc(diagnostics: ^sp.IBlob, loc := #caller_location) {
	if diagnostics != nil {
		buffer := slice.bytes_from_ptr(diagnostics->getBufferPointer(), int(diagnostics->getBufferSize()))
		fmt.eprintln(false, string(buffer), loc)
	}
}

init_slang_session :: proc() -> ^sp.ISession {
	using sp


	target_options := [?]CompilerOptionEntry{{name = .GLSLForceScalarLayout, value = {kind = .Int, intValue0 = 1}}}
	target_desc := TargetDesc {
		structureSize            = size_of(TargetDesc),
		format                   = .SPIRV,
		flags                    = {.GENERATE_SPIRV_DIRECTLY},
		profile                  = game.render_state.global_session->findProfile("sm_6_0"),
		forceGLSLScalarBufferLayout = true,
		compilerOptionEntries    = &target_options[0],
		compilerOptionEntryCount = len(target_options),
	}

	session_options := [?]CompilerOptionEntry {
		{name = .VulkanUseEntryPointName, value = {kind = .Int, intValue0 = 1}},
		{name = .GLSLForceScalarLayout, value = {kind = .Int, intValue0 = 1}},
		{name = .DisableWarning, value = {kind = .String, stringValue0 = "39001"}},
	}
	session_desc := SessionDesc {
		structureSize            = size_of(SessionDesc),
		targets                  = &target_desc,
		targetCount              = 1,
		defaultMatrixLayoutMode  = .COLUMN_MAJOR,
		compilerOptionEntries    = &session_options[0],
		compilerOptionEntryCount = len(session_options),
	}
	session: ^ISession
	slang_check(game.render_state.global_session->createSession(session_desc, &session))
	return session
}

get_dependency_file_paths :: proc(root_path: cstring, allocator := context.allocator) -> []string {
	using sp

	session := init_slang_session()
	defer session->release()

	diagnostics: ^IBlob
	module: ^IModule = session->loadModule(root_path, &diagnostics)
	diagnostics_check(diagnostics)
	assert(module != nil)
	defer module->release()

	count := module->getDependencyFileCount()

	file_paths := make([]string, count)

	for i in 0 ..< module->getDependencyFileCount() {
		str := module->getDependencyFilePath(i)
		file_paths[i] = strings.clone_from_cstring(str)
	}

	return file_paths
}

compile_slang_to_spirv :: proc(shader: ^Shader) -> (compiled_code: []u8, ok: bool) {
	start_compile_time := time.tick_now()

	using sp
	code, diagnostics: ^IBlob
	r: Result

	session := init_slang_session()
	defer session->release()

	blob: ^IBlob

	module: ^IModule = session->loadModule(shader.path, &diagnostics)
	diagnostics_check(diagnostics)
	if module == nil {
		fmt.println("Shader", shader.path, "doesn't exist.")
		return
	}
	defer module->release()

	components: [dynamic]^IComponentType = {module}
	defer delete(components)

	linked_program: ^IComponentType
	r = session->createCompositeComponentType(&components[0], len(components), &linked_program, &diagnostics)
	diagnostics_check(diagnostics)
	slang_check(r)

	target_code: ^IBlob
	r = linked_program->getTargetCode(0, &target_code, &diagnostics)
	diagnostics_check(diagnostics)
	slang_check(r)

	code_size := target_code->getBufferSize()
	source_code := slice.bytes_from_ptr(target_code->getBufferPointer(), auto_cast code_size)

	assert(code_size % 4 == 0)

	compiled_code = slice.clone(source_code)
	ok = true

	return
}
