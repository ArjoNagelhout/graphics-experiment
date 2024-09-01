cmake_minimum_required(VERSION 3.6)

project(my_app)

add_library(graphics_experiment SHARED
    YourSourceHere.c
)
target_link_libraries(graphics_experiment PRIVATE SDL3::SDL3)
