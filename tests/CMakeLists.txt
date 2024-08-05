add_subdirectory(external/googletest)

set(TESTS_SOURCES
        main.cpp
        websockets.cpp
        gltf.mm
        json.cpp
)

add_executable(tests ${TESTS_SOURCES})

target_link_libraries(tests gtest metal_experiment_lib)

set_source_files_properties(main.cpp PROPERTIES
        COMPILE_FLAGS "-x objective-c++")