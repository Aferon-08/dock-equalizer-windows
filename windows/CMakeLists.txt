qt_add_executable(SekaiSoundbar WIN32 main.cpp DesktopOverlay.cpp DesktopOverlay.h)
target_sources(SekaiSoundbar PRIVATE MediaSessions.cpp MediaSessions.h PlaybackClock.h
    SystemAudio.cpp SystemAudio.h SpectrumAnalyzer.cpp SpectrumAnalyzer.h)
target_link_libraries(SekaiSoundbar PRIVATE Qt6::Quick Qt6::QuickControls2)
if(WIN32)
    target_sources(SekaiSoundbar PRIVATE WinMediaWorker.cpp WinMediaWorker.h WinMediaAbi.h)
    target_link_libraries(SekaiSoundbar PRIVATE dwmapi runtimeobject ole32 shcore)
endif()

# Explicit inputs keep the SekaiPOP adapters out of QML scanning and deployment.
set(shared_ui
    BackingLayer.qml
    BackingPhrase.qml
    DockLyrics.qml
    DockWings.qml
    FireflyScene.qml
    KaraokeLine.qml
    LandingSplashes.qml
    LyricMarker.qml
    LyricsFinale.qml
    LyricsReel.qml
    MarkerScene.qml
    MultiVoiceGlow.qml
    MultiVoiceLyrics.qml
    SpectrumRibbon.qml
    VisualizerCapsule.qml
    WaitingDots.qml
    WavyProgress.qml
    AnalysisPolicy.js
    BackingLayout.js
    BeatTracker.js
    DockMaterial.js
    FireflyMotion.js
    ImportedLyrics.js
    LightMotion.js
    LyricsEnd.js
    LyricsMath.js
    LyricsTimeline.js
    MarkerLayout.js
    MarkerMotion.js
    MultiVoiceFinale.js
    MultiVoiceMath.js
    VoiceAnnotations.js
)
set(shared_assets assets/next.svg assets/previous.svg assets/volume.svg)
set_source_files_properties(qml/Main.qml PROPERTIES QT_RESOURCE_ALIAS Main.qml)
foreach(file IN LISTS shared_ui shared_assets)
    set_source_files_properties("${PROJECT_SOURCE_DIR}/${file}" PROPERTIES QT_RESOURCE_ALIAS "${file}")
endforeach()
list(TRANSFORM shared_ui PREPEND "${PROJECT_SOURCE_DIR}/")
list(TRANSFORM shared_assets PREPEND "${PROJECT_SOURCE_DIR}/")

qt_add_qml_module(SekaiSoundbar
    URI Sekai.Soundbar
    QML_FILES qml/Main.qml ${shared_ui}
    RESOURCES ${shared_assets}
)

qt_add_shaders(SekaiSoundbar soundbar_shaders
    PREFIX "/qt/qml/Sekai/Soundbar"
    BASE "${PROJECT_SOURCE_DIR}"
    FILES
        "${PROJECT_SOURCE_DIR}/glass.frag"
        "${PROJECT_SOURCE_DIR}/liquid.frag"
        "${PROJECT_SOURCE_DIR}/spectrum-ribbon.frag"
)

if(WIN32)
    install(TARGETS SekaiSoundbar RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")
    install(FILES "${PROJECT_SOURCE_DIR}/LICENSE" "${PROJECT_SOURCE_DIR}/THIRD_PARTY.md" DESTINATION .)
    qt_generate_deploy_qml_app_script(
        TARGET SekaiSoundbar
        OUTPUT_SCRIPT deploy_script
        DEPLOY_TOOL_OPTIONS --include-plugins qsvg
    )
    install(SCRIPT "${deploy_script}")
endif()

if(BUILD_TESTING)
    add_executable(soundbar_clock_test tests/PlaybackClockTest.cpp)
    add_test(NAME soundbar.clock COMMAND soundbar_clock_test)
    add_executable(soundbar_spectrum_test tests/SpectrumAnalyzerTest.cpp SpectrumAnalyzer.cpp)
    add_test(NAME soundbar.spectrum COMMAND soundbar_spectrum_test)
    add_test(NAME soundbar.overlay COMMAND SekaiSoundbar --smoke-test)
    set_tests_properties(soundbar.overlay PROPERTIES
        TIMEOUT 25
        FAIL_REGULAR_EXPRESSION
            "Error decoding;Error loading;Failed to deserialize QShader;ReferenceError:;TypeError:"
    )
endif()
