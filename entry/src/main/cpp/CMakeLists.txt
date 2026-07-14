# the minimum version of CMake.
cmake_minimum_required(VERSION 3.5.0)
project(TelegramForHarmony)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

# Keep the build machine out of the shipped binary. Linking against the
# imported libtdjson.so otherwise records its directory — an absolute path on
# the developer's disk — as RUNPATH, and __FILE__ in any assertion would bake
# in the source path. Both are visible to anyone running `strings` on a
# released HAP. RUNPATH is useless at runtime anyway: the loader resolves
# DT_NEEDED from the HAP's own libs directory.
set(CMAKE_SKIP_BUILD_RPATH TRUE)
set(CMAKE_SKIP_INSTALL_RPATH TRUE)
add_compile_options(-ffile-prefix-map=${CMAKE_CURRENT_SOURCE_DIR}=.)

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include)

add_library(entry SHARED napi_init.cpp)

add_library(tdjson SHARED IMPORTED)
set_target_properties(tdjson PROPERTIES IMPORTED_LOCATION
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/${OHOS_ARCH}/libtdjson.so)

target_link_libraries(entry PUBLIC libace_napi.z.so tdjson libhilog_ndk.z.so)