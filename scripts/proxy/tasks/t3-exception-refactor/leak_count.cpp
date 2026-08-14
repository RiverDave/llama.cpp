#include "leak_count.h"

#include <cstdlib>

long long LeakStats::alive = 0;

void* operator new(std::size_t n) {
    LeakStats::alive += 1;
    return std::malloc(n);
}

void operator delete(void* p) noexcept {
    if (p) LeakStats::alive -= 1;
    std::free(p);
}

void* operator new[](std::size_t n) {
    LeakStats::alive += 1;
    return std::malloc(n);
}

void operator delete[](void* p) noexcept {
    if (p) LeakStats::alive -= 1;
    std::free(p);
}

void operator delete(void* p, std::size_t) noexcept { ::operator delete(p); }
void operator delete[](void* p, std::size_t) noexcept { ::operator delete[](p); }
