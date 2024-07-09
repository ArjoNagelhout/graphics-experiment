# lodepng
set(LODEPNG_SOURCES
        lodepng/lodepng.h
        lodepng/lodepng.cpp
)

add_library(lodepng ${LODEPNG_SOURCES})
target_include_directories(lodepng PUBLIC lodepng)

# glm
add_subdirectory(glm)

# fmt
add_subdirectory(fmt)

# tinygltf
add_subdirectory(tinygltf)

# imgui
set(IMGUI_SOURCES
        imgui/imgui.h
        imgui/imgui.cpp

        imgui/imgui_demo.cpp
        imgui/imgui_draw.cpp
        imgui/imgui_widgets.cpp

        imgui/imgui_demo.cpp
        imgui/imgui_tables.cpp

        imgui/backends/imgui_impl_metal.h
        imgui/backends/imgui_impl_metal.mm

        imgui/backends/imgui_impl_osx.h
        imgui/backends/imgui_impl_osx.mm

        imgui/misc/cpp/imgui_stdlib.h
        imgui/misc/cpp/imgui_stdlib.cpp
)
add_library(imgui ${IMGUI_SOURCES})
target_include_directories(imgui PUBLIC imgui)

# simdjson
add_subdirectory(simdjson)

# libwebsockets
add_subdirectory(libwebsockets)