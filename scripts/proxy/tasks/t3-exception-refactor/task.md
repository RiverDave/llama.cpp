# Task: make this code exception-safe (RAII refactor)

You are in a directory containing `leak_count.h`, `leak_count.cpp`,
`main.cpp`, and `verify.sh`.

`main.cpp` contains a `ResourceManager` whose `run()` method allocates a
temporary scratch buffer with `new[]`. If the method throws mid-way (the
`throw_midway` flag), that scratch buffer **leaks** — it is a local
pointer, so the destructor cannot see it.

Refactor `ResourceManager` so it is exception-safe using RAII
(`std::unique_ptr`, `std::vector`, or similar). The rules:

1. Observable behavior must not change: the functional test asserts
   `checksum()` == 1498500 after `run(false)` with size 1000.
2. No leaks on any path: the tests track live allocations through the
   global `operator new`/`delete` (in `leak_count.cpp`) and fail if the
   exception path or the normal path leaves allocations alive.
3. Keep the public interface (`ResourceManager(size_t)`, `run(bool)`,
   `checksum()`, deleted copy) intact.

Do not modify `leak_count.h`, `leak_count.cpp`, or `verify.sh`.

**Definition of done**: `./verify.sh` exits 0 (compiles with
`g++ -std=c++20 -O2 -Wall -Wextra` and passes all three tests: functional
output, exception-path balance, normal-path balance).
