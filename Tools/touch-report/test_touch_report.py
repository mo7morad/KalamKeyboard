from touch_report import parse, report

GATE = "_UISystemGestureGateGestureRecognizer"

# An older appearance, then the last one: the report covers only the last.
TRACE = f"""\
1000.0 frame UIInputView (0.0, 0.0, 402.0, 274.4) in window (0.0, 0.0, 402.0, 274.4)
1001.0 spy began at 30.0,120.0 in KeyboardView lag 1.0 ms id 0xold recognizers {GATE}:0
5000.0 frame UIInputView (0.0, 0.0, 402.0, 274.4) in window (0.0, 0.0, 402.0, 274.4)
5000.5 gesture UIWindow {GATE} delaysTouchesBegan true delaysTouchesEnded false cancelsTouchesInView true
5100.0 spy began at 30.0,120.0 in KeyboardView lag 2.0 ms id 0xa recognizers {GATE}:0,KeyTouchRecognizer:0
5100.4 touch began h at 5.50,0.40 lag 2.4 ms id 0xa
5160.0 sudden move from h, 90.0 pt, 60.0 ms after a 0.0 pt step
5160.1 commit "h"
5160.3 touch began e at 2.50,-0.40 lag 1.5 ms id 0xa
5200.0 spy ended at 120.0,60.0 in KeyboardView lag 1.0 ms id 0xa recognizers {GATE}:5,KeyTouchRecognizer:0
5200.2 touch ended e at 2.50,-0.40 lag 1.2 ms id 0xa
5200.3 commit "e"
5300.0 spy began at 200.0,230.0 in KeyboardView lag 30.0 ms id 0xb recognizers {GATE}:0,KeyTouchRecognizer:0
5340.0 view began id 0xb
5350.0 spy cancelled at 200.0,230.0 in KeyboardView lag 1.0 ms id 0xb recognizers {GATE}:3,KeyTouchRecognizer:4
5400.0 spy began at 150.0,20.0 in SuggestionBar lag 1.0 ms id 0xc recognizers {GATE}:0
5500.0 spy began at 200.0,240.0 in KeyboardView lag 3.0 ms id 0xd recognizers {GATE}:0,KeyTouchRecognizer:0
5500.2 touch began space at 4.90,3.40 lag 3.2 ms id 0xd
5550.0 touch ended space at 4.90,3.40 lag 1.0 ms id 0xd
5550.1 commitWord "he" -> "He" delete 2
5550.2 keyUp space
5600.0 touch cancelled y at 5.50,0.40 lag 1.0 ms id 0xe
"""


def test_report_covers_the_last_appearance_and_finds_the_lost_touch():
    text = report(parse(TRACE))
    assert "Touch-downs the keyboard's window got: 4 (KeyboardView 3, SuggestionBar 1)" in text  # not the older 0xold
    assert "Touch-downs the keys got: 2, plus 1 sudden-move landings" in text
    assert "Window touch-downs that never reached a key: 1" in text
    # The lost touch: where it was, and the system recognizer that recognized it when it was cancelled.
    assert f"+0.300 s at 200.0,230.0 in KeyboardView, lag 30.0 ms, recognizers {GATE}:0,KeyTouchRecognizer:0; cancelled 50 ms later, recognizers {GATE}:3,KeyTouchRecognizer:4; the key view got it 40 ms later, KeyTouchRecognizer didn't" in text
    assert f"Recognizers that began or recognized on a touch: {GATE} x1" in text
    assert "Cancelled by the system: 1; dropped on reset: 0" in text
    assert "Typed: he " in text
    assert "Autocorrects: he -> He" in text


def test_everything_counts_older_appearances_too():
    assert "Touch-downs the keyboard's window got: 5" in report(parse(TRACE, everything=True))


def test_taps_between_rows_are_counted():
    trace = "1.0 touch began q at 0.50,0.95 lag 1.0 ms id 0xq\n2.0 touch began z at 1.90,-0.05 lag 1.0 ms id 0xz\n"
    assert "Key touch-downs between rows (iOS dropped these before round 6): 2" in report(parse(trace))
    assert "between rows (iOS dropped these before round 6): 0" in report(parse(TRACE))


def test_a_trace_without_spy_lines_says_so():
    text = report(parse("1.0 touch began q at 0.50,0.50 lag 1.0 ms id 0xq\n"))
    assert "Key touch-downs with no window line (spy not attached?): 1" in text
