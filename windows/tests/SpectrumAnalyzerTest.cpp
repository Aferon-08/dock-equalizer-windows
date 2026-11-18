#include "../SpectrumAnalyzer.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <vector>

namespace {

constexpr int sampleRate = 48000;
constexpr std::size_t frames = 8192;
constexpr double twoPi = 6.283185307179586;

float tone(double frequency, std::size_t sample)
{
    return float(0.24 * std::sin(twoPi * frequency * sample / sampleRate));
}

bool expect(bool condition, const char *message)
{
    if (!condition)
        std::fprintf(stderr, "%s\n", message);
    return condition;
}

std::size_t peak(const SpectrumBands &bands, std::size_t side)
{
    const auto start = bands.begin() + side * bandsPerChannel;
    return std::max_element(start, start + bandsPerChannel) - start;
}

bool silent(const SpectrumBands &bands)
{
    return std::all_of(bands.begin(), bands.end(), [](int value) { return value == 0; });
}

bool stereoAndSilence()
{
    SpectrumAnalyzer spectrum({sampleRate, sizeof(float) * 2, PcmEncoding::Float32,
                               {{1, 0}, {0, 1}}});
    if (!expect(silent(spectrum.update()), "Initial spectrum must be silent"))
        return false;

    std::vector<std::array<float, 2>> samples(frames);
    for (std::size_t i = 0; i < samples.size(); ++i)
        samples[i] = {tone(257.8125, i), tone(3000, i)};
    spectrum.append(samples.data(), samples.size());
    const auto stereo = spectrum.update();
    const auto left = peak(stereo, 0);
    const auto right = peak(stereo, 1);
    if (!expect(left == 9 && right == 22, "Stereo tones must peak in their corresponding bands")
            || !expect(stereo[left] > 300 && stereo[bandsPerChannel + right] > 300,
                       "Ordinary signal levels must be visible")
            || !expect(stereo[right] < 5 && stereo[bandsPerChannel + left] < 5,
                       "The tones must not leak between channels"))
        return false;

    spectrum.append(nullptr, frames);
    auto fading = spectrum.update();
    if (!expect(fading[left] > 0 && fading[left] < stereo[left], "Silence must have a release"))
        return false;
    for (int i = 0; i < 24; ++i)
        fading = spectrum.update();
    return expect(silent(fading), "The spectrum must eventually reach zero");
}

bool packedMono()
{
    // A padded frame must be consumed at the supplied stride.
    SpectrumAnalyzer spectrum({sampleRate, 4, PcmEncoding::Signed24, {{1, 1}}});
    std::vector<std::array<std::uint8_t, 4>> samples(frames);
    for (std::size_t i = 0; i < samples.size(); ++i) {
        const auto value = std::uint32_t(std::int32_t(tone(750, i) * 8388608));
        samples[i] = {std::uint8_t(value), std::uint8_t(value >> 8), std::uint8_t(value >> 16), 0xff};
    }
    spectrum.append(samples.data(), samples.size());
    const auto mono = spectrum.update();
    if (!expect(peak(mono, 0) == 15 && mono[15] > 300, "Packed PCM must decode at the frame stride")
            || !expect(std::equal(mono.begin(), mono.begin() + bandsPerChannel,
                                 mono.begin() + bandsPerChannel), "Mono must light both sides equally"))
        return false;

    spectrum.clearHistory();
    for (int i = 0; i < 24; ++i)
        spectrum.update();
    return expect(silent(spectrum.update()), "A stopped packet stream must clear its old spectrum");
}

} // namespace

int main()
{
    return stereoAndSilence() && packedMono() ? 0 : 1;
}
