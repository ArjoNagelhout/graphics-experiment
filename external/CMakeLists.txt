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
set(CGLTF_SOURCES
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
# opencascade and eigen should be installed and their install paths should be specified as cmake arguments:
# -DOCC_INCLUDE_DIR=/opt/homebrew/include/opencascade
# -DEIGEN_DIR=/opt/homebrew/include/eigen3
# see https://docs.ifcopenshell.org/ifcopenshell/installation.html

# default options:
option(BUILD_IFCGEOM "" ON)
option(BUILD_IFCPYTHON "" OFF)
option(BUILD_CONVERT "" OFF)
option(BUILD_DOCUMENTATION "" OFF)
option(BUILD_EXAMPLES "" OFF)
option(BUILD_GEOMSERVER "" OFF)
option(BUILD_IFCMAX "" OFF)
option(BUILD_QTVIEWER "" OFF)
option(BUILD_PACKAGE "" OFF)
option(GLTF_SUPPORT "" OFF)
option(CITYJSON_SUPPORT "" OFF)
option(COLLADA_SUPPORT "" OFF)
option(HDF5_SUPPORT "" OFF)
option(WITH_CGAL "" OFF)
add_subdirectory(IfcOpenShell/cmake)

add_library(ifcopenshell INTERFACE)
target_link_libraries(ifcopenshell INTERFACE IfcParse IfcGeom)
target_include_directories(ifcopenshell INTERFACE IfcOpenShell/src)

# eigen include dirs are required, but as IfcOpenShell uses include_directories rather than target_include_directories,
# the include_directories do not get propagated outside ifcOpenShell/cmake/CMakeLists.txt
find_package(Eigen3 3.3 REQUIRED NO_MODULE)
target_link_libraries(ifcopenshell INTERFACE Eigen3::Eigen)

# SDL
#because dealing with platform specific APIs for window creation is annoying
add_subdirectory(SDL)

# MoltenVK
# see MoltenVK/README.md
# run the following commands:
# ./fetchDependencies --macos
# xcodebuild build -quiet -project MoltenVKPackaging.xcodeproj -scheme "MoltenVK Package (macOS only)" -configuration "Debug"

# dynamic linking and dynamic loading is recommended, but static linking is easiest for now

set(MOLTENVK_PACKAGE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/Package/Debug/MoltenVK)
add_library(moltenvk STATIC IMPORTED GLOBAL)
set_target_properties(moltenvk PROPERTIES
        IMPORTED_LOCATION ${MOLTENVK_PACKAGE_DIR}/static/MoltenVK.xcframework)
target_include_directories(moltenvk INTERFACE ${MOLTENVK_PACKAGE_DIR}/include)

# build Vulkan-Headers
# cd Vulkan-Headers/
# cmake -B build
# cmake --install build --prefix build/install

set(VULKAN_HEADERS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/Vulkan-Headers)
ExternalProject_Add(build_vulkan_headers
        SOURCE_DIR ${VULKAN_HEADERS_DIR}
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -G "Unix Makefiles" -B <BINARY_DIR> <SOURCE_DIR>
        BUILD_COMMAND ""
        INSTALL_COMMAND ${CMAKE_COMMAND} --install <BINARY_DIR> --prefix <INSTALL_DIR>
)
ExternalProject_Get_Property(build_vulkan_headers INSTALL_DIR)
set(VULKAN_HEADERS_INSTALL_DIR ${INSTALL_DIR})
message("vulkan headers install dir: ${VULKAN_HEADERS_INSTALL_DIR}")

add_library(vulkan_headers INTERFACE)
add_dependencies(vulkan_headers build_vulkan_headers)

# Vulkan Loader
# cd Vulkan-Loader/
# cmake -B build -DUPDATE_DEPS=OFF -DVULKAN_HEADERS_INSTALL_DIR=/Users/arjonagelhout/Documents/Experiments/metal-experiment/external/Vulkan-Headers/build/install -D CMAKE_BUILD_TYPE=Debug
# cmake --build build
# cmake --install build --prefix /Users/arjonagelhout/Documents/Experiments/metal-experiment/external/Vulkan-Loader/build/install

set(VULKAN_LOADER_DIR ${CMAKE_CURRENT_SOURCE_DIR}/Vulkan-Loader)
ExternalProject_Add(build_vulkan_loader
        SOURCE_DIR ${VULKAN_LOADER_DIR}
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -B <BINARY_DIR> <SOURCE_DIR> -DUPDATE_DEPS=OFF -DVULKAN_HEADERS_INSTALL_DIR=${VULKAN_HEADERS_INSTALL_DIR} -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
        BUILD_COMMAND ${CMAKE_COMMAND} --build <BINARY_DIR>
        INSTALL_COMMAND ${CMAKE_COMMAND} --install <BINARY_DIR> --prefix <INSTALL_DIR>
        BUILD_BYPRODUCTS <INSTALL_DIR>/lib/libvulkan.dylib
)
add_dependencies(build_vulkan_loader build_vulkan_headers)
ExternalProject_Get_Property(build_vulkan_loader INSTALL_DIR)
set(VULKAN_LOADER_INSTALL_DIR ${INSTALL_DIR})
message("vulkan loader install dir: ${VULKAN_LOADER_INSTALL_DIR}")

add_library(vulkan_loader STATIC IMPORTED GLOBAL)
add_dependencies(vulkan_loader build_vulkan_loader)
set_target_properties(vulkan_loader PROPERTIES IMPORTED_LOCATION ${VULKAN_LOADER_INSTALL_DIR}/lib/libvulkan.dylib)



# Vulkan validation layers
# cd Vulkan-ValidationLayers/
# cmake -B build -DUPDATE_DEPS=ON -DBUILD_WERROR=ON -DBUILD_TESTS=OFF -DCMAKE_BUILD_TYPE=Debug
# cmake --build build --config Debug
# cmake --install build --prefix /Users/arjonagelhout/Documents/Experiments/metal-experiment/external/Vulkan-ValidationLayers/build/install

