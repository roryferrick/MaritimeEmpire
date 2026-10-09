#!/bin/sh
# Builds the native library (see README.md): the editor's (template_debug) and
# the exported game's (template_release). From Git Bash on Windows.
cd "$(dirname "$0")"
export PATH="/c/Program Files/CMake/bin:$PATH"
export MSYS_NO_PATHCONV=1  # (Leave MSBuild's /m:1 alone.)
for dir in build build-release; do
	cmake -S . -B "$dir" > /dev/null 2>&1  # (Picks up new source files.)
	cmake --build "$dir" --config Release --target maritime_native -- /m:1 /p:CL_MPCount=4 2>&1 | grep -E "error C|error LNK|maritime_native.vcxproj ->|^.*: error" || exit 1
done
