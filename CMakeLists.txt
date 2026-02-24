cmake_minimum_required(VERSION 3.28)
set(PROJECT_NAME "$ENV{PROJECT_NAME}")
project("${PROJECT_NAME}" LANGUAGES C CXX)

add_library(core SHARED
    native/test.h
    native/test.c
    native/test.c++
    native/test.m
    native/test.mm
)

enable_testing()
add_executable(core_test native/test.test.c++)
target_link_libraries(core_test PUBLIC core)
add_test(
    NAME core_test
    COMMAND core_test
)