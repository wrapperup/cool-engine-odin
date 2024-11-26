odin build src -build-mode:dll -out:build/debug/game.dll -collection:deps=deps -ignore-unknown-attributes -debug -o:none -use-separate-modules -show-timings -linker:lld
exit $LastExitCode
