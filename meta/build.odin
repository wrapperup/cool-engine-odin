package meta

import "core:fmt"
import "core:odin/ast"
import "core:odin/parser"

main :: proc() {
	pkg, ok := parser.collect_package("./src")
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
}

ShaderStruct :: struct {
	expr: ^ast.Struct_Type,
	name: string,
}
