odin build src -out:build/release/main.exe -collection:deps=deps -ignore-unknown-attributes -o:aggressive -use-separate-modules -show-timings -lld
exit $LastExitCode
