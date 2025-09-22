package game

import "base:intrinsics"

import "core:fmt"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:os"
import "core:os/os2"
import "core:path/filepath"
import "core:strings"
import "core:time"

Type_Mapping :: struct {
    from: string,
    to: string,
}

type_map := []Type_Mapping {
    // { "f32", "float" },
    // { "f64", "double" },
    // { "i32", "int" },
    // { "u32", "uint" },
    // { "u8" , "uint8_t" },
}

templated_type_map := []string {
    "Image1D_",
    "Image2D_",
    "Image3D_",
    "ImageCube_",

    "Image1DArray_",
    "Image2DArray_",
    "Image3DArray_",
    "ImageCubeArray_",

    "RWImage1D_",
    "RWImage2D_",
    "RWImage3D_",
}

banned_types := []Type_Mapping {
    { "ImageId", "Tag the struct with an `Image*` type." },
    { "SamplerId", "Tag the struct with `Sampler` or `SamplerComparison`." },
}

error_reported := false

report_error :: proc(message: string, node: ^ast.Node, file: ^ast.File, suggestion := "") {
    error_reported = true

    fmt.eprintln("\x1b[1m", node.pos.file, "(", node.pos.line, ":", node.pos.column, ")\x1b[22m \x1b[31mError:\x1b[0m ", message, sep = "")

    fmt.eprint("        ")
    file_src := file.src
    i := 0
    for line in strings.split_lines_iterator(&file_src) {
        if i == node.pos.line-1 {
            fmt.eprintln(strings.trim_space(line))
            break
        }
        i += 1
    }

    fmt.eprint("        ")
    for i in 2..<node.pos.column {
        fmt.eprint(" ")
    }
    fmt.eprint("^")
    if node.end.column != node.pos.column {
        for i in 2..<(node.end.column - node.pos.column) {
            fmt.eprint("~")
        }
        fmt.eprint("^")
    }
    fmt.eprintln("")
    if suggestion != "" {
        fmt.eprint("        ")
        fmt.eprintln("Suggestion:", suggestion)
    }
}

map_type_to_slang :: proc(ty: string, node: ^ast.Node, file: ^ast.File) -> string {
    for mapping in type_map {
        if mapping.from == ty {
            return mapping.to
        }
    }

    for name in templated_type_map {
        if strings.starts_with(ty, name) {
            start := name[:len(name)-1]
            rest := ty[len(name):]
            return fmt.tprint(start, "<", rest, ">", sep = "");
        }
    }

    return strip_gpu_name(ty);
}

strip_gpu_name :: proc(s: string) -> string {
    if s == "GPUPtr" {
        return s;
    }

    if strings.has_prefix(s, "GPU_") {
        return s[4:]
    } else if strings.has_prefix(s, "GPU") {
        return s[3:]
    }

    return s;
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

            base := filepath.base(fullpath)
            if base == "generated.odin" {
                return
            }

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

    p := parser.default_parser()

    for i in 0..<len(files) {
        src_file := files[i]
        fullpath := fullpaths[i]

        file := ast.new(ast.File, NO_POS, NO_POS)
        file.src = string(src_file)
        file.fullpath = fullpath

        assert(parser.parse_file(&p, file))

        ast_files[i] = file
    }

	success = true
	return
}

