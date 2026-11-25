from pathlib import Path
import argparse
import csv
import numpy as np
from scipy import signal
import soundfile as sf
from design_feedback import RATE, fixed_window_db

PALETTES = (("Classic", ""), ("Studio latch", "studio-"), ("Felt thud", "felt-"), ("Porcelain", "porcelain-"), ("Soft click", "soft-"))

def measure(samples):
    energy = np.cumsum(samples ** 2)
    spectrum = abs(np.fft.rfft(samples, 8192)) ** 2
    frequencies = np.fft.rfftfreq(8192, 1 / RATE)
    first = np.flatnonzero(abs(samples) > abs(samples).max() * .01)[0]
    peak = abs(signal.resample_poly(samples, 4, 1)).max()
    return {
        "duration_ms": round(1000 * len(samples) / RATE, 1),
        "onset_1pct_ms": round(1000 * first / RATE, 2),
        "peak_at_ms": round(1000 * np.argmax(abs(samples)) / RATE, 2),
        "energy_90pct_ms": round(1000 * np.searchsorted(energy, .9 * energy[-1]) / RATE, 1),
        "centroid_hz": round(np.average(frequencies, weights=spectrum)),
        "energy_above_4khz_pct": round(100 * spectrum[frequencies > 4000].sum() / spectrum.sum(), 2),
        "kw_100ms_dbfs": round(fixed_window_db(samples), 1),
        "true_peak_db_4x": round(20 * np.log10(peak), 1),
    }

def main():
    parser = argparse.ArgumentParser(description="Measure the shipped mono PCM cues and render a level-matched listening reel.")
    parser.add_argument("sounds", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    reel = np.zeros(round(1.5 * len(PALETTES) * RATE))
    rows = []
    for index, (label, prefix) in enumerate(PALETTES):
        for edge, target_db, offset in (("engage", -34, 0), ("release", -36, .43)):
            samples, rate = sf.read(args.sounds / f"{prefix}{edge}.wav")
            if rate != RATE or samples.ndim != 1:
                raise ValueError("Expected 44.1 kHz mono WAV")
            rows.append({"palette": label, "cue": edge, **measure(samples)})
            adjusted = samples * 10 ** ((target_db - fixed_window_db(samples)) / 20)
            start = round((index * 1.5 + offset) * RATE)
            reel[start:start + len(samples)] = adjusted
    with (args.output / "all-sound-measurements.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
    sf.write(args.output / "all-five-pairs.wav", reel, RATE, subtype="PCM_16")

if __name__ == "__main__":
    main()
