odin build src -out:build/release/main.exe -collection:deps=deps -ignore-unknown-attributes -o:aggressive -no-bounds-check
exit $LastExitCode
