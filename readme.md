# MyIntelGPU — Native Intel Gen 10–12 iGPU Driver for Hackintosh

Standalone macOS IOKit kernel extension that drives Intel Gen 10–12 integrated GPUs
(Xe-LP / Raptor Lake-U, e.g. `8086:A7AC` — Core 5 120U, 80 EU) — hardware Apple
never shipped a driver for.

**No Lilu. No WhateverGreen. No OpenCore injection.** Pure native driver loaded
from `/Library/Extensions`.

> **Version:** 4.4.149 · **Bundle ID:** `com.pongpan-bk.MyIntelGPU`
> **Tested on:** iMac20,1 · macOS Sonoma 14.8.9 (23J631)

## Status

| Layer | Status |
|---|---|
| PCI setup / MMIO (BAR0 regs / BAR2 aperture) | ✅ |
| Display / IOFramebuffer (1920x1080 FHD, backlight) | ✅ — W2-1 cross-connect proven |
| RCS / BCS / VCS rings + execlists submission | ✅ |
| PPGTT identity mapping (GEM buffers) | ✅ |
| Media engines (VDBOX / VEBOX detect via `0x138010`) | ✅ |
| **H.264 hardware decode (VDBOX writes NV12 pixels)** | ✅ **proven** |
| ExecBatch / WaitBatch / RingStatus client API | ✅ |
| GPU render (Metal) | ⏳ opt-in (`myintelaccel=1/2`), not yet proven |

## Hardware decode proof

```
[READBACK] probe=20480 poison(0xA5)=2091 zero=0 other=18389
[READBACK] => HW เขียนพิกเซลจริง! decode สำเร็จ
[SRC-COHERENCE] aperture vs CPU: MATCH ✅
[PIPELINE] scratch 1531 bytes ← VDBOX เขียน!
[DUMP] wrote 18432 bytes → NV12 128x96
```

The kext speaks the Intel MFX command set directly to the VDBOX engine via the VCS
ring — bypassing VideoToolbox entirely. Apple's private IOGPU protocol is
undocumented, and Apple never wrote a Gen12 driver, so the KBL/Gen9 spoof route is
a crash generator, not a shortcut.

Golden reference dumps from Linux `i915` and the Windows Intel driver live in
`ubuntu-gold/` (register dumps, NV12 frames, MD5 manifest).

## Boot-args

| Flag | Effect |
|---|---|
| `myintelfb=1` | Let `MyIntelFramebuffer` own the real panel (EDID `2c82`/`0924`) |
| `myinteldisplaypipe=1` | Attach the display pipe (W2-1 cross-connect path) |
| `myintelaccel=1` | Opt-in accelerator / IOAccelerator path under `MyIntelGPU` node — **risky on Gen12** |
| `myintelaccel=2` | Opt-in accelerator under PCI device topology (Apple-style), often better for probing Metal on ADL-P/i3-1220P |

> ⚠️ `myintelaccel=1` binds the `AppleIntelKBLGraphics` Metal/GL plugin against
> Gen12 registers. Known panic vectors: `stack_chk_fail`, `IOGMD: not wired`.
> Keep a rescue EFI with a safe 2-flag config (`myintelfb` + `myinteldisplaypipe`)
> before testing.

## Build

```bash
make KERNEL_SDK_DIR=/Users/ppbk/MacKernelSDK clean
make KERNEL_SDK_DIR=/Users/ppbk/MacKernelSDK -j$(sysctl -n hw.ncpu)
```

## Deploy (L/E only — never OpenCore)

```bash
sudo rm -rf /Library/Extensions/MyIntelGPU.kext
sudo cp -R MyIntelGPU.kext /Library/Extensions/
sudo chown -R root:wheel /Library/Extensions/MyIntelGPU.kext
sudo chmod -R 755 /Library/Extensions/MyIntelGPU.kext
sudo codesign -s - --force /Library/Extensions/MyIntelGPU.kext
sudo kmutil install --volume-root /
# reboot, then check:
kextstat | grep pongpan
```

> ⚠️ Do NOT inject via OpenCore `Kernel:Add` or spoof device-id in
> `DeviceProperties` — the kext matches the real PCI class itself.

**Iron rules:** backup → build → deploy → **reboot** → verify. Never reboot
mid-deploy. Keep a bootable rescue path before any risky boot-args change.

## Test

VCS decode harness (proves VDBOX writes real pixels):

```bash
clang++ -x objective-c++ -std=c++14 -O2 \
  -framework IOKit -framework CoreFoundation -framework Foundation \
  test_submit_vcs.m MyIntelVCSCommand.cpp -o /tmp/vcs_test_harness
/tmp/vcs_test_harness test_clip.h264 /tmp/vcs_test_out.nv12
```

## Client API (IOUserClient selectors)

| Sel | Name | Purpose |
|---|---|---|
| 0–11 | legacy GEM/ring/readback | buffer mgmt, submit proof batches |
| 12 | `ExecBatch` | submit caller-authored command stream (i915 execbuffer) |
| 13 | `WaitBatch` | poll HWSP seqno fence |
| 14 | `RingStatus` | head/tail/space/pending telemetry |
| 20–24 | accelerator step machine | IOAccelerator adoption path |

## Architecture

```
Userspace (harness / VideoToolbox-bypass)
    │ IOConnectCall
    ▼
MyIntelVCSClient (IOUserClient) ── GEM buffers, PPGTT identity map
    ▼
MyIntelRing (execlists ELSP) ── BB_START → flush → USER_INTERRUPT
    ▼
VDBOX / VCS0 engine (MFX command stream, Gen12)
```

Source layout: `MyIntelGPU.cpp` (core/rings), `MyIntelVCSClient.cpp` (client),
`MyIntelVCSCommand.cpp` (Gen12 MFX builders), `MyIntelMedia.cpp` (engine detect),
`MyIntelAccelerator.cpp` (IOAccelerator attempt), `MyIntelRing.cpp` (ring/PPGTT),
`MyIntelFramebuffer.cpp` (display / W2-1).

## Hardware ground truth

- **iGPU:** Intel Raptor Lake-U `8086:a7ac` rev 04, 80 EU (Iris Xe), subsystem `1025:192e`
- **BAR0** = 16 MB MMIO regs · **BAR2** = 256 MB aperture / GMADR
- **Display:** eDP panel @ 1920x1080 (FHD), W2-1 cross-connect
  (`kIOFBDependentIDKey = 0x1000004DB`, `kConnectionFlags = 0x800` built-in)

## License & disclaimer

Research / experimental driver. Use at your own risk — kernel extensions can
panic your machine. Always keep a bootable rescue path.
