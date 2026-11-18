import QtQuick
import QtTest
import ".." as Plugin

Rectangle {
    id: background
    width: 540
    height: 100
    color: "#172822"

    Plugin.DockProgress {
        id: progress
        width: 408
        height: 20
        anchors.centerIn: parent
        settings: ({})
        palette: ({ink: Qt.color("#e8f4ee"), accent: Qt.color("#96dcc0")})
        secondary: "#77bcea"
        duration: 120
        seekable: true
    }
    SignalSpy {
        id: seeks
        target: progress
        signalName: "seek"
    }

    TestCase {
        name: "DockProgress"
        when: windowShown

        function init() {
            progress.settings = {}
            progress.glassEnabled = true
            progress.visible = true
            progress.playing = false
            progress.bands = []
            progress.fraction = 0
            progress.duration = 120
            progress.trackIdentity = "track-a"
            progress.indeterminate = false
            progress.seekable = true
            progress.palette = {ink: Qt.color("#e8f4ee"), accent: Qt.color("#96dcc0")}
            progress.secondary = "#77bcea"
            background.color = "#172822"
            seeks.clear()
        }

        function test_coordinates_data() {
            return [{tag: "legacy", settings: {}, renderer: "materialProgressRenderer"},
                {tag: "material", settings: {progressStyle: "material"}, renderer: "materialProgressRenderer"},
                {tag: "plassglass", settings: {progressStyle: "plassglass"}, renderer: "plassglassProgressRenderer"}]
        }

        function test_coordinates(data) {
            progress.settings = data.settings
            tryVerify(() => !!findChild(progress, data.renderer))
            const renderer = findChild(progress, data.renderer)
            const points = [0, 0.25, 0.5, 1, 0.25, 0]
            for (let i = 0; i < points.length; ++i) {
                const fraction = points[i]
                progress.fraction = fraction
                const x = 4 + fraction * 400
                compare(progress.positionX, x)
                if (progress.plassglass)
                    compare(renderer.x + renderer.width * renderer.fraction, x)
                else
                    compare(renderer.positionX, x)
                mouseClick(progress, x, 10, Qt.LeftButton)
                compare(seeks.count, i + 1)
                compare(seeks.signalArguments[i][0], fraction)
            }
            mouseClick(progress, 0, 10, Qt.LeftButton)
            mouseClick(progress, progress.width - 1, 10, Qt.LeftButton)
            compare(seeks.signalArguments[points.length][0], 0)
            compare(seeks.signalArguments[points.length + 1][0], 1)
        }

        function test_style_switch_and_unknown_duration() {
            progress.fraction = .5
            tryVerify(() => !!findChild(progress, "materialProgressRenderer"))
            const x = progress.positionX
            progress.settings = {progressStyle: "plassglass"}
            tryVerify(() => !!findChild(progress, "plassglassProgressRenderer"))
            tryVerify(() => !findChild(progress, "materialProgressRenderer"))
            compare(progress.positionX, x)
            compare(seeks.count, 0)
            progress.indeterminate = true
            tryVerify(() => !findChild(progress, "plassglassProgressRenderer"))
            mouseClick(progress, x, 10, Qt.LeftButton)
            compare(seeks.count, 0)
            progress.indeterminate = false
            progress.fraction = 0
            tryVerify(() => !!findChild(progress, "plassglassProgressRenderer"))
            compare(progress.positionX, progress.trackLeft)
            progress.visible = false
            tryVerify(() => !findChild(progress, "plassglassProgressRenderer"))
        }

        function test_scrub_data() { return [{tag: "material"}, {tag: "plassglass"}] }

        function test_scrub(data) {
            progress.settings = {progressStyle: data.tag}
            progress.fraction = .25
            mouseMove(progress, 204, 10)
            verify(progress.previewing)
            compare(progress.previewSeconds, 60)
            compare(progress.positionX, 104)
            mousePress(progress, 204, 10, Qt.LeftButton)
            verify(progress.scrubbing)
            compare(progress.positionX, 204)
            mouseMove(progress, 304, 10)
            compare(progress.previewSeconds, 90)
            progress.fraction = .28
            compare(progress.positionX, 304)
            compare(seeks.count, 0)
            mouseRelease(progress, 304, 10, Qt.LeftButton)
            verify(!progress.scrubbing)
            compare(seeks.count, 1)
            compare(seeks.signalArguments[0][0], .75)
        }

        function test_cancel_pressed_seek_data() {
            return [{tag: "escape"}, {tag: "track"}, {tag: "disabled"}, {tag: "unknown"}]
        }

        function test_cancel_pressed_seek(data) {
            progress.fraction = .25
            mousePress(progress, 204, 10, Qt.LeftButton)
            verify(progress.scrubbing)
            switch (data.tag) {
            case "escape": keyClick(Qt.Key_Escape); break
            case "track": progress.trackIdentity = "track-b"; break
            case "disabled": progress.seekable = false; break
            case "unknown": progress.indeterminate = true; break
            }
            verify(!progress.scrubbing)
            compare(progress.positionX, 104)
            mouseRelease(progress, 204, 10, Qt.LeftButton)
            compare(seeks.count, 0)
        }

        function test_keyboard_seek() {
            progress.fraction = .5
            progress.forceActiveFocus()
            verify(progress.activeFocus)
            keyClick(Qt.Key_Left)
            keyClick(Qt.Key_Right)
            keyClick(Qt.Key_Home)
            keyClick(Qt.Key_End)
            compare(seeks.signalArguments.map(values => Math.round(values[0] * 120)), [55, 65, 0, 120])
            progress.duration = 0
            keyClick(Qt.Key_Right)
            compare(seeks.count, 4)
        }

        function test_stereo_fade_and_clipping() {
            progress.settings = {progressStyle: "plassglass", spectrumFade: 80}
            progress.fraction = .5
            progress.playing = true
            tryVerify(() => !!findChild(progress, "progressSpectrum"))
            const spectrum = findChild(progress, "progressSpectrum")
            compare(spectrum.parent.width, 200)
            verify(spectrum.parent.clip)

            progress.bands = Array.from({length: 64}, (_, i) => i === 26 ? 80 : i === 37 ? 150 : 0)
            tryCompare(spectrum, "peak", .15)
            compare(spectrum.amplitudes[5], .15)
            progress.bands = Array(64).fill(0)
            tryCompare(spectrum, "peak", 0)
            progress.bands = Array(64).fill(800)
            tryCompare(spectrum, "peak", .8)
            progress.glassEnabled = false
            compare(spectrum.useRibbon, false)
            progress.playing = false
            tryCompare(spectrum, "peak", 0)
            progress.bands = Array(64).fill(1000)
            compare(spectrum.peak, 0)
            compare(progress.positionX, 204)
        }

        function pixelDelta(before, after, from, to) {
            let delta = 0
            for (let x = from; x < to; ++x) {
                for (let y = 2; y < 18; ++y)
                    delta += Math.abs(before.red(x,y) - after.red(x,y))
                        + Math.abs(before.green(x,y) - after.green(x,y))
                        + Math.abs(before.blue(x,y) - after.blue(x,y))
            }
            return delta / ((to - from) * 16 * 3)
        }

        function test_visible_spectrum_data() {
            return [{tag: "dark-ribbon", style: "wave", dark: true, glass: true},
                {tag: "light-ribbon", style: "wave", dark: false, glass: true},
                {tag: "dark-bars", style: "bars", dark: true, glass: true},
                {tag: "opaque-ribbon", style: "wave", dark: true, glass: false}]
        }

        function test_visible_spectrum(data) {
            progress.settings = {progressStyle: "plassglass", style: data.style}
            progress.glassEnabled = data.glass
            if (!data.dark) {
                background.color = "#eaf7f8"
                progress.palette = {ink: Qt.color("#19344a"), accent: Qt.color("#366da8")}
                progress.secondary = "#5167bc"
            }
            progress.fraction = .5
            progress.playing = true
            progress.bands = Array(64).fill(0)
            verify(waitForRendering(progress))
            const silence = grabImage(progress)
            progress.bands = Array(64).fill(48)
            tryVerify(() => pixelDelta(silence, grabImage(progress), 10, 193) > .4)
            const quiet = grabImage(progress)
            progress.bands = Array(64).fill(820)
            tryVerify(() => pixelDelta(quiet, grabImage(progress), 10, 193) > 5)
            const peak = grabImage(progress)
            compare(pixelDelta(silence, peak, 210, 396), 0, "Audio does not paint over the unplayed side")
        }
    }
}
