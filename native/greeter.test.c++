import greeter;

#include <cassert>
#include <string>

int main() {
  assert(greeter::greet("World") == "Hello, World!");
  assert(greeter::greet("C++") == "Hello, C++!");
  return 0;
}