get_type_string :: proc(expr: ^ast.Expr, file: ^ast.File) -> (type_name: string, array_name: string) {
    builder: strings.Builder
    arr_builder: strings.Builder

    node := expr.derived

	#partial switch ty in node {
	case ^ast.Selector_Expr:
        return get_type_string(ty.field, file)
	case ^ast.Ident:
        return map_type_to_slang(ty.name, &ty.node, file), ""
	case ^ast.Call_Expr:
        if len(ty.args) == 1 {
            ptr_name: string
            ptr_name, _ = get_type_string(ty.expr, file)

            if ptr_name == "GPUPtr" {
                inner_name: string
                inner_name, array_name = get_type_string(ty.args[0], file)
                fmt.sbprint(&builder, inner_name, "*", sep="")
                break;
            }
        }
    case ^ast.Array_Type:
        assert(ty.len != nil, "Arrays must be fixed length.")

        lit, ok := ty.len.derived_expr.(^ast.Basic_Lit)
        assert(ok, "Array length must be positive.")
        
        len_string := lit.tok.text

        inner_type_name, inner_array_name := get_type_string(ty.elem, file)
        fmt.sbprint(&builder, inner_type_name)
        fmt.sbprint(&arr_builder, inner_array_name, "[", len_string, "]", sep="")
	case:
		assert(false, "Type is not supported.")
	}

	return strings.to_string(builder), strings.to_string(arr_builder)
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
					if iok && i.name == "shader_shared" {
						found = true
					}
				}
			}

			if !found do continue

			ident, nok := value.names[0].derived.(^ast.Ident)
			if !nok do continue

			// fmt.println("Bind shader struct for", ident.name)

			bind_struct := ShaderStruct {
				expr = str_type,
				name = ident.name,
                src_file = file,
			}

			append(&bind_structs, bind_struct)
		}
	}

	builder: strings.Builder
	strings.builder_init(&builder)

	for bind_struct in bind_structs {
		strings.write_string(&builder, "struct ")
		strings.write_string(&builder, strip_gpu_name(bind_struct.name))
		if len(bind_struct.expr.fields.list) > 0 {
			strings.write_string(&builder, " {\n")

			for field in bind_struct.expr.fields.list {
				field_type, array_decl: string
                if field.tag.text != "" {
                    field_type = field.tag.text[1:len(field.tag.text)-1]
                } else {
                    field_type, array_decl = get_type_string(field.type, bind_struct.src_file)
                }

                for name in banned_types {
                    if name.from == field_type {
                        report_error("Type is not allowed in a shader struct.", &field.type.expr_base, bind_struct.src_file, name.to)
                    }
                }

				field_name := field.names[0].derived_expr.(^ast.Ident).name

				strings.write_string(&builder, "  ")
				strings.write_string(&builder, field_type)
				strings.write_string(&builder, " ")
				strings.write_string(&builder, field_name)
                if len(array_decl) > 0 {
                    strings.write_string(&builder, array_decl)
                }
				strings.write_string(&builder, ";\n")
			}

			strings.write_string(&builder, "}")
		}
		strings.write_string(&builder, ";\n\n")
	}

	str := strings.to_string(builder)
	str = strings.trim(str, "\n")

    if !error_reported {
        err_wef := os2.write_entire_file("shaders/generated.slang", transmute([]u8)str)
        assert(err_wef == nil)
    }
}

ShaderStruct :: struct {
	expr: ^ast.Struct_Type,
	name: string,
    src_file: ^ast.File,
}

main_meta :: proc() {
	start_time := time.now()

	files, ok := collect_files("./src")
	assert(ok)

	generate_shader_bindings(files[:])
    generate_assets()

	fmt.println("Parsed and generated code in", time.since(start_time))
}

generate_assets :: proc() {
    b: strings.Builder

    asset_files: [dynamic]os.File_Info

	filepath.walk("assets", proc(info: os.File_Info, in_err: os.Error, user_data: rawptr) -> (err: os.Error, skip_dir: bool) { 
        if !info.is_dir {
            asset_files := cast(^[dynamic]os.File_Info)user_data
            append(asset_files, info);
        }

        return
    }, &asset_files)

    working_directory, err_wd := os2.get_working_directory(context.temp_allocator)
    assert(err_wd == nil, "Can't get working directory")

    bpln :: fmt.sbprintln

    bpln(&b, "package game")
    bpln(&b, "")
    bpln(&b, "// Assets")
    bpln(&b, "Asset_Name :: enum {")
    for file in asset_files {
        stem := filepath.stem(file.name)
        bpln(&b, "    ", stem, ",", sep = "")
    }
    bpln(&b, "}")
    bpln(&b, "")
    bpln(&b, "asset_map: [Asset_Name]Asset")
    bpln(&b, "")
    bpln(&b, "load_generated_assets :: proc() -> bool {")
    for file in asset_files {
        base := filepath.stem(file.name)
        rel_path, k := filepath.rel(working_directory, file.fullpath)
        fixed_path, ok := strings.replace_all(rel_path, "\\", "/")
        assert(ok)

        assert(k == nil, "Couldn't get relative path")
        bpln(&b, "    asset_map[.", base, "] = load_asset(\"", fixed_path, "\") or_return", sep = "")
    }
    bpln(&b, "    return true")
    bpln(&b, "}")

    if !error_reported {
        err_wef := os2.write_entire_file("src/generated.odin", transmute([]u8)strings.to_string(b))
        assert(err_wef == nil, "Couldn't write generated.odin")
    }
}
