cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

set(RUNNER_RESOURCE "Runner.rc")
if(YUEYIN_BUILD)
  set(RUNNER_RESOURCE "Yueyin.rc")
endif()

add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "floating_lyrics_channel.cpp"
  "floating_lyrics_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "${RUNNER_RESOURCE}"
  "runner.exe.manifest"
)

apply_standard_settings(${BINARY_NAME})
if(YUEYIN_BUILD)
  target_sources(${BINARY_NAME} PRIVATE "windows_desktop_channel.cpp"
    "ik_desktop_channel.cpp" "ik_desktop_host.cpp")
  target_compile_definitions(${BINARY_NAME} PRIVATE "YUEYIN_BUILD")
  target_link_libraries(${BINARY_NAME} PRIVATE "shell32.lib" "gdi32.lib"
    "windowsapp.lib" "runtimeobject.lib" "shcore.lib" "advapi32.lib")
  foreach(GATE_TARGET yueyin_desktop_gate yueyin_desktop_red_gate)
    add_executable(${GATE_TARGET} EXCLUDE_FROM_ALL "windows_desktop_gate.cpp")
    apply_standard_settings(${GATE_TARGET})
    target_compile_definitions(${GATE_TARGET} PRIVATE "NOMINMAX")
    target_link_libraries(${GATE_TARGET} PRIVATE "user32.lib" "gdi32.lib")
    target_compile_options(${GATE_TARGET} PRIVATE /utf-8)
    set_target_properties(${GATE_TARGET} PROPERTIES
      RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/desktop-gate")
  endforeach()
  target_compile_definitions(yueyin_desktop_red_gate PRIVATE "LEYIN_DESKTOP_BASELINE")
  foreach(GATE_TARGET ik_desktop_gate ik_desktop_red_gate)
    add_executable(${GATE_TARGET} EXCLUDE_FROM_ALL
      "ik_desktop_gate.cpp" "ik_desktop_host.cpp")
    apply_standard_settings(${GATE_TARGET})
    target_compile_definitions(${GATE_TARGET} PRIVATE "NOMINMAX")
    target_compile_options(${GATE_TARGET} PRIVATE /utf-8)
    target_link_libraries(${GATE_TARGET} PRIVATE "user32.lib" "shell32.lib"
      "advapi32.lib" "windowsapp.lib" "runtimeobject.lib" "shcore.lib")
    set_target_properties(${GATE_TARGET} PROPERTIES
      RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/desktop-gate")
  endforeach()
  target_compile_definitions(ik_desktop_red_gate PRIVATE "IK_DESKTOP_BASELINE")
endif()

target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

add_dependencies(${BINARY_NAME} flutter_assemble)
