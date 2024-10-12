odin build src -out:build/debug/main.exe -collection:deps=deps -ignore-unknown-attributes -debug -o:none -use-separate-modules -show-timings
exit $LastExitCode
