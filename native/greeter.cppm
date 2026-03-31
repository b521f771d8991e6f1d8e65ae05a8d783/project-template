module;

#include <string>

export module greeter;

export namespace greeter {

auto greet(std::string_view name) -> std::string {
  return std::string("Hello, ") + std::string(name) + "!";
}

} // namespace greeter
