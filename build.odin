package build

import "core:fmt"
import "core:odin/parser"
import "core:odin/ast"

main :: proc() {
    pkg, ok := parser.collect_package("./main")
    assert(ok)

    ok = parser.parse_package(pkg)
    assert(ok)

    for key, val in pkg.files {
        fmt.printf("a:", val.decls)
    }
}
