#include "sam.h"

// TODO(you): implement the suffix automaton.
//
// Skeleton to get you started:
//
//   struct State {
//       int len;            // longest string in this equivalence class
//       int link;           // suffix link
//       int next[26];       // transitions (-1 = none)
//   };
//
//   extend(c): standard SAM construction with a cloned state on split.
//   distinct_substrings(): sum over states of (len - len(link)).
//   longest_common_substring(text): walk the automaton with `text`,
//       tracking current length and resetting via suffix links.
//   clear(): drop all states except the root.
//
// Note: the class has no data members, so keep per-instance state in an
// external registry keyed by `this` (e.g. a static map), and make sure a
// destroyed instance cleans up after itself (the destructor is declared
// in sam.h precisely so you can).

SuffixAutomaton::SuffixAutomaton() = default;

SuffixAutomaton::~SuffixAutomaton() = default;

void SuffixAutomaton::extend(char) {
    // TODO
}

long long SuffixAutomaton::distinct_substrings() const {
    return 0;  // TODO
}

int SuffixAutomaton::longest_common_substring(const std::string&) const {
    return 0;  // TODO
}

void SuffixAutomaton::clear() {
    // TODO
}
