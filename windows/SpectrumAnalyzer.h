#pragma once

#include <array>
#include <complex>
#include <cstddef>
#include <utility>
#include <vector>

enum class PcmEncoding { Unsigned8, Signed16, Signed24, Signed32, Float32, Float64 };

struct SpectrumInput
{
    int sampleRate;
    std::size_t frameBytes;
    PcmEncoding encoding;
    std::vector<std::array<float, 2>> channelWeights;
};

inline constexpr std::size_t bandsPerChannel = 32;
using SpectrumBands = std::array<int, 2 * bandsPerChannel>;

class SpectrumAnalyzer
{
public:
    explicit SpectrumAnalyzer(SpectrumInput input);

    // A null packet represents silence for the given number of frames.
    void append(const void *packet, std::size_t frames);
    void clearHistory();
    SpectrumBands update();

private:
    void measure(std::size_t side);

    SpectrumInput m_input;
    std::size_t m_sampleBytes;
    std::size_t m_fftSize = 1024;
    std::size_t m_writeIndex = 0;
    bool m_dirty = false;
    std::array<std::vector<float>, 2> m_history;
    std::vector<std::size_t> m_bitOrder;
    std::vector<float> m_window;
    std::vector<std::complex<float>> m_twiddles;
    std::vector<std::complex<float>> m_fft;
    std::array<std::pair<std::size_t, std::size_t>, bandsPerChannel> m_binRanges{};
    std::array<float, SpectrumBands{}.size()> m_measured{};
    std::array<float, SpectrumBands{}.size()> m_smoothed{};
};
