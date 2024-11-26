package game

import "core:fmt"
import "core:os"
import "core:slice"
import "core:time"

import vk "vendor:vulkan"

import sp "deps:odin-slang/slang"

import "gfx"

ShaderCreatePipelineCallback :: #type proc(shader_module: vk.ShaderModule) -> (vk.Pipeline, bool)

Shader :: struct {
	pipeline:                 vk.Pipeline,
	path:                     cstring,
	entrypoints:              []cstring,
	last_write_time:          os.File_Time,
	pipeline_create_callback: ShaderCreatePipelineCallback,
}

init_shader :: proc(path: cstring, entrypoints: []cstring, pipeline_create_callback: ShaderCreatePipelineCallback) -> Shader {
	assert(os.exists(string(path)))

	last_write_time, err := os.last_write_time_by_name(string(path))
	assert(err == nil)

	shader := Shader {
		path                     = path,
		entrypoints              = slice.clone(entrypoints),
		last_write_time          = last_write_time,
		pipeline_create_callback = pipeline_create_callback,
	}

	// Load shader on demand.
	// TODO: Since this is at startup, we'll assert... for now
	assert(reload_shader_pipeline(&shader))

	return shader
}

reload_shader_pipeline :: proc(shader: ^Shader) -> bool {
	code := compile_slang_to_spirv(shader) or_return

	shader_module, f_ok := gfx.load_shader_module_from_bytes(code)
	assert(f_ok, "Failed to load shaders.")

	// TODO: Make this async? Currently not a bottleneck.
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

compile_slang_to_spirv :: proc(shader: ^Shader) -> (compiled_code: []u8, ok: bool) {
	start_compile_time := time.tick_now()

	using sp
	code, diagnostics: ^IBlob
	r: Result

	target_desc := TargetDesc {
		structureSize = size_of(TargetDesc),
		format        = .SPIRV,
		flags         = {.GENERATE_SPIRV_DIRECTLY},
		profile       = game.render_state.global_session->findProfile("sm_6_0"),
	}

	compiler_option_entries := [?]CompilerOptionEntry {
		{name = .VulkanUseEntryPointName, value = {kind = .Int, intValue0 = 1}},
		{name = .DisableWarning, value = {kind = .String, stringValue0 = "39001"}},
	}
	session_desc := SessionDesc {
		structureSize            = size_of(SessionDesc),
		targets                  = &target_desc,
		targetCount              = 1,
		defaultMatrixLayoutMode  = .COLUMN_MAJOR,
		compilerOptionEntries    = &compiler_option_entries[0],
		compilerOptionEntryCount = len(compiler_option_entries),
	}

	session: ^ISession
	slang_check(game.render_state.global_session->createSession(session_desc, &session))
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

	for entrypoint_name in shader.entrypoints {
		entrypoint: ^IEntryPoint
		module->findEntryPointByName(entrypoint_name, &entrypoint)

		if entrypoint == nil {
			fmt.println("Shader", shader.path, ": Entrypoint", entrypoint_name, "doesn't exist.")
			return
		}
	}

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
