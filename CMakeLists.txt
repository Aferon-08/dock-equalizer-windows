cmake_minimum_required(VERSION 3.25)
project(SekaiSoundbar VERSION 0.12.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
add_compile_options("$<$<CXX_COMPILER_ID:MSVC>:/utf-8>")

find_package(Qt6 6.8.2 REQUIRED COMPONENTS Network Quick QuickControls2 ShaderTools Svg Widgets)
qt_standard_project_setup(REQUIRES 6.8)

include(CTest)
qt_add_executable(SekaiSoundbar WIN32)

# Declare the module from the project root so qmlcachegen never puts parent
# components in Windows output paths for the shared QML and JavaScript files.
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
foreach(file IN ITEMS Main.qml ApplicationState.qml SettingsWindow.qml)
    set_source_files_properties("windows/qml/${file}"
        PROPERTIES QT_RESOURCE_ALIAS "${file}")
endforeach()
foreach(file IN ITEMS AlignmentDialog.qml DockNotification.qml DockPresence.qml)
    set_source_files_properties("windows/qml/${file}"
        PROPERTIES QT_RESOURCE_ALIAS "qml/${file}")
endforeach()
foreach(file IN LISTS shared_ui shared_assets)
    set_source_files_properties("${PROJECT_SOURCE_DIR}/${file}"
        PROPERTIES QT_RESOURCE_ALIAS "${file}")
endforeach()
list(TRANSFORM shared_ui PREPEND "${PROJECT_SOURCE_DIR}/")
list(TRANSFORM shared_assets PREPEND "${PROJECT_SOURCE_DIR}/")

qt_add_qml_module(SekaiSoundbar
    URI Sekai.Soundbar
    QML_FILES
        windows/qml/Main.qml
        windows/qml/AlignmentDialog.qml
        windows/qml/ApplicationState.qml
        windows/qml/DockNotification.qml
        windows/qml/DockPresence.qml
        windows/qml/SettingsWindow.qml
        ${shared_ui}
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

add_subdirectory(windows)
