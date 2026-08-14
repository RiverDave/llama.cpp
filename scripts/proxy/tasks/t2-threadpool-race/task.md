# Task: fix the data race in this C++ program

You are in a directory containing `main.cpp` and `verify.sh`.

`main.cpp` reduces the numbers 1..1000 across 8 worker threads, but the shared
queue and the running total are accessed with **no synchronization at all**.
The program is a data race (undefined behavior): it often prints the right
answer by luck, and sometimes a wrong one.

Fix `main.cpp` so that:

1. The program is **correct**: it prints `total=500500 expected=500500` and
   exits 0.
2. It is **race-free**: the verify script compiles with
   `clang++ -fsanitize=thread` and runs with `TSAN_OPTIONS=halt_on_error=1`,
   so any remaining data race aborts the run and fails the gate.

You may restructure the code freely (mutexes, atomics, `std::async`, a proper
thread pool, whatever you prefer), but the observable behavior must stay the
same: sum of 1..1000 printed as `total=<n> expected=500500`.

Do not modify `verify.sh`.

Toolchain note: Homebrew's `clang++` TSAN runtime segfaults on macOS
ARM64 (dyld `__guard_setup`). Use the system compiler for your own
iteration: `/usr/bin/clang++ -std=c++20 -O1 -g -fsanitize=thread
main.cpp -o /tmp/tp_test` (the gate already pins it).

**Definition of done**: `./verify.sh` exits 0. Use the shell to compile and
iterate (`/usr/bin/clang++ -std=c++20 -O1 -g -fsanitize=thread main.cpp
-o /tmp/tp_test` and run it yourself while developing).
