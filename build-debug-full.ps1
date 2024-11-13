odin build main_release -out:build/debug/main-full.exe -collection:deps=deps -ignore-unknown-attributes -debug -o:none -use-separate-modules -show-timings -lld
exit $LastExitCode
