set(RADIANCE_SOURCES
        radiance.h
        radiance.cpp
)

add_library(radiance ${RADIANCE_SOURCES})
target_include_directories(radiance PUBLIC ../lib)