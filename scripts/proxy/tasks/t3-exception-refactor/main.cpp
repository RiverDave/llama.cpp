#include "leak_count.h"

#include <iostream>
#include <stdexcept>

// ResourceManager owns two buffers. It is NOT exception-safe:
// run() allocates a scratch buffer with new[] and throws while the
// scratch is still owned. The scratch is a LOCAL pointer, so the
// destructor cannot free it on unwinding -> it leaks.
//
// Refactor to RAII so no path leaks (see task.md).
class ResourceManager {
public:
    explicit ResourceManager(std::size_t n);
    ~ResourceManager();
    ResourceManager(const ResourceManager&) = delete;
    ResourceManager& operator=(const ResourceManager&) = delete;

    void run(bool throw_midway);   // may throw std::runtime_error
    long long checksum() const;

private:
    int* buf_a_ = nullptr;
    int* buf_b_ = nullptr;
    std::size_t n_ = 0;
};

ResourceManager::ResourceManager(std::size_t n) : n_(n) {}

ResourceManager::~ResourceManager() {
    delete[] buf_a_;
    delete[] buf_b_;
}

void ResourceManager::run(bool throw_midway) {
    buf_a_ = new int[n_];
    for (std::size_t i = 0; i < n_; ++i) buf_a_[i] = static_cast<int>(i);

    // BUG: scratch is raw-new'd and local; throwing below leaks it.
    int* scratch = new int[n_];
    for (std::size_t i = 0; i < n_; ++i) scratch[i] = static_cast<int>(i);

    if (throw_midway) {
        throw std::runtime_error("midway failure");  // scratch leaks here
    }

    buf_b_ = new int[n_];
    for (std::size_t i = 0; i < n_; ++i) buf_b_[i] = scratch[i] * 2;
    delete[] scratch;
}

long long ResourceManager::checksum() const {
    long long s = 0;
    if (buf_a_) for (std::size_t i = 0; i < n_; ++i) s += buf_a_[i];
    if (buf_b_) for (std::size_t i = 0; i < n_; ++i) s += buf_b_[i];
    return s;
}

int main() {
    // 1) Functional behavior must not change:
    //    sum(0..999) + sum(0,2,...,1998) = 499500 + 999000 = 1498500
    {
        ResourceManager rm(1000);
        rm.run(false);
        if (rm.checksum() != 1498500) {
            std::cerr << "functional output changed\n";
            return 1;
        }
    }
    // 2) Exception path must not leak.
    {
        const long long before = LeakStats::alive;
        try {
            ResourceManager rm(1000);
            rm.run(true);  // throws
        } catch (const std::runtime_error&) {
            // expected
        }
        const long long after = LeakStats::alive;
        if (after != before) {
            std::cerr << "LEAK on exception path: alive " << before
                      << " -> " << after << "\n";
            return 2;
        }
    }
    // 3) Normal path also balanced.
    {
        const long long before = LeakStats::alive;
        { ResourceManager rm(500); rm.run(false); }
        if (LeakStats::alive != before) {
            std::cerr << "LEAK on normal path\n";
            return 3;
        }
    }
    std::cout << "ALL TESTS PASSED\n";
    return 0;
}
