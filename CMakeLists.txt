# Copyright (C) 2022 Toitware ApS.

cmake_minimum_required(VERSION 3.23)

project(supabase)

set(TOITRUN "toit.run" CACHE FILEPATH "The executable used to run the tests")
set(TOITPKG "toit.pkg" CACHE FILEPATH "The executable used to install the packages")

include("tools/toit.cmake")

toit_project(supabase "${CMAKE_CURRENT_LIST_DIR}")

enable_testing()
add_subdirectory(tests)
