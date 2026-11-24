#!/usr/bin/env python3
"""Run an actual GLES2 shader via Mesa EGL; Python only binds native APIs."""
import ctypes as c
import os
import re
import stat
import sys

I, U, P, S = c.c_int, c.c_uint, c.c_void_p, c.c_char_p
EGL_NONE, EGL_SURFACELESS_MESA = 0x3038, 0x31DD
W, H = 8, 4

def native(egl, name, result, *args):
    f = getattr(egl, name)
    f.restype, f.argtypes = result, args
    return f

def render(egl):
    address = native(egl, "eglGetProcAddress", P, S)

    def gl(name, result, *args):
        addr = address(name.encode())
        if not addr:
            raise RuntimeError(f"{name} is unavailable")
        return c.CFUNCTYPE(result, *args)(addr)

    renderer = (gl("glGetString", S, U)(0x1F01) or b"").decode(errors="replace")
    print(f"GL_RENDERER: {renderer}", flush=True)
    api = gl("glGetString", S, U)(0x1F02)
    print(f"GL_VERSION: {(api or b'').decode(errors='replace')}", flush=True)

    def shader(kind, source):
        obj = gl("glCreateShader", U, U)(kind)
        strings = (S * 1)(source)
        gl("glShaderSource", None, U, I, c.POINTER(S), P)(obj, 1, strings, None)
        gl("glCompileShader", None, U)(obj)
        ok = I()
        gl("glGetShaderiv", None, U, U, c.POINTER(I))(obj, 0x8B81, c.byref(ok))
        if not ok.value:
            log = c.create_string_buffer(2048)
            gl("glGetShaderInfoLog", None, U, I, P, P)(obj, len(log), None, log)
            raise RuntimeError(f"shader compile failed: {log.value.decode(errors='replace')}")
        return obj

    vert = shader(0x8B31, b"attribute vec2 pos; void main(){gl_Position=vec4(pos,0.,1.);}")
    frag = shader(0x8B30, b"""precision mediump float;
        void main() {
            gl_FragColor = gl_FragCoord.x < 4.0
                ? vec4(1.,0.,0.,1.) : vec4(0.,1.,0.,1.);
        }""")
    program = gl("glCreateProgram", U)()
    attach = gl("glAttachShader", None, U, U)
    attach(program, vert)
    attach(program, frag)
    gl("glBindAttribLocation", None, U, U, S)(program, 0, b"pos")
    gl("glLinkProgram", None, U)(program)
    ok = I()
    gl("glGetProgramiv", None, U, U, c.POINTER(I))(program, 0x8B82, c.byref(ok))
    if not ok.value:
        raise RuntimeError("GLES2 program link failed")
    gl("glUseProgram", None, U)(program)

    fbo, color = U(), U()
    gl("glGenFramebuffers", None, I, c.POINTER(U))(1, c.byref(fbo))
    gl("glGenRenderbuffers", None, I, c.POINTER(U))(1, c.byref(color))
    gl("glBindFramebuffer", None, U, U)(0x8D40, fbo)
    gl("glBindRenderbuffer", None, U, U)(0x8D41, color)
    gl("glRenderbufferStorage", None, U, U, I, I)(0x8D41, 0x8056, W, H)  # RGBA4
    gl("glFramebufferRenderbuffer", None, U, U, U, U)(0x8D40, 0x8CE0, 0x8D41, color)
    if gl("glCheckFramebufferStatus", U, U)(0x8D40) != 0x8CD5:
        raise RuntimeError("GLES2 framebuffer is incomplete")
    gl("glViewport", None, I, I, I, I)(0, 0, W, H)
    vertices = (c.c_float * 6)(-1, -1, 3, -1, -1, 3)
    gl("glVertexAttribPointer", None, U, I, U, c.c_ubyte, I, P)(0, 2, 0x1406, 0, 0, vertices)
    gl("glEnableVertexAttribArray", None, U)(0)
    gl("glDrawArrays", None, U, I, I)(4, 0, 3)
    data = (c.c_ubyte * (4 * W * H))()
    gl("glReadPixels", None, I, I, I, I, U, U, P)(0, 0, W, H, 0x1908, 0x1401, data)
    err = gl("glGetError", U)()
    if err:
        raise RuntimeError(f"GLES2 error 0x{err:04x}")
    actual = bytes(data)
    if actual != (bytes((255, 0, 0, 255)) * 4 + bytes((0, 255, 0, 255)) * 4) * H:
        raise RuntimeError("GLES2 shader/readback returned unexpected pixels")
    print("GLES2 shader/FBO/readback: PASS (8x4 RGBA)", flush=True)
    return renderer

