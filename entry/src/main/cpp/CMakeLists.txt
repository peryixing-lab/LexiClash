# the minimum version of CMake.
cmake_minimum_required(VERSION 3.5.0)
project(LexiClashBridge)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

add_library(flclash_core SHARED IMPORTED)
set_target_properties(flclash_core PROPERTIES
    IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/${OHOS_ARCH}/libflclash_core.so
    IMPORTED_NO_SONAME TRUE)

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include
                    ${CMAKE_CURRENT_SOURCE_DIR}/prebuilt/${OHOS_ARCH})

add_library(clash_bridge SHARED napi_init.cpp)
target_link_libraries(clash_bridge PUBLIC libace_napi.z.so libhilog_ndk.z.so flclash_core)
set_target_properties(clash_bridge PROPERTIES
    BUILD_WITH_INSTALL_RPATH TRUE
    INSTALL_RPATH "$ORIGIN")
