cmake_minimum_required(VERSION 3.28)
set(PROJECT_NAME "$ENV{PROJECT_NAME}")
project("${PROJECT_NAME}" LANGUAGES C CXX OBJC OBJCXX)

add_library(core SHARED
    test.h
    test.c
    test.c++
    test.m
    test.mm
)
find_library(OBJC_LIBRARY objc
    HINTS ${CMAKE_C_IMPLICIT_LINK_DIRECTORIES})
target_link_libraries(core PUBLIC ${OBJC_LIBRARY})

enable_testing()
add_executable(core_test test.test.c++)
target_link_libraries(core_test PUBLIC core)
add_test(
    NAME core_test
    COMMAND core_test
)