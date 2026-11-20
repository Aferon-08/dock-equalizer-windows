target_sources(SekaiSoundbar PRIVATE main.cpp DesktopOverlay.cpp DesktopOverlay.h
    MediaSessions.cpp MediaSessions.h PlaybackClock.h ArtworkColor.cpp ArtworkColor.h
    DisplaySettings.cpp DisplaySettings.h DockAppearance.cpp DockAppearance.h StartupSettings.cpp StartupSettings.h
    LyricsAlignment.cpp LyricsAlignment.h
    LyricsHttp.cpp LyricsHttp.h LyricsImport.cpp LyricsImport.h LyricsSearch.cpp LyricsSearch.h
    SystemAudio.cpp SystemAudio.h SpectrumAnalyzer.cpp SpectrumAnalyzer.h
    MonitorBackdrop.cpp MonitorBackdrop.h BackdropGeometry.h)
target_include_directories(SekaiSoundbar PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(SekaiSoundbar PRIVATE Qt6::Network Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)
target_compile_definitions(SekaiSoundbar PRIVATE SOUNDBAR_VERSION="${PROJECT_VERSION}")
if(WIN32)
    target_sources(SekaiSoundbar PRIVATE WinMediaWorker.cpp WinMediaWorker.h WinMediaAbi.h
        WinCaptureAbi.h BackdropTextureNode.h)
    target_link_libraries(SekaiSoundbar PRIVATE Qt6::GuiPrivate d3d11 dwmapi runtimeobject ole32 shcore)
endif()

if(WIN32)
    install(TARGETS SekaiSoundbar RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")
    install(FILES "${PROJECT_SOURCE_DIR}/LICENSE" "${PROJECT_SOURCE_DIR}/THIRD_PARTY.md" DESTINATION .)
    install(FILES alignment/worker.py alignment/cpu-windows.lock DESTINATION "${CMAKE_INSTALL_BINDIR}/alignment")
    set(SOUNDBAR_ALIGNMENT_PYTHON "" CACHE PATH "Path to the CPython 3.12 x64 NuGet tools directory")
    if(SOUNDBAR_ALIGNMENT_PYTHON)
        install(DIRECTORY "${SOUNDBAR_ALIGNMENT_PYTHON}/" DESTINATION "${CMAKE_INSTALL_BINDIR}/alignment/python")
    endif()
    if(MSVC)
        # Deploy the app-local Visual C++ DLLs so the ZIP runs without setup.
        set(CMAKE_INSTALL_SYSTEM_RUNTIME_DESTINATION "${CMAKE_INSTALL_BINDIR}")
        include(InstallRequiredSystemLibraries)
        set(deploy_compiler_runtime NO_COMPILER_RUNTIME)
    endif()
    qt_generate_deploy_qml_app_script(
        TARGET SekaiSoundbar
        OUTPUT_SCRIPT deploy_script
        ${deploy_compiler_runtime}
        NO_TRANSLATIONS
        DEPLOY_TOOL_OPTIONS --include-plugins qsvg,qschannelbackend
    )
    install(SCRIPT "${deploy_script}")
    file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/VERSION.txt" "${PROJECT_VERSION}\n")
    install(FILES "${CMAKE_CURRENT_BINARY_DIR}/VERSION.txt" DESTINATION .)
endif()

if(BUILD_TESTING)
    add_executable(soundbar_clock_test tests/PlaybackClockTest.cpp)
    add_test(NAME soundbar.clock COMMAND soundbar_clock_test)
    add_executable(soundbar_spectrum_test tests/SpectrumAnalyzerTest.cpp SpectrumAnalyzer.cpp)
    add_test(NAME soundbar.spectrum COMMAND soundbar_spectrum_test)
    add_executable(soundbar_artwork_color_test tests/ArtworkColorTest.cpp ArtworkColor.cpp)
    target_link_libraries(soundbar_artwork_color_test PRIVATE Qt6::Gui)
    add_test(NAME soundbar.artwork-color COMMAND soundbar_artwork_color_test)
    add_executable(soundbar_backdrop_test tests/BackdropGeometryTest.cpp)
    target_link_libraries(soundbar_backdrop_test PRIVATE Qt6::Core)
    add_test(NAME soundbar.backdrop-geometry COMMAND soundbar_backdrop_test)
    add_executable(soundbar_lyrics_test tests/LyricsImportTest.cpp LyricsImport.cpp LyricsImport.h)
    target_link_libraries(soundbar_lyrics_test PRIVATE Qt6::Core)
    add_test(NAME soundbar.lyrics-import COMMAND soundbar_lyrics_test)
    add_executable(soundbar_lyrics_search_test tests/LyricsSearchTest.cpp
        LyricsHttp.cpp LyricsHttp.h LyricsImport.cpp LyricsImport.h LyricsSearch.cpp LyricsSearch.h)
    target_link_libraries(soundbar_lyrics_search_test PRIVATE Qt6::Network Qt6::Qml)
    qt_add_resources(soundbar_lyrics_search_test lyrics_math
        PREFIX "/qt/qml/Sekai/Soundbar" BASE "${PROJECT_SOURCE_DIR}"
        FILES "${PROJECT_SOURCE_DIR}/LyricsMath.js")
    add_test(NAME soundbar.lyrics-search COMMAND soundbar_lyrics_search_test)
    set_tests_properties(soundbar.lyrics-search PROPERTIES TIMEOUT 20)
    find_program(SOUNDBAR_TEST_CURL curl)
    if(SOUNDBAR_TEST_CURL AND NOT CMAKE_CROSSCOMPILING)
        add_test(NAME soundbar.lyrics-search-curl COMMAND soundbar_lyrics_search_test "${SOUNDBAR_TEST_CURL}")
        set_tests_properties(soundbar.lyrics-search-curl PROPERTIES TIMEOUT 45)
    endif()
    set(smoke_fixtures
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/lyrics.lrc"
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/wordtime.json")
    add_test(NAME soundbar.overlay COMMAND SekaiSoundbar --smoke-test ${smoke_fixtures})
    add_test(NAME soundbar.overlay-software COMMAND SekaiSoundbar --software-rendering --smoke-test ${smoke_fixtures})
    set_tests_properties(soundbar.overlay soundbar.overlay-software PROPERTIES
        TIMEOUT 35
        FAIL_REGULAR_EXPRESSION
            "Error decoding;Error loading;Failed to deserialize QShader;ReferenceError:;TypeError:"
    )
endif()
