#!/bin/bash
# Gate for the threadpool-race task. DO NOT MODIFY.
set -euo pipefail
clang++ -std=c++20 -O1 -g -fsanitize=thread main.cpp -o /tmp/tp_test
TSAN_OPTIONS="halt_on_error=1" /tmp/tp_test
echo "PASS"
