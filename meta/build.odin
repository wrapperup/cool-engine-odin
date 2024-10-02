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

supported_type_map := map[string]string {
	"f32" = "float",
	"f64" = "double",
	"i32" = "int",
	"u32" = "uint",
}

collect_package_ex :: proc(path: string) -> (pkg: ^ast.Package, success: bool) {
	NO_POS :: tokenizer.Pos{}

	pkg_path, pkg_path_ok := filepath.abs(path)
	if !pkg_path_ok {
		return
	}

	path_pattern := fmt.tprintf("%s/**.odin", pkg_path)
	matches, err := filepath.glob(path_pattern)
	defer delete(matches)

	if err != nil {
		return
	}

	pkg = ast.new(ast.Package, NO_POS, NO_POS)
	pkg.fullpath = pkg_path

	for match in matches {
		src: []byte
		fullpath, ok := filepath.abs(match)
		if !ok {
			return
		}

		src, ok = os.read_entire_file(fullpath)
		if !ok {
			delete(fullpath)
			return
		}
		if strings.trim_space(string(src)) == "" {
			delete(fullpath)
			delete(src)
			continue
		}

		file := ast.new(ast.File, NO_POS, NO_POS)
		file.pkg = pkg
		file.src = string(src)
		file.fullpath = fullpath
		pkg.files[fullpath] = file
	}

	success = true
	return
}

get_type_string :: proc(node: ^ast.Any_Node) -> (type_name: string, is_pointer: bool) {
	#partial switch ty in node {
	case ^ast.Selector_Expr:
		type_name = ty.field.derived_expr.(^ast.Ident).name
	case ^ast.Ident:
		type_name = ty.name
	case ^ast.Call_Expr:
		is_pointer = true
		type_name, _ = get_type_string(&ty.args[0].derived)
	}

	type_name = strings.trim_prefix(type_name, "GPU")

	return
}

main :: proc() {
	pkg, ok := collect_package_ex("./src")
	assert(ok)

	ok = parser.parse_package(pkg)
	assert(ok)

	// bind_structs: map[string]ShaderStruct
	bind_structs: [dynamic]ShaderStruct

	for key, val in pkg.files {
		for decl in val.decls {
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

				field_type, is_pointer := get_type_string(&field.type.derived)
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
