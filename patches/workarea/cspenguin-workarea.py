#!/usr/bin/env python3
# Measure the work area of window managers that don't publish it to X11 (COSMIC).
#
# A transparent, undecorated dummy window is maximized by the window manager, and
# the space it leaves on each side (panels, docks) is applied to every monitor
# (the window manager picks the monitor; COSMIC panels are shared by all outputs).
# Prints the work areas in _GTK_WORKAREAS_D0 format: "x, y, w, h, x, y, w, h, ..."
# Only uses the Python standard library (ctypes) and libX11/libXrandr.
import ctypes as C
import ctypes.util
import sys
import time

X = C.CDLL(ctypes.util.find_library("X11"))
Xr = C.CDLL(ctypes.util.find_library("Xrandr"))

X.XOpenDisplay.restype = C.c_void_p
X.XDefaultRootWindow.restype = C.c_ulong
X.XDefaultRootWindow.argtypes = [C.c_void_p]
X.XDefaultScreen.argtypes = [C.c_void_p]
X.XInternAtom.restype = C.c_ulong
X.XInternAtom.argtypes = [C.c_void_p, C.c_char_p, C.c_int]
X.XCreateWindow.restype = C.c_ulong
X.XCreateWindow.argtypes = [C.c_void_p, C.c_ulong, C.c_int, C.c_int, C.c_uint, C.c_uint, C.c_uint,
                            C.c_int, C.c_uint, C.c_void_p, C.c_ulong, C.c_void_p]
X.XCreateColormap.restype = C.c_ulong
X.XCreateColormap.argtypes = [C.c_void_p, C.c_ulong, C.c_void_p, C.c_int]
X.XChangeProperty.argtypes = [C.c_void_p, C.c_ulong, C.c_ulong, C.c_ulong, C.c_int, C.c_int, C.c_void_p, C.c_int]
X.XMapWindow.argtypes = [C.c_void_p, C.c_ulong]
X.XDestroyWindow.argtypes = [C.c_void_p, C.c_ulong]
X.XSync.argtypes = [C.c_void_p, C.c_int]
X.XFlush.argtypes = [C.c_void_p]
X.XSetWMNormalHints.argtypes = [C.c_void_p, C.c_ulong, C.c_void_p]
X.XTranslateCoordinates.argtypes = [C.c_void_p, C.c_ulong, C.c_ulong, C.c_int, C.c_int,
                                    C.POINTER(C.c_int), C.POINTER(C.c_int), C.POINTER(C.c_ulong)]
X.XGetGeometry.argtypes = [C.c_void_p, C.c_ulong, C.POINTER(C.c_ulong), C.POINTER(C.c_int), C.POINTER(C.c_int),
                           C.POINTER(C.c_uint), C.POINTER(C.c_uint), C.POINTER(C.c_uint), C.POINTER(C.c_uint)]
X.XGetWindowProperty.argtypes = [C.c_void_p, C.c_ulong, C.c_ulong, C.c_long, C.c_long, C.c_int, C.c_ulong,
                                 C.POINTER(C.c_ulong), C.POINTER(C.c_int), C.POINTER(C.c_ulong),
                                 C.POINTER(C.c_ulong), C.POINTER(C.c_void_p)]
X.XFree.argtypes = [C.c_void_p]


class XVisualInfo(C.Structure):
    _fields_ = [("visual", C.c_void_p), ("visualid", C.c_ulong), ("screen", C.c_int), ("depth", C.c_int),
                ("class", C.c_int), ("red_mask", C.c_ulong), ("green_mask", C.c_ulong), ("blue_mask", C.c_ulong),
                ("colormap_size", C.c_int), ("bits_per_rgb", C.c_int)]


