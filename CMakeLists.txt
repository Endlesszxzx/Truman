cmake_minimum_required(VERSION 3.14)

# Workspace entry point for CLion.  The actual analyzer CMake project remains
# in static_analysis/; exposing it here lets the repository root be opened as
# one CMake project and makes the AnalyzerDBM target available in its CMake
# tool window.
project(TrumanWorkspace LANGUAGES C CXX)

add_subdirectory(static_analysis)
