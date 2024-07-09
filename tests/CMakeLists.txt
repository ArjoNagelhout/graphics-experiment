add_subdirectory(external/googletest)

set(TESTS_SOURCES
        websockets.cpp
        gltf.cpp
        json.cpp
)

add_executable(tests ${TESTS_SOURCES})

target_link_libraries(tests gtest_main libwebsockets tinygltf simdjson)