#!/usr/bin/env python3
"""Where the keyboard's taps went, from the Debug trace (device round 4).

A Debug build of the keyboard appends to kalam-trace.log in the App Group container: a "spy" line
for every touch the keyboard's window got (Debug/TouchSpy.swift) and a "touch" line for every touch
the keys got, with the same touch id. This matches them up for the last time the keyboard appeared
and prints a short report to paste back.

    python3 Tools/touch-report/touch_report.py --device "<iPhone name>"   # pulls the trace first
    python3 Tools/touch-report/touch_report.py kalam-trace.log [--all]

`xcrun devicectl list devices` shows the iPhone's name.
"""

import argparse
import re
import statistics
import subprocess
import sys
import tempfile
from collections import Counter
from dataclasses import dataclass, field

APP_GROUP = "group.com.morad.kalam"
TRACE_PATH = "Library/Caches/kalam-trace.log"

LINE = re.compile(r"^(\d+(?:\.\d+)?) (.*)$")
SPY = re.compile(r"^spy (began|ended|cancelled) at (-?[\d.]+),(-?[\d.]+) in (\S+) lag (-?[\d.]+) ms id (\S+) recognizers ?(.*)$")
TOUCH = re.compile(r"^touch (began|ended|cancelled) (\S+) at (-?[\d.]+),(-?[\d.]+) lag (-?[\d.]+) ms id (\S+)$")
SUDDEN = re.compile(r"^sudden move from (\S+), ")
COMMIT = re.compile(r'^commit "(.*)"$')
KEY_UP = re.compile(r"^keyUp (\S+)$")
AUTOCORRECT = re.compile(r'^commitWord "(.*?)" -> "(.*?)" delete')
VIEW = re.compile(r"^view began id (\S+)$")

# A spy line and the key line for the same touch are written in the same event, a few ms apart.
MATCH_WINDOW_MS = (-20.0, 100.0)
# The key view's own touchesBegan can come later: the window's system recognizers may hold it back.
VIEW_WINDOW_MS = (-20.0, 1500.0)
# A "sudden move" line is followed by its landing's "touch began" within the same event.
LANDING_WINDOW_MS = 10.0
# Kalam's views whose touches the keys never see, by design: the suggestion bar and its buttons (or
# the globe), and the emoji and clipboard panels. A touch anywhere else that no key got was lost.
NOT_KEYS = {"SuggestionBar", "UIButton", "EmojiPanel", "ClipboardPanel", "UICollectionView", "EmojiCell", "ClipTile"}


@dataclass
class Spy:
    time: float
    phase: str
    x: float
    y: float
    view: str
    lag: float
    id: str
    recognizers: list


@dataclass
class KeyTouch:
    time: float
    key: str
    lag: float
    id: str
    landing: bool = False
    matched: bool = False


@dataclass
class Session:
    start: float = 0.0
    end: float = 0.0
    spies: list = field(default_factory=list)
    keys: list = field(default_factory=list)
    views: list = field(default_factory=list)  # (time, id) of the key view's own touchesBegan
    typed: list = field(default_factory=list)
    autocorrects: list = field(default_factory=list)
    gestures: list = field(default_factory=list)
    cancelled: int = 0
    dropped: int = 0


def unescape(text):
    """Swift's debugDescription escapes, enough for typed text."""
    text = re.sub(r"\\u\{([0-9a-fA-F]+)\}", lambda m: chr(int(m.group(1), 16)), text)
    return text.replace('\\"', '"').replace("\\n", "\n").replace("\\t", "\t").replace("\\\\", "\\")


def last_session(lines, everything=False):
    """The lines since the keyboard last appeared: its view chain ("frame" and "gesture" lines) opens each one."""
    if everything:
        return lines
    starts = [i for i, (_, text) in enumerate(lines) if text.startswith("frame ")]
    if not starts:
        return lines
    i = starts[-1]
    while i > 0 and lines[i - 1][1].startswith(("frame ", "gesture ")):
        i -= 1
    return lines[i:]


def parse(text, everything=False):
    lines = []
    for raw in text.splitlines():
        m = LINE.match(raw)
        if m:
            lines.append((float(m.group(1)), m.group(2)))
    session = Session()
    lines = last_session(lines, everything)
    if lines:
        session.start, session.end = lines[0][0], lines[-1][0]
    landing_after = None
    for time, text in lines:
        if m := SPY.match(text):
            phase, x, y, view, lag, touch_id, recognizers = m.groups()
            session.spies.append(Spy(time, phase, float(x), float(y), view, float(lag), touch_id,
                                     [r for r in recognizers.split(",") if r]))
        elif m := TOUCH.match(text):
            phase, key, _, _, lag, touch_id = m.groups()
            if phase == "began":
                landing = landing_after is not None and time - landing_after <= LANDING_WINDOW_MS
                session.keys.append(KeyTouch(time, key, float(lag), touch_id, landing))
                landing_after = None
            elif phase == "cancelled":
                session.cancelled += 1
        elif m := VIEW.match(text):
            session.views.append((time, m.group(1)))
        elif SUDDEN.match(text):
            landing_after = time
        elif m := COMMIT.match(text):
            session.typed.append(unescape(m.group(1)))
        elif m := KEY_UP.match(text):
            session.typed.append({"space": " ", "return": "⏎"}.get(m.group(1), ""))
        elif m := AUTOCORRECT.match(text):
            session.autocorrects.append((unescape(m.group(1)), unescape(m.group(2))))
        elif text.startswith("gesture "):
            session.gestures.append(text[len("gesture "):])
        elif text.startswith("dropped "):
            session.dropped += 1
    return session


