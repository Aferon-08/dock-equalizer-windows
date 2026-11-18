import QtQuick
import QtQuick.Window
import Quickshell
import ".." as Plugin

ShellRoot {
    id: test
    settings.watchFiles: false
    property real elapsed: 0
    property var spectrum: Array.from({length:64},(_,i)=>100)
    property var coverSnapshot: null
    DemoRecorder { id: recorder; scene: win.contentItem }
    QtObject {
        id: demoPlayer
        property bool lengthSupported: true
        property real length: Number(Quickshell.env("DEMO_TRACK_DURATION")) || 120
        property bool positionSupported: true
        property bool canSeek: true
        property bool canGoPrevious: true
        property bool canGoNext: true
        property bool canTogglePlaying: true
        property bool volumeSupported: true
        property bool canControl: true
        property real volume: 0.8
        property real position: 2.2
        property var metadata: ({ "xesam:url": "file:///demo.ogg" })
    }
    QtObject {
        id: demoMedia
        property var player: demoPlayer
        property bool playing: false
        property string title: "A little light"
        property string artist: "SekaiPOP Demo"
        property string artUrl: ""
        function togglePlaying() { playing = !playing }
        function next() { console.log("NEXT") }
        function previous() { console.log("PREVIOUS") }
    }
    QtObject {
        id: demoLyrics
        property string status: "ready"
        property var lastArgs: ["SekaiPOP Demo", "A little light"]
        property int syncTotal: 0
        property var lines: [
            {t:0,text:"A little light begins to glow",marks:[{cs:0,t:0},{cs:2,t:.4},{cs:9,t:1.2},{cs:15,t:2.1},{cs:22,t:2.8},{cs:25,t:3.2}]},
            {t:4,text:"It follows every word we know",marks:[{cs:0,t:4},{cs:3,t:4.5},{cs:11,t:5.3},{cs:17,t:6.1},{cs:22,t:6.8},{cs:25,t:7.4}]},
            {t:8,text:"Across the glass and into blue",marks:[{cs:0,t:8},{cs:7,t:8.6},{cs:11,t:9.1},{cs:17,t:9.8},{cs:21,t:10.5},{cs:26,t:11.1}]},
            {t:12,text:"A tiny world that moves with you",marks:[{cs:0,t:12},{cs:2,t:12.4},{cs:7,t:13},{cs:13,t:13.5},{cs:18,t:14},{cs:24,t:14.7},{cs:29,t:15.2}]},
            {t:17,text:"Let every little spark shine through"}
        ]
    }
    QtObject {
        id: demoHost
        property var settings: ({ enabled: true, width: 200, height: 38, gap: 12, sensitivity: 1.25, style: "wave", collapseDelay: 600,
            lyrics: true, expandLyrics: true, lyricsWidth: 560, progressStyle: Quickshell.env("DEMO_PROGRESS_STYLE") || "material" })
        property bool working: true
        property var service: {
            const phase = (test.elapsed * 118 / 60) % 1
            return {playing: demoMedia.playing, bands: test.spectrum, rhythm: {
                at: Date.now(), bpm: 118, phase: phase, confidence: .9,
                beat: .9 * Math.exp(-phase * 5.8), onset: 0, energy: .48}}
        }
        property var theme: ({ fontFamily: "Noto Sans", iconFont: "Material Symbols Rounded" })
        property QtObject dock: QtObject {
            property var item: pill
            property bool vertical: false
            property bool capsule: true
            property string look: "capsule"
            property real radius: Math.min(pill.width, pill.height - 4) / 2
            property real shadow: 4
            property bool asleep: false
            property var mediaSource: demoMedia
            property var lyrics: demoLyrics
            property bool hovered: false
            property bool editing: false
            property bool desktopEmpty: false
            property real baseCapHeight: 69
            property real baseWidth: 432
            property real stageWidth: 1100
            property var palette: ({ fill: Qt.color("#101b18"), rim: Qt.color("#284a3d"), shadow: Qt.color("#060d0a"), ink: Qt.color("#e8f4ee"), accent: Qt.color("#96dcc0"), border: 3, ringWidth: 3, ring: Qt.color("#101b18") })
        }
    }
    QtObject {
        id: scenePalette
        property bool dark: true
        property color surface: "#182328"
        property color accentCyan: "#80a7d7"
        property color accentMint: "#96dcc0"
    }
    Window {
        id: win
        visible: true
        width: 1100; height: 360; minimumWidth:1100; maximumWidth:1100; minimumHeight:360; maximumHeight:360; flags:Qt.Tool|Qt.FramelessWindowHint; color: "#182328"
        Item {
            id: coverArt
            width: 96; height: 96
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop {position: 0; color: "#3c6589"}
                    GradientStop {position: 1; color: "#182633"}
                }
            }
            Rectangle {x: 18; y: 20; width: 61; height: 61; radius: width / 2; color: "#6886aa"}
            Rectangle {x: 27; y: 34; width: 50; height: 50; radius: width / 2; color: "#263e5b"}
            Rectangle {x: 49; y: 32; width: 15; height: 15; radius: width / 2; color: "#f1bf97"}
        }
        Plugin.ProceduralWallpaper {
            anchors.fill: parent
            seed: "dock-preview-glass"
            screenName: "dock-demo"
            theme: scenePalette
            settings: ({wallpaperDensity: "calm", wallpaperMotion: false, wallpaperGlass: .72,
                wallpaperIntro: 1500, wallpaperPet: false})
        }
        Plugin.DockWings { id: wings; anchors.fill: parent; host: demoHost }
        Item {
            id: pill
            width: 432 + wings.lyricsWidthExtra
            height: 73 + wings.lyricsHeightExtra
            x: (parent.width - width) / 2; y: 55
            readonly property real capWidth: width
            readonly property real capHeight: height - 4
            Row {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: wings.iconsOffset / 2
                scale: wings.iconsScale
                opacity: wings.iconsOpacity
                spacing: 24
                Repeater { model: ["search", "folder", "content_paste", "timer", "web", "terminal", "push_pin"]; Text { required property string modelData; text: modelData; color: "white"; font.family: "Material Symbols Rounded"; font.pixelSize: 30 } }
            }
        }
    }
    Timer {
        interval: 250
        running: true
        onTriggered: coverArt.grabToImage(result => {
            test.coverSnapshot = result
            demoMedia.artUrl = result.url
        })
    }
    Timer { interval: 50; running:!recorder.finishing; repeat:true; onTriggered: {
        test.elapsed+=.05
        demoMedia.playing=test.elapsed>1 && !(test.elapsed>15 && test.elapsed<18)
        demoHost.dock.desktopEmpty=test.elapsed>5
        if(demoMedia.playing)demoPlayer.position+=.05
        test.spectrum=Array.from({length:64},(_,i)=>Math.round(70+180*Math.pow((1+Math.sin(i*.41+test.elapsed*5.8))*.5,3)))
        if (test.elapsed > 22) recorder.finish()
        else recorder.record(wings.lyricsWidthExtra > 50
            ? (demoMedia.playing ? "expanded" : "paused")
            : demoMedia.playing && wings.phase > .6 ? "compact" : "idle")
    }}
}
