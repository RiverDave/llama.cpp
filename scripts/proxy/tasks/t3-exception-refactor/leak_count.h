#pragma once
// Allocation counter used by the tests to detect leaks. DO NOT MODIFY.
#include <cstddef>

struct LeakStats {
    static long long alive;
};

// Global operator new/delete replacements (defined in leak_count.cpp).
void* operator new(std::size_t n);
void operator delete(void* p) noexcept;
void* operator new[](std::size_t n);
void operator delete[](void* p) noexcept;
void operator delete(void* p, std::size_t) noexcept;
void operator delete[](void* p, std::size_t) noexcept;
