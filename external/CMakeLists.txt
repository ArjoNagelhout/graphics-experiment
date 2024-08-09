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
# add_subdirectory(libwebsockets)

# cgltf
set (CGLTF_SOURCES
        cgltf/cgltf.h
        cgltf/cgltf_write.h
)
add_library(cgltf INTERFACE ${CGLTF_SOURCES})
target_include_directories(cgltf INTERFACE cgltf)

# libjpeg-turbo
include(ExternalProject)
set(LIBJPEG_TURBO_DIR ${CMAKE_CURRENT_SOURCE_DIR}/libjpeg-turbo)
set(LIBJPEG_TURBO_LIB ${LIBJPEG_TURBO_DIR}/libturbojpeg.a)
ExternalProject_Add(build_libjpeg-turbo
        PREFIX ${LIBJPEG_TURBO_DIR}
        SOURCE_DIR ${LIBJPEG_TURBO_DIR}
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -G "Unix Makefiles" ${LIBJPEG_TURBO_DIR}
        BUILD_COMMAND ${CMAKE_COMMAND} --build ${LIBJPEG_TURBO_DIR}
        BUILD_BYPRODUCTS ${LIBJPEG_TURBO_LIB} # required for ninja
        INSTALL_COMMAND ""
        BUILD_IN_SOURCE 1
)

# GLOBAL is important: https://stackoverflow.com/questions/23565564/cmake-cant-find-imported-library
add_library(libjpeg-turbo STATIC IMPORTED GLOBAL)
add_dependencies(libjpeg-turbo build_libjpeg-turbo)
set_target_properties(libjpeg-turbo PROPERTIES
        IMPORTED_LOCATION ${LIBJPEG_TURBO_LIB}
)
target_include_directories(libjpeg-turbo INTERFACE ${LIBJPEG_TURBO_DIR})

# ifcopenshell
# these arguments are highly specific to the way these libraries are installed on my computer
# so this should be changed into cmake arguments for the top level application too
ExternalProject_Add(
        build_ifcopenshell
        SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/ifcOpenShell/cmake
        CMAKE_ARGS
            -DCMAKE_INSTALL_PREFIX=${CMAKE_BINARY_DIR}/ifcopenshell/install
            -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}

            -DBUILD_IFCGEOM=ON
            -DBUILD_CONVERT=ON
            -DBUILD_GEOMSERVER=OFF
            -DBUILD_IFCPYTHON=OFF

            -DGLTF_SUPPORT=OFF
            -DCITYJSON_SUPPORT=OFF
            -DCOLLADA_SUPPORT=OFF
            -DHDF5_SUPPORT=OFF

            -DWITH_CGAL=OFF

            -DOCC_INCLUDE_DIR=/opt/homebrew/include/opencascade
            -DEIGEN_DIR=/opt/homebrew/include/eigen3
        BUILD_IN_SOURCE 0
        INSTALL_COMMAND ""
)

add_library(ifcopenshell INTERFACE)
add_dependencies(ifcopenshell build_ifcopenshell)