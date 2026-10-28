cmake_minimum_required(VERSION 3.22)
project(whisper_vulkan_lib LANGUAGES C CXX)

# Builds the optional Android Vulkan speech library from the pinned whisper.cpp
# v1.9.1 sources. The CPU library stays an independent Gradle/CMake target so it
# keeps API 24 and never resolves Vulkan 1.1 symbols.
if(NOT ANDROID OR NOT ANDROID_ABI STREQUAL "arm64-v8a")
    message(FATAL_ERROR "libwhisper_vulkan.so targets Android arm64-v8a only")
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_BACKEND_DL OFF CACHE BOOL "" FORCE)
set(GGML_CPU_ARM_ARCH "armv8-a" CACHE STRING "" FORCE)
set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(GGML_CCACHE OFF CACHE BOOL "" FORCE)
set(GGML_VULKAN ON CACHE BOOL "" FORCE)

find_package(Vulkan REQUIRED)
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/whisper.cpp" whisper)
target_include_directories(ggml-vulkan PRIVATE "${SPIRV_INCLUDE_DIR}")

add_library(whisper_vulkan SHARED main.cpp)
set_target_properties(whisper_vulkan PROPERTIES
    OUTPUT_NAME whisper_vulkan
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN YES
)
target_include_directories(whisper_vulkan PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${WHISPER_DR_WAV_DIR}"
)
target_compile_definitions(whisper_vulkan PRIVATE WHISPER_GGML_VULKAN=1)
target_compile_options(whisper_vulkan PRIVATE -O3 -ffunction-sections -fdata-sections)
# --exclude-libs keeps ggml/whisper symbols private: the app loads this library
# next to the CPU library and must not interpose either runtime on the other.
target_link_options(whisper_vulkan PRIVATE -Wl,--gc-sections -Wl,--exclude-libs,ALL)
target_link_libraries(whisper_vulkan PRIVATE whisper Vulkan::Vulkan)
