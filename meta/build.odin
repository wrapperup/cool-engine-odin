package meta

import "base:runtime"

import "core:fmt"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:os"
import "core:path/filepath"
import "core:reflect"
import "core:strings"
import "core:time"

supported_type_map := map[string]string {
	"f32" = "float",
	"f64" = "double",
	"i32" = "int",
	"u32" = "uint",
	"u8"  = "uint8_t",
}

collect_files :: proc(path: string) -> (ast_files: [dynamic]^ast.File, success: bool) {
	NO_POS :: tokenizer.Pos{}

	pkg_path, pkg_path_ok := filepath.abs(path)
	assert(pkg_path_ok)

	files: [dynamic]string
	fullpaths: [dynamic]string

	FileParseContext :: struct {
		files:     ^[dynamic]string,
		ast_files: ^[dynamic]^ast.File,
		fullpaths: ^[dynamic]string,
	}

	parse_ctx := FileParseContext {
		files     = &files,
		fullpaths = &fullpaths,
		ast_files = &ast_files,
	}

	filepath.walk(pkg_path, proc(info: os.File_Info, in_err: os.Error, user_data: rawptr) -> (err: os.Error, skip_dir: bool) {
			if (info.is_dir) do return

			assert(user_data != nil)

			ctx := cast(^FileParseContext)user_data

			fullpath := strings.clone(info.fullpath)
			src, ok := os.read_entire_file(fullpath)
			if !ok {
				delete(fullpath)
				fmt.eprintln("Couldn't read file:", fullpath)
				assert(false, "YAY")
			}

			if strings.trim_space(string(src)) == "" {
				delete(fullpath)
				delete(src)
				return
			}

			append(ctx.fullpaths, string(fullpath))
			append(ctx.files, string(src))
			return
		}, &parse_ctx)

	resize(&ast_files, len(files))

	parallel_for(len(files), proc(i: int, data: rawptr) {
			p := parser.default_parser()
			ctx := cast(^FileParseContext)data

			src_file := ctx.files[i]
			fullpath := ctx.fullpaths[i]

			file := ast.new(ast.File, NO_POS, NO_POS)
			file.src = string(src_file)
			file.fullpath = fullpath

			assert(parser.parse_file(&p, file))

			ctx.ast_files[i] = file
		}, &parse_ctx)

	success = true
	return
}

get_type_string :: proc(node: ^ast.Any_Node) -> (type_name: string, is_pointer: bool, is_array: bool, num_elems: u32, ok: bool) {
	#partial switch ty in node {
	case ^ast.Selector_Expr:
		type_name = ty.field.derived_expr.(^ast.Ident).name
	case ^ast.Ident:
		type_name = ty.name
	case ^ast.Call_Expr:
		is_pointer = true
		type_name, _, _, _, ok = get_type_string(&ty.args[0].derived)
	case:
		return
	}

	type_name = strings.trim_prefix(type_name, "GPU")

	ok = true

	return
}

main :: proc() {
	start_time := time.now()

	init_parallel_for_thread_pool(12)

	files, ok := collect_files("./src")
	assert(ok)

	generate_shader_bindings(files[:])

	fmt.println("Finished in", time.since(start_time))
}

generate_shader_bindings :: proc(files: []^ast.File) {
	// bind_structs: map[string]ShaderStruct
	bind_structs: [dynamic]ShaderStruct

	for file in files {
		for decl in file.decls {
			value, ok := decl.derived_stmt.(^ast.Value_Decl)
			if !ok do continue

			if len(value.values) != 1 do continue
			if len(value.attributes) <= 0 do continue

			str_type, vok := value.values[0].derived_expr.(^ast.Struct_Type)
			if !vok do continue

			found := false
			for attr in value.attributes {
				for elem in attr.elems {
					i, iok := elem.derived.(^ast.Ident)
					if iok && i.name == "ShaderShared" {
						found = true
					}
				}
			}

			if !found do continue

			ident, nok := value.names[0].derived.(^ast.Ident)
			if !nok do continue

			fmt.println("Bind shader struct for", ident.name)

			bind_struct := ShaderStruct {
				expr = str_type,
				name = ident.name,
			}

			append(&bind_structs, bind_struct)
		}
	}

	builder: strings.Builder
	strings.builder_init(&builder)

	for bind_struct in bind_structs {
		strings.write_string(&builder, "struct ")
		strings.write_string(&builder, strings.trim_prefix(bind_struct.name, "GPU"))
		if len(bind_struct.expr.fields.list) > 0 {
			strings.write_string(&builder, " {\n")

			for field in bind_struct.expr.fields.list {
				write_type: string

				field_type, is_pointer, is_array, num_elems, ty_ok := get_type_string(&field.type.derived)

				if !ty_ok {
					fmt.eprintln("Type in struct field is not supported:", field.type)
					continue
				}

				field_name := field.names[0].derived_expr.(^ast.Ident).name

				// Map type to an HLSL/Slang type
				new_field_type, ok := supported_type_map[field_type]
				if ok {
					field_type = new_field_type
				}

				if field_type == "vk.DeviceAddress" {
					field_type = field.tag.text

					if len(field_type) < 2 {
						fmt.eprintln("vk.DeviceAddress field is not tagged.")
						continue
					}

					field_type = field_type[1:len(field_type) - 1]
					is_pointer = true
				}

				strings.write_string(&builder, "  ")
				strings.write_string(&builder, field_type)
				strings.write_string(&builder, " ")
				if is_pointer do strings.write_string(&builder, "*")
				strings.write_string(&builder, field_name)
				strings.write_string(&builder, ";\n")
			}

			strings.write_string(&builder, "}")
		}
		strings.write_string(&builder, ";\n\n")
	}

	string := strings.to_string(builder)
	string = strings.trim(string, "\n")

	fmt.println(string)
	os.write_entire_file("shaders/gen/structs.slang", transmute([]byte)string)
}

ShaderStruct :: struct {
	expr: ^ast.Struct_Type,
	name: string,
}