def match(session):
    """Pairs each window touch-down with the keys' touch-down of the same touch. Returns the unmatched spies."""
    unmatched = []
    for spy in (s for s in session.spies if s.phase == "began"):
        low, high = spy.time + MATCH_WINDOW_MS[0], spy.time + MATCH_WINDOW_MS[1]
        key = next((k for k in session.keys if not k.matched and not k.landing and k.id == spy.id
                    and low <= k.time <= high), None)
        if key:
            key.matched = True
        else:
            unmatched.append(spy)
    return unmatched


def percentile(values, fraction):
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(len(ordered) * fraction))]


def report(session):
    unmatched = match(session)
    began = [s for s in session.spies if s.phase == "began"]
    views = Counter(s.view for s in began)
    lost = [s for s in unmatched if s.view not in NOT_KEYS]
    landings = [k for k in session.keys if k.landing]
    unseen = [k for k in session.keys if not k.matched and not k.landing]
    out = [f"Kalam touch report: {(session.end - session.start) / 1000:.1f} s since the keyboard last appeared"]
    out.append(f"Touch-downs the keyboard's window got: {len(began)} ("
               + ", ".join(f"{view} {n}" for view, n in views.most_common()) + ")")
    out.append(f"Touch-downs the keys got: {len(session.keys) - len(landings)}"
               + f", plus {len(landings)} sudden-move landings")
    out.append(f"Window touch-downs that never reached a key: {len(lost)}")
    for spy in lost:
        ends = [s for s in session.spies if s.id == spy.id and s.phase != "began" and s.time >= spy.time]
        end = f"; {ends[0].phase} {ends[0].time - spy.time:.0f} ms later, recognizers {','.join(ends[0].recognizers)}" if ends else ""
        low, high = spy.time + VIEW_WINDOW_MS[0], spy.time + VIEW_WINDOW_MS[1]
        view = next((t for t, touch_id in session.views if touch_id == spy.id and low <= t <= high), None)
        reached = f"; the key view got it {view - spy.time:.0f} ms later, KeyTouchRecognizer didn't" if view is not None else ""
        out.append(f"  +{(spy.time - session.start) / 1000:.3f} s at {spy.x:.1f},{spy.y:.1f} in {spy.view}, "
                   + f"lag {spy.lag:.1f} ms, recognizers {','.join(spy.recognizers)}{end}{reached}")
    if unseen:
        out.append(f"Key touch-downs with no window line (spy not attached?): {len(unseen)}")
    out.append(f"Cancelled by the system: {session.cancelled}; dropped on reset: {session.dropped}")
    lags = [k.lag for k in session.keys]
    if lags:
        out.append(f"Delay from finger to Kalam (ms): median {statistics.median(lags):.1f}, "
                   + f"90% {percentile(lags, 0.9):.1f}, max {max(lags):.1f}")
    claimed = Counter(r.split(":")[0] for s in session.spies for r in s.recognizers
                      if r.split(":")[-1] in ("1", "2", "3"))
    if claimed:
        out.append("Recognizers that began or recognized on a touch: "
                   + ", ".join(f"{name} x{n}" for name, n in claimed.most_common()))
    out.append("Typed: " + "".join(session.typed).replace("\n", "⏎"))
    if session.autocorrects:
        out.append("Autocorrects: " + ", ".join(f"{a} -> {b}" for a, b in session.autocorrects))
    return "\n".join(out)


def pull(device):
    destination = tempfile.NamedTemporaryFile(suffix="-kalam-trace.log", delete=False).name
    command = ["xcrun", "devicectl", "device", "copy", "from", "--device", device,
               "--domain-type", "appGroupDataContainer", "--domain-identifier", APP_GROUP,
               "--source", TRACE_PATH, "--destination", destination]
    try:
        subprocess.run(command, check=True, stdout=subprocess.DEVNULL)
    except (OSError, subprocess.CalledProcessError) as error:
        sys.exit(f"devicectl couldn't copy the trace ({error}). `xcrun devicectl list devices` shows the iPhone's name.")
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("trace", nargs="?", help="a kalam-trace.log already on this Mac")
    parser.add_argument("--device", help="pull the trace from this iPhone with devicectl")
    parser.add_argument("--all", action="store_true", help="the whole trace, not just the keyboard's last appearance")
    args = parser.parse_args()
    if not args.trace and not args.device:
        parser.error("give a trace file or --device")
    path = pull(args.device) if args.device else args.trace
    with open(path, encoding="utf-8", errors="replace") as file:
        print(report(parse(file.read(), everything=args.all)))


if __name__ == "__main__":
    main()
