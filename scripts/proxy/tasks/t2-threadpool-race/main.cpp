#include <iostream>
#include <queue>
#include <thread>
#include <vector>

// BUG: the shared queue and the running total are accessed by several
// threads with no synchronization. This is a data race (undefined
// behavior). The program usually prints the right answer by luck.
//
// Fix it so it is correct AND reports zero data races under
// ThreadSanitizer (the verify script compiles with -fsanitize=thread
// and runs with TSAN_OPTIONS=halt_on_error=1).
static int total = 0;

int main() {
    std::queue<int> work;
    for (int i = 1; i <= 1000; ++i) work.push(i);

    std::vector<std::thread> workers;
    for (int w = 0; w < 8; ++w) {
        workers.emplace_back([&] {
            while (!work.empty()) {
                int v = work.front();
                work.pop();
                total += v;
            }
        });
    }
    for (auto& t : workers) t.join();

    const int expected = 1000 * 1001 / 2;
    std::cout << "total=" << total << " expected=" << expected << "\n";
    return total == expected ? 0 : 1;
}
