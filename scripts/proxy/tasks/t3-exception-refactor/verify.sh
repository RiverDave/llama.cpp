#!/bin/bash
# Gate for the exception-refactor task. DO NOT MODIFY.
set -euo pipefail
g++ -std=c++20 -O2 -Wall -Wextra leak_count.cpp main.cpp -o /tmp/rm_test
/tmp/rm_test
echo "PASS"
