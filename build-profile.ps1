odin build src -out:build/debug/main.exe -collection:deps=deps -ignore-unknown-attributes -use-separate-modules -debug -o:aggressive -show-timings
exit $LastExitCode
