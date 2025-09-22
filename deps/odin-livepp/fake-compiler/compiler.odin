package compiler

import "core:os"
import "core:fmt"
import "core:os/os2"
import "core:strings"


main :: proc() {
    a, b, c, d := os2.process_exec({
        command = { "cmd.exe", "/c", "call", "build.bat" },
    }, allocator = context.temp_allocator)

    if len(os.args) == 2 && len(os.args[1]) > 1 {
        contents, ok := os.read_entire_file(os.args[1][1:]);
        if ok {
            content := cast(string)contents

            spl := strings.split(content, "\"")

            out_patch_filepath := spl[1]
            source_filepath := spl[3]
            in_obj_filepath := out_patch_filepath[:len(out_patch_filepath)-10]

            fmt.println("out:", out_patch_filepath, "src:", source_filepath, "in:", in_obj_filepath)

            fmt.println(cast(string)contents)

            os2.copy_file(out_patch_filepath, in_obj_filepath)
        }
    }
}
