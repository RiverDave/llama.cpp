// Tests for the suffix automaton. DO NOT MODIFY.
#include "sam.h"

#include <algorithm>
#include <cassert>
#include <iostream>
#include <random>
#include <set>
#include <string>

static long long distinct_brute(const std::string& s) {
    std::set<std::string> subs;
    for (size_t i = 0; i < s.size(); ++i)
        for (size_t j = i + 1; j <= s.size(); ++j)
            subs.insert(s.substr(i, j - i));
    return static_cast<long long>(subs.size());
}

static int lcs_brute(const std::string& a, const std::string& b) {
    int best = 0;
    for (size_t i = 0; i < a.size(); ++i)
        for (size_t j = i + 1; j <= a.size(); ++j)
            if (b.find(a.substr(i, j - i)) != std::string::npos)
                best = std::max(best, static_cast<int>(j - i));
    return best;
}

int main() {
    // Fixed known cases.
    {
        SuffixAutomaton sa;
        for (char c : std::string("banana")) sa.extend(c);
        assert(sa.distinct_substrings() == 15);
    }
    {
        SuffixAutomaton sa;
        for (char c : std::string("aaaa")) sa.extend(c);
        assert(sa.distinct_substrings() == 4);
    }
    {
        SuffixAutomaton sa;
        assert(sa.distinct_substrings() == 0);
    }

    std::mt19937 rng(20260814);
    auto rand_str = [&](int max_len) {
        int len = 1 + static_cast<int>(rng() % max_len);
        std::string s;
        s.reserve(len);
        for (int i = 0; i < len; ++i) s.push_back('a' + rng() % 3);
        return s;
    };

    // Distinct substrings vs brute force.
    for (int it = 0; it < 60; ++it) {
        std::string s = rand_str(30);
        SuffixAutomaton sa;
        for (char c : s) sa.extend(c);
        assert(sa.distinct_substrings() == distinct_brute(s));
    }

    // Longest common substring vs brute force.
    for (int it = 0; it < 60; ++it) {
        std::string a = rand_str(30);
        std::string b = rand_str(30);
        SuffixAutomaton sa;
        for (char c : a) sa.extend(c);
        assert(sa.longest_common_substring(b) == lcs_brute(a, b));
    }

    // clear() resets everything.
    {
        SuffixAutomaton sa;
        for (char c : std::string("banana")) sa.extend(c);
        sa.clear();
        assert(sa.distinct_substrings() == 0);
        for (char c : std::string("ab")) sa.extend(c);
        assert(sa.distinct_substrings() == 3);
    }

    std::cout << "ALL TESTS PASSED\n";
    return 0;
}
