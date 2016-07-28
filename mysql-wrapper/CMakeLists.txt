cmake_minimum_required(VERSION 3.2)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${CMAKE_SOURCE_DIR}/cmake")

include_directories(${CMAKE_CURRENT_BINARY_DIR} ${CMAKE_CURRENT_SOURCE_DIR})
add_executable(example example.cpp)
find_package (MySQL REQUIRED)

include_directories(${MYSQL_INCLUDE_DIRS})
target_link_libraries(example ${MYSQL_CLIENT_LIBS})

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=gnu++11 -g -O0" )

## Crutches ##

if (CYGWIN)
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,--image-base -Wl,0x10000000" )
endif (CYGWIN)
