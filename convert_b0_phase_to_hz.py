#!/usr/bin/env python3

"""Convert an unwrapped dual-echo phase-difference image from radians to Hz."""

import argparse
import json
import math
from pathlib import Path

import nibabel as nib
import numpy as np


def parse_args():
    parser = argparse.ArgumentParser(
        description="Convert unwrapped phase difference to B0 frequency offset in Hz."
    )
    parser.add_argument("--unwrapped", type=Path, required=True)
    parser.add_argument("--echo1-json", type=Path, required=True)
    parser.add_argument("--echo2-json", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--output-json", type=Path, required=True)
    return parser.parse_args()


def read_echo_time(path):
    metadata = json.loads(path.read_text(encoding="utf-8"))
    try:
        echo_time = float(metadata["EchoTime"])
    except (KeyError, TypeError, ValueError) as error:
        raise SystemExit(f"Missing or invalid EchoTime in {path}") from error
    if not math.isfinite(echo_time) or echo_time <= 0:
        raise SystemExit(f"EchoTime must be positive in {path}: {echo_time}")
    return echo_time


def main():
    args = parse_args()
    echo_time1 = read_echo_time(args.echo1_json)
    echo_time2 = read_echo_time(args.echo2_json)
    delta_echo_time = echo_time2 - echo_time1
    if delta_echo_time <= 0:
        raise SystemExit(
            f"EchoTime2 must exceed EchoTime1: {echo_time2} <= {echo_time1}"
        )

    image = nib.load(str(args.unwrapped))
    phase_radians = image.get_fdata(dtype=np.float32)
    frequency_hz = phase_radians / (2.0 * np.pi * delta_echo_time)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    header = image.header.copy()
    header.set_data_dtype(np.float32)
    header["descrip"] = b"B0 frequency offset (Hz)"
    nib.save(
        nib.Nifti1Image(frequency_hz.astype(np.float32), image.affine, header),
        str(args.output),
    )

    provenance = {
        "Units": "Hz",
        "EchoTime1": echo_time1,
        "EchoTime2": echo_time2,
        "EchoTimeDifference": delta_echo_time,
        "ConversionFormula": "frequency_hz = unwrapped_phase_radians / (2*pi*EchoTimeDifference_seconds)",
        "Sources": {
            "UnwrappedPhase": str(args.unwrapped.resolve()),
            "Echo1Metadata": str(args.echo1_json.resolve()),
            "Echo2Metadata": str(args.echo2_json.resolve()),
        },
    }
    args.output_json.write_text(
        json.dumps(provenance, indent=2) + "\n", encoding="utf-8"
    )
    scale = 1.0 / (2.0 * np.pi * delta_echo_time)
    print(f"EchoTimeDifference: {delta_echo_time * 1000.0:.3f} ms")
    print(f"Scale: {scale:.6f} Hz/radian")
    print(f"Saved: {args.output.resolve()}")
    print(f"Saved: {args.output_json.resolve()}")


if __name__ == "__main__":
    main()
