cmake_minimum_required(VERSION 3.6)

project(GAME)

# SDL sources are in a subfolder named "SDL"
add_subdirectory(SDL)

# Your game and its CMakeLists.txt are in a subfolder named "src"
add_subdirectory(src)