class XSetWindowAttributes(C.Structure):
    _fields_ = [("background_pixmap", C.c_ulong), ("background_pixel", C.c_ulong),
                ("border_pixmap", C.c_ulong), ("border_pixel", C.c_ulong), ("bit_gravity", C.c_int),
                ("win_gravity", C.c_int), ("backing_store", C.c_int), ("backing_planes", C.c_ulong),
                ("backing_pixel", C.c_ulong), ("save_under", C.c_int), ("event_mask", C.c_long),
                ("do_not_propagate_mask", C.c_long), ("override_redirect", C.c_int), ("colormap", C.c_ulong),
                ("cursor", C.c_ulong)]


class XSizeHints(C.Structure):
    _fields_ = [("flags", C.c_long), ("x", C.c_int), ("y", C.c_int), ("width", C.c_int), ("height", C.c_int),
                ("min_width", C.c_int), ("min_height", C.c_int), ("max_width", C.c_int), ("max_height", C.c_int),
                ("width_inc", C.c_int), ("height_inc", C.c_int), ("min_aspect", C.c_int * 2),
                ("max_aspect", C.c_int * 2), ("base_width", C.c_int), ("base_height", C.c_int),
                ("win_gravity", C.c_int)]


class XRRMonitorInfo(C.Structure):
    _fields_ = [("name", C.c_ulong), ("primary", C.c_int), ("automatic", C.c_int), ("noutput", C.c_int),
                ("x", C.c_int), ("y", C.c_int), ("width", C.c_int), ("height", C.c_int),
                ("mwidth", C.c_int), ("mheight", C.c_int), ("outputs", C.c_void_p)]


X.XMatchVisualInfo.argtypes = [C.c_void_p, C.c_int, C.c_int, C.c_int, C.POINTER(XVisualInfo)]
Xr.XRRGetMonitors.restype = C.POINTER(XRRMonitorInfo)
Xr.XRRGetMonitors.argtypes = [C.c_void_p, C.c_ulong, C.c_int, C.POINTER(C.c_int)]

USPosition, USSize, PPosition, PSize = 1, 2, 4, 8
CWBackPixel, CWBorderPixel, CWColormap = 1 << 1, 1 << 3, 1 << 13
XA_ATOM, XA_CARDINAL = 4, 6
TrueColor, InputOutput = 4, 1


def geometry(d, root, w):
    x, y, child = C.c_int(), C.c_int(), C.c_ulong()
    X.XTranslateCoordinates(d, w, root, 0, 0, C.byref(x), C.byref(y), C.byref(child))
    r, gx, gy, gw, gh, b, dp = C.c_ulong(), C.c_int(), C.c_int(), C.c_uint(), C.c_uint(), C.c_uint(), C.c_uint()
    X.XGetGeometry(d, w, C.byref(r), C.byref(gx), C.byref(gy), C.byref(gw), C.byref(gh), C.byref(b), C.byref(dp))
    return x.value, y.value, gw.value, gh.value


def is_maximized(d, w, atom_state, atom_vert):
    typ, fmt, n, rem, data = C.c_ulong(), C.c_int(), C.c_ulong(), C.c_ulong(), C.c_void_p()
    if X.XGetWindowProperty(d, w, atom_state, 0, 32, 0, XA_ATOM, C.byref(typ), C.byref(fmt), C.byref(n),
                            C.byref(rem), C.byref(data)) != 0 or not data.value:
        return False
    atoms = C.cast(data, C.POINTER(C.c_ulong))
    found = any(atoms[i] == atom_vert for i in range(n.value))
    X.XFree(data)
    return found


