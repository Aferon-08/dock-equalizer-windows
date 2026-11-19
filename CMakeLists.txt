cmake_minimum_required(VERSION 3.25)
project(SekaiSoundbar LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.8.2 REQUIRED COMPONENTS Network Quick QuickControls2 ShaderTools Svg)
qt_standard_project_setup(REQUIRES 6.8)

include(CTest)
add_subdirectory(windows)
