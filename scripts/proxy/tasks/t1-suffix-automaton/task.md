# Task: implement a suffix automaton in C++

You are in a directory containing `sam.h`, `sam.cpp`, `test_sam.cpp`, and `verify.sh`.

Implement a **suffix automaton** (also called a DAWG) for lowercase ASCII strings:

- `SuffixAutomaton()` - default-construct an automaton for the empty string.
- `void extend(char c)` - append one lowercase letter to the built string.
- `long long distinct_substrings() const` - number of distinct substrings of the
  string built so far.
- `int longest_common_substring(const std::string& text) const` - length of the
  longest string that occurs both in `text` and in the string built so far.
- `void clear()` - reset to the empty string.

Requirements:

- Construction must be O(n) states and O(n) amortized transitions for `extend`.
- `distinct_substrings()` and `longest_common_substring()` must be correct for
  inputs up to 30 characters (the tests use brute force as the oracle).
- You may design the internal representation freely, but do not change the
  public interface in `sam.h`, and do not modify `test_sam.cpp` or `verify.sh`.

The test binary compiles `sam.cpp` with `test_sam.cpp` and asserts:

- fixed cases (`"banana"` -> 15 distinct substrings, `"aaaa"` -> 4, empty -> 0),
- 60 random strings checked against a brute-force distinct-substring count,
- 60 random string pairs checked against a brute-force longest-common-substring,
- `clear()` resets state.

**Definition of done**: `./verify.sh` exits 0 (it compiles with
`g++ -std=c++20 -O2 -Wall -Wextra` and runs the tests). Use the shell to
compile and iterate. Do not modify `verify.sh` or `test_sam.cpp`.
