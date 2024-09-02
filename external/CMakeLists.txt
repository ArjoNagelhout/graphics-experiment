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
if (NOT ANDROID)
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
endif ()

# SDL
#because dealing with platform specific APIs for window creation is annoying
add_subdirectory(SDL)

# VulkanMemoryAllocator (vma), because Vulkan is very verbose for memory management
add_subdirectory(VulkanMemoryAllocator)

# googletest
add_subdirectory(googletest)

# vulkan
add_library(vulkan INTERFACE)

if (ANDROID)
    add_subdirectory(Vulkan-Headers)
    find_package(Vulkan REQUIRED)

    # make sure shaderc is built before this using the following instructions: https://developer.android.com/ndk/guides/graphics/shader-compilers
    # replace c++_shared with c++_static etc. if compiled with a different c++ standard library
    add_library(shaderc_android STATIC IMPORTED)
    set(SHADERC_DIR ${CMAKE_ANDROID_NDK}/sources/third_party/shaderc)
    message("shaderc dir ${SHADERC_DIR}")
    set_target_properties(shaderc_android PROPERTIES IMPORTED_LOCATION
            ${SHADERC_DIR}/libs/c++_shared/${ANDROID_ABI}/libshaderc.a)
    target_include_directories(shaderc_android INTERFACE ${SHADERC_DIR}/include)

    target_link_libraries(vulkan INTERFACE
            Vulkan::Vulkan
            Vulkan-Headers # hpp headers are not provided by the Android NDK, so we have to add it manually
            shaderc_android
    )
else ()
    find_package(Vulkan REQUIRED COMPONENTS shaderc_combined)
    target_link_libraries(vulkan INTERFACE
            Vulkan::Vulkan
            Vulkan::shaderc_combined
    )
endif ()
