#!/usr/bin/env python3
"""Patch the legacy cash-payment route out of both ARM libgame.so builds.

The runtime bridge later replaces PriceManager::pay with a guarded barter hook
on armeabi-v7a. The static return patch is deliberately fail-closed for devices
that cannot load the optional JNI bridge.
"""
from __future__ import annotations

import os
import struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB_DIR = os.path.join(ROOT, "kingdom-in-chaos-decompiled", "lib")

# Offsets are verified against the bundled ARMv7 libgame.so symbol table and
# original instruction bytes. The same layout is present in armeabi.
PATCHES = {
    0x2B98FC: (
        bytes.fromhex("f0 b5 4f 46 46 46 c0 b4"),
        bytes.fromhex("70 47 00 bf 00 bf 00 bf"),
        "disable legacy Google/real-money purchase entry",
    ),
    0x2BD298: (
        bytes.fromhex("ea f7 cc ff"),
        bytes.fromhex("00 bf 00 bf"),
        "disable legacy cash-payment network recording",
    ),
    0x2BD416: (
        bytes.fromhex("c1 f7 2b ff"),
        bytes.fromhex("00 bf 00 bf"),
        "disable paid-purchase analytics",
    ),
}


def thumb_bl(site: int, target: int) -> bytes:
    """Encode a Thumb-2 BL instruction from one file address to another."""
    offset = target - (site + 4)
    if offset & 1 or not -(1 << 24) <= offset < (1 << 24):
        raise ValueError(f"Thumb BL target out of range: {site:#x} -> {target:#x}")
    imm = offset & 0x01FFFFFF
    s = (imm >> 24) & 1
    i1 = (imm >> 23) & 1
    i2 = (imm >> 22) & 1
    imm10 = (imm >> 12) & 0x3FF
    imm11 = (imm >> 1) & 0x7FF
    j1 = (~(i1 ^ s)) & 1
    j2 = (~(i2 ^ s)) & 1
    half1 = 0xF000 | (s << 10) | imm10
    half2 = 0xD000 | (j1 << 13) | (j2 << 11) | imm11
    return struct.pack("<HH", half1, half2)


def replace_exact(data: bytearray, offset: int, original: bytes,
                  replacement: bytes, description: str) -> None:
    actual = bytes(data[offset:offset + len(original)])
    if actual == replacement:
        return
    if actual != original:
        raise RuntimeError(
            f"Unexpected bytes at {offset:#x} ({description}): {actual.hex(' ')}"
        )
    data[offset:offset + len(replacement)] = replacement


def patch_library(path: str) -> None:
    with open(path, "rb") as stream:
        data = bytearray(stream.read())

    for offset, (original, replacement, description) in PATCHES.items():
        replace_exact(data, offset, original, replacement, description)

    # onPaidOK must still deliver the original item/VIP reward, but its old
    # money-purchase success toast is replaced by the generic reward toast.
    toast_site = 0x2BD41E
    toast_original = bytes.fromhex("1f f0 81 fd")
    toast_replacement = thumb_bl(toast_site, 0x2DCDF0)
    replace_exact(data, toast_site, toast_original, toast_replacement,
                  "replace cash success toast with generic game reward toast")

    with open(path, "wb") as stream:
        stream.write(data)


def main() -> None:
    patched = []
    for abi in ("armeabi", "armeabi-v7a"):
        path = os.path.join(LIB_DIR, abi, "libgame.so")
        if not os.path.isfile(path):
            raise SystemExit(f"Missing native library: {path}")
        patch_library(path)
        patched.append(path)
    for path in patched:
        print(f"Patched {os.path.relpath(path, ROOT)}")


if __name__ == "__main__":
    main()
