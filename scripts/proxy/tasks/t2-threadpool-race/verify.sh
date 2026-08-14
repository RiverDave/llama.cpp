#!/bin/bash
# Gate for the threadpool-race task. DO NOT MODIFY.
set -euo pipefail
# NOTE: Homebrew clang 20's TSAN runtime segfaults on macOS ARM64
# (crashes in dyld __guard_setup). System Apple clang works. Pin it.
CLANGXX="/usr/bin/clang++"
"$CLANGXX" -std=c++20 -O1 -g -fsanitize=thread main.cpp -o /tmp/tp_test
TSAN_OPTIONS="halt_on_error=1" /tmp/tp_test
echo "PASS"