def probe(d, root, mon, vinfo, cmap, atoms):
    attr = XSetWindowAttributes()
    attr.background_pixel = 0  # fully transparent ARGB
    attr.border_pixel = 0
    attr.colormap = cmap
    w = X.XCreateWindow(d, root, mon.x + mon.width // 4, mon.y + mon.height // 4, mon.width // 2, mon.height // 2,
                        0, vinfo.depth, InputOutput, vinfo.visual, CWBackPixel | CWBorderPixel | CWColormap,
                        C.byref(attr))
    hints = XSizeHints()
    hints.flags = USPosition | USSize | PPosition | PSize
    hints.x, hints.y = mon.x + mon.width // 4, mon.y + mon.height // 4
    hints.width, hints.height = mon.width // 2, mon.height // 2
    X.XSetWMNormalHints(d, w, C.byref(hints))
    state = (C.c_ulong * 4)(atoms["vert"], atoms["horz"], atoms["skip_taskbar"], atoms["skip_pager"])
    X.XChangeProperty(d, w, atoms["state"], XA_ATOM, 32, 0, state, 4)  # PropModeReplace
    wtype = (C.c_ulong * 1)(atoms["normal"])
    X.XChangeProperty(d, w, atoms["type"], XA_ATOM, 32, 0, wtype, 1)
    # undecorated like CSP: flags=MWM_HINTS_DECORATIONS, decorations=0
    mwm = (C.c_ulong * 5)(2, 0, 0, 0, 0)
    X.XChangeProperty(d, w, atoms["mwm"], atoms["mwm"], 32, 0, mwm, 5)
    opacity = (C.c_ulong * 1)(0)
    X.XChangeProperty(d, w, atoms["opacity"], XA_CARDINAL, 32, 0, opacity, 1)
    X.XMapWindow(d, w)
    X.XSync(d, 0)

    result = None
    deadline = time.time() + 2.0
    while time.time() < deadline:
        time.sleep(0.05)
        X.XSync(d, 0)
        g = geometry(d, root, w)
        if is_maximized(d, w, atoms["state"], atoms["vert"]) and g[2] > mon.width // 2:
            # give the window manager a moment to settle the final size
            time.sleep(0.1)
            X.XSync(d, 0)
            result = geometry(d, root, w)
            break
    X.XDestroyWindow(d, w)
    X.XSync(d, 0)
    return result


def main():
    d = X.XOpenDisplay(None)
    if not d:
        return 1
    root = X.XDefaultRootWindow(d)
    screen = X.XDefaultScreen(d)
    vinfo = XVisualInfo()
    if not X.XMatchVisualInfo(d, screen, 32, TrueColor, C.byref(vinfo)):
        return 1
    cmap = X.XCreateColormap(d, root, vinfo.visual, 0)
    atoms = {k: X.XInternAtom(d, v, 0) for k, v in {
        "state": b"_NET_WM_STATE", "vert": b"_NET_WM_STATE_MAXIMIZED_VERT",
        "horz": b"_NET_WM_STATE_MAXIMIZED_HORZ", "skip_taskbar": b"_NET_WM_STATE_SKIP_TASKBAR",
        "skip_pager": b"_NET_WM_STATE_SKIP_PAGER", "type": b"_NET_WM_WINDOW_TYPE",
        "normal": b"_NET_WM_WINDOW_TYPE_NORMAL", "opacity": b"_NET_WM_WINDOW_OPACITY",
        "mwm": b"_MOTIF_WM_HINTS"}.items()}

    n = C.c_int()
    mons = Xr.XRRGetMonitors(d, root, 1, C.byref(n))
    mons = [mons[i] for i in range(n.value)]
    if not mons:
        return 2
    g = probe(d, root, mons[0], vinfo, cmap, atoms)
    if g is None:
        print("probe failed", file=sys.stderr)
        return 2
    x, y, w, h = g
    home = next((m for m in mons if m.x <= x < m.x + m.width and m.y <= y < m.y + m.height), None)
    if home is None:
        print(f"maximized window outside of every monitor ({g})", file=sys.stderr)
        return 3
    left, top = x - home.x, y - home.y
    right, bottom = home.x + home.width - (x + w), home.y + home.height - (y + h)
    if min(left, top, right, bottom) < 0:
        print(f"maximized window larger than its monitor ({g})", file=sys.stderr)
        return 3
    print(f"insets: left {left}, top {top}, right {right}, bottom {bottom}", file=sys.stderr)
    out = []
    for m in mons:
        out += [m.x + left, m.y + top, m.width - left - right, m.height - top - bottom]
    print(", ".join(str(v) for v in out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
