#include "sam.h"

#include <algorithm>
#include <map>
#include <vector>

namespace {

struct State {
    int len = 0;
    int link = -1;
    int next[26];
    State() { std::fill(std::begin(next), std::end(next), -1); }
};

struct Data {
    std::vector<State> st{1};  // root at index 0
    int last = 0;
};

std::map<const SuffixAutomaton*, Data>& pool() {
    static std::map<const SuffixAutomaton*, Data> m;
    return m;
}

}  // namespace

SuffixAutomaton::SuffixAutomaton() { pool()[this]; }

SuffixAutomaton::~SuffixAutomaton() { pool().erase(this); }

void SuffixAutomaton::extend(char c) {
    Data& d = pool()[this];
    int cur = static_cast<int>(d.st.size());
    d.st.emplace_back();
    d.st[cur].len = d.st[d.last].len + 1;
    int p = d.last;
    int cc = c - 'a';
    while (p != -1 && d.st[p].next[cc] == -1) {
        d.st[p].next[cc] = cur;
        p = d.st[p].link;
    }
    if (p == -1) {
        d.st[cur].link = 0;
    } else {
        int q = d.st[p].next[cc];
        if (d.st[p].len + 1 == d.st[q].len) {
            d.st[cur].link = q;
        } else {
            int clone = static_cast<int>(d.st.size());
            d.st.push_back(d.st[q]);
            d.st[clone].len = d.st[p].len + 1;
            while (p != -1 && d.st[p].next[cc] == q) {
                d.st[p].next[cc] = clone;
                p = d.st[p].link;
            }
            d.st[q].link = d.st[cur].link = clone;
        }
    }
    d.last = cur;
}

long long SuffixAutomaton::distinct_substrings() const {
    const Data& d = pool()[this];
    long long total = 0;
    for (size_t i = 1; i < d.st.size(); ++i) {
        total += d.st[i].len - d.st[d.st[i].link].len;
    }
    return total;
}

int SuffixAutomaton::longest_common_substring(const std::string& text) const {
    const Data& d = pool()[this];
    int v = 0, l = 0, best = 0;
    for (char ch : text) {
        int cc = ch - 'a';
        while (v != 0 && d.st[v].next[cc] == -1) {
            v = d.st[v].link;
            l = d.st[v].len;
        }
        if (d.st[v].next[cc] != -1) {
            v = d.st[v].next[cc];
            ++l;
        }
        best = std::max(best, l);
    }
    return best;
}

void SuffixAutomaton::clear() { pool()[this] = Data{}; }
