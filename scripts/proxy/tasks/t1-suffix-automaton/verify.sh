#!/bin/bash
# Gate for the suffix-automaton task. DO NOT MODIFY.
set -euo pipefail
g++ -std=c++20 -O2 -Wall -Wextra -I. sam.cpp test_sam.cpp -o /tmp/sam_test
/tmp/sam_test
echo "PASS"
