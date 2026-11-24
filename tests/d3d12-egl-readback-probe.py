"""Adapter classification regressions, separate from real EGL execution."""
import runpy
from pathlib import Path

path = Path(__file__).resolve().parents[1] / "samples" / "probe-d3d12-egl-readback.py"
classify = runpy.run_path(str(path))["adapter_from_renderer"]
assert classify("D3D12 (NVIDIA RTX A4000)") == "NVIDIA RTX A4000"
for name in (
    "llvmpipe (LLVM 19.1.7, 256 bits)", "softpipe", "D3D12 (WARP)",
    "D3D12 (Microsoft Basic Render Driver)", "D3D12 (Unknown)",
    "D3D12 (Software Adapter)", "",
):
    assert classify(name) is None, name
print("D3D12 adapter classification fixtures passed")
