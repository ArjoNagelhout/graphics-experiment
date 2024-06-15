# lodepng
set(LODEPNG_SOURCES
        lodepng/lodepng.h
        lodepng/lodepng.cpp
)

add_library(lodepng ${LODEPNG_SOURCES})
target_include_directories(lodepng PUBLIC lodepng)

# glm
add_subdirectory(glm)