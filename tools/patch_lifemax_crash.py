#!/usr/bin/env python3
"""Fail-safe patch for the achievement-claim SIGSEGV in LifeMax().

The supplied crash report identifies the failing native call chain as
UIAchieveLayer::onAward -> LifeMax -> native float/config conversion. The
current game UI and Life system use a maximum of 24. This patch replaces only
LifeMax's entry with `movs r0, #24; bx lr`, avoiding the failing config path.
It is deliberately exact-byte checked and idempotent for both bundled ARM ABIs.
"""
from __future__ import annotations
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB_DIR = os.path.join(ROOT, "kingdom-in-chaos-decompiled", "lib")
OFFSET = 0x305330
ORIGINAL = bytes.fromhex("30 b5 85 b0")  # push {r4,r5,lr}; sub sp,#0x14
PATCHED = bytes.fromhex("18 20 70 47")   # movs r0,#24; bx lr (Thumb)


def patch(path: str) -> None:
    with open(path, "rb") as f:
        data = bytearray(f.read())
    current = bytes(data[OFFSET:OFFSET + 4])
    if current == PATCHED:
        return
    if current != ORIGINAL:
        raise RuntimeError(
            f"Unexpected LifeMax bytes in {path} at {OFFSET:#x}: {current.hex(' ')}"
        )
    data[OFFSET:OFFSET + 4] = PATCHED
    with open(path, "wb") as f:
        f.write(data)


def main() -> None:
    for abi in ("armeabi", "armeabi-v7a"):
        path = os.path.join(LIB_DIR, abi, "libgame.so")
        if not os.path.isfile(path):
            raise SystemExit(f"Missing native library: {path}")
        patch(path)
        print(f"Patched LifeMax crash guard: {os.path.relpath(path, ROOT)}")

if __name__ == "__main__":
    main()
