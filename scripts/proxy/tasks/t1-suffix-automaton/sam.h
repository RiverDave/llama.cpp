#pragma once

#include <string>

// Suffix automaton: a minimal DFA accepting all substrings of a string.
// Alphabet: lowercase 'a'-'z'.
//
// Requirements (see task.md):
//   - extend() amortized O(1)
//   - distinct_substrings() correct for strings up to 30 chars
//   - longest_common_substring() O(|text|) per query
//
// Do NOT change this interface.
class SuffixAutomaton {
public:
    SuffixAutomaton();
    ~SuffixAutomaton();
    SuffixAutomaton(const SuffixAutomaton&) = delete;
    SuffixAutomaton& operator=(const SuffixAutomaton&) = delete;

    void extend(char c);                    // append one lowercase letter
    long long distinct_substrings() const;  // distinct substrings built so far
    int longest_common_substring(const std::string& text) const;
    void clear();
};