def adapter_from_renderer(renderer):
    match = re.fullmatch(r"D3D12 \((.+)\)", renderer.strip(), flags=re.I)
    if not match:
        return None
    adapter = match[1].strip()
    if re.search(r"warp|microsoft basic|software|llvmpipe|softpipe|unknown",
                 adapter, flags=re.I):
        return None
    return adapter

def main():
    egl = c.CDLL("libEGL.so.1")
    get_error = native(egl, "eglGetError", U)
    display = native(egl, "eglGetPlatformDisplay", P, U, P, P)(EGL_SURFACELESS_MESA, None, None)
    major, minor = I(), I()
    if not display or not native(egl, "eglInitialize", U, P, c.POINTER(I), c.POINTER(I))(
            display, c.byref(major), c.byref(minor)):
        raise RuntimeError(f"surfaceless eglInitialize failed (0x{get_error():04x})")
    terminate = native(egl, "eglTerminate", U, P)
    context, surface = None, None
    make_current = native(egl, "eglMakeCurrent", U, P, P, P, P)
    try:
        print(f"EGL: {major.value}.{minor.value} (surfaceless platform)")
        if not native(egl, "eglBindAPI", U, U)(0x30A0):
            raise RuntimeError("eglBindAPI(EGL_OPENGL_ES_API) failed")
        choose = native(egl, "eglChooseConfig", U, P, c.POINTER(I), c.POINTER(P), I, c.POINTER(I))
        attrs = (I * 5)(0x3033, 1, 0x3040, 4, EGL_NONE)  # PBUFFER_BIT, OPENGL_ES2_BIT
        count, config = I(), P()
        if not choose(display, attrs, c.byref(config), 1, c.byref(count)) or count.value != 1:
            raise RuntimeError("No GLES2 EGL pbuffer config")
        context = native(egl, "eglCreateContext", P, P, P, P, c.POINTER(I))(
            display, config, None, (I * 3)(0x3098, 2, EGL_NONE))
        surface = native(egl, "eglCreatePbufferSurface", P, P, P, c.POINTER(I))(
            display, config, (I * 5)(0x3057, W, 0x3056, H, EGL_NONE))
        if not context or not surface or not make_current(display, surface, surface, context):
            raise RuntimeError(f"EGL context/pbuffer could not be made current (0x{get_error():04x})")
        renderer = render(egl)
    finally:
        make_current(display, None, None, None)
        if surface:
            native(egl, "eglDestroySurface", U, P, P)(display, surface)
        if context:
            native(egl, "eglDestroyContext", U, P, P)(display, context)
        terminate(display)
    adapter = adapter_from_renderer(renderer)
    if not adapter:
        print("D3D12 adapter criterion: FAIL (not a named, non-software D3D12 adapter)", file=sys.stderr)
        return 2
    try:
        dxg = stat.S_ISCHR(os.stat("/dev/dxg").st_mode)
    except OSError:
        dxg = False
    if not dxg:
        print("D3D12 adapter criterion: FAIL (/dev/dxg is not a character device)", file=sys.stderr)
        return 2
    print(f"D3D12 adapter criterion: PASS (driver reports {adapter}; /dev/dxg present)")
    print("Not tested: Shady, wl_shm transport, or WSLg window presentation. Confirm the adapter independently.")
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, OSError, AttributeError) as e:
        print(f"FAIL: {e}", file=sys.stderr)
        sys.exit(1)
