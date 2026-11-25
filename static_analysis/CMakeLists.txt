cmake_minimum_required(VERSION 3.14)

project(truman)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
	message("Setting build type to 'RelWithDebInfo' as none was specified.")
	set(CMAKE_BUILD_TYPE RelWithDebInfo CACHE STRING "Choose the type of build." FORCE)
endif()

if(CMAKE_BUILD_TYPE STREQUAL "Debug")
	set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -DSPDLOG_ACTIVE_LEVEL=1")
endif()

find_package(LLVM 17.0.6 EXACT REQUIRED CONFIG PATHS ${LLVM_DIR})
add_definitions(${LLVM_DEFINITIONS})
include_directories(${LLVM_INCLUDE_DIRS} ${PROJECT_SOURCE_DIR}/include)

if(NOT SVF_SOURCE_DIR OR NOT SVF_BUILD_DIR)
	message(FATAL_ERROR "SVF_SOURCE_DIR and SVF_BUILD_DIR must point to the checked-out SVF source and its LLVM 17 build directory")
endif()
if(NOT EXISTS "${SVF_SOURCE_DIR}/svf/include/WPA/Andersen.h" OR
		NOT EXISTS "${SVF_SOURCE_DIR}/svf-llvm/include/SVF-LLVM/SVFIRBuilder.h")
	message(FATAL_ERROR "SVF_SOURCE_DIR does not contain the SVF Core/SVF-LLVM source layout")
endif()

set(SVF_LIBRARIES
	"${SVF_BUILD_DIR}/lib/libSvfLLVM.a"
	"${SVF_BUILD_DIR}/lib/libSvfCore.a"
)
foreach(SVF_LIBRARY IN LISTS SVF_LIBRARIES)
	if(NOT EXISTS "${SVF_LIBRARY}")
		message(FATAL_ERROR "Missing SVF library: ${SVF_LIBRARY}")
	endif()
endforeach()

include_directories(SYSTEM
	${SVF_SOURCE_DIR}/svf/include
	${SVF_SOURCE_DIR}/svf-llvm/include
	${SVF_BUILD_DIR}/include
)
link_directories(${LLVM_LIBRARY_DIRS})
if(LLVM_LINK_LLVM_DYLIB)
	set(TRUMAN_LLVM_LIBRARIES LLVM)
else()
	llvm_map_components_to_libnames(TRUMAN_LLVM_LIBRARIES core ipo irreader support)
endif()

set(CMAKE_POSITION_INDEPENDENT_CODE ON)

include(FetchContent)

FetchContent_Declare(
	spdlog
	GIT_REPOSITORY https://github.com/gabime/spdlog.git
	GIT_TAG	v1.x
)

FetchContent_Declare(
	yaml-cpp
	GIT_REPOSITORY https://github.com/jbeder/yaml-cpp.git
)

FetchContent_MakeAvailable(spdlog yaml-cpp)

include_directories(z3/include)
link_directories(z3/bin)
add_subdirectory(RangeAnalysis)
add_subdirectory(Customizations)
add_subdirectory(LinuxKernelCustomizations)
add_subdirectory(Utils)
add_subdirectory(Analyzer)
