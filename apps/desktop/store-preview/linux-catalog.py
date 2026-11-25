"""Exercise the installed GTK/WebKit app with ordinary accessibility actions."""
import os
import subprocess
import time
import pyatspi

app = subprocess.Popen(["/usr/bin/vyrra-desktop"])
def find(name, wait=90, enabled=True):
    deadline = time.monotonic() + wait
    last = []
    while time.monotonic() < deadline:
        if app.poll() is not None:
            raise RuntimeError(f"App exited with {app.returncode}")
        queue = [pyatspi.Registry.getDesktop(0)]
        last = []
        while queue:
            element = queue.pop(0)
            try:
                label = element.name
                if label:
                    last.append(label)
                matches = name(label or "") if callable(name) else label == name
                if matches and (not enabled or element.getState().contains(pyatspi.STATE_ENABLED)):
                    return element
                queue.extend(element.getChildAtIndex(i) for i in range(element.childCount))
            except (RuntimeError, LookupError, AttributeError):
                continue
        time.sleep(.35)
    raise RuntimeError(f"Missing {name!r} in the isolated runner. Controls: {last[:90]}")
def press(name):
    control=find(name)
    actions=control.queryAction()
    for i in range(actions.nActions):
        if actions.getName(i).lower() in {"click","press","activate","jump","open"}:
            if not actions.doAction(i):
                raise RuntimeError(f"Action failed: {name}")
            return
    raise RuntimeError(f"No activation action on {name}")

def select_wav():
    title = "^Transcribe audio on this device$"
    picker = subprocess.run(
        ["xdotool", "search", "--sync", "--onlyvisible", "--name", title],
        capture_output=True, check=True, timeout=45, text=True,
    ).stdout.splitlines()[-1]
    chooser = find("Transcribe audio on this device", wait=15, enabled=False)
    find("Select", wait=15, enabled=False)
    subprocess.run(["xdotool", "windowactivate", "--sync", picker], check=True)
    subprocess.run(["xdotool", "key", "--clearmodifiers", "ctrl+l"], check=True)
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        queue = [chooser]
        while queue:
            element = queue.pop(0)
            try:
                state = element.getState()
                if state.contains(pyatspi.STATE_FOCUSED) and state.contains(pyatspi.STATE_EDITABLE):
                    target = os.environ["VYRRA_TEST_WAV"]
                    element.queryEditableText().setTextContents(target)
                    if element.queryText().getText(0, -1) != target:
                        raise AssertionError("The native file chooser did not accept the fixture path.")
                    print("Verified the fixture path in the focused GTK location entry.")
                    press("Select")
                    time.sleep(.7)
                    visible = subprocess.run(["xdotool", "search", "--onlyvisible", "--name", title], capture_output=True)
                    if visible.returncode == 0:
                        subprocess.run(["xdotool", "key", "--clearmodifiers", "Return"], check=True)
                    return
                queue.extend(element.getChildAtIndex(i) for i in range(element.childCount))
            except (RuntimeError, LookupError, AttributeError):
                continue
        time.sleep(.15)
    raise RuntimeError("GTK did not focus its location entry.")

try:
    press("Models")
    press("Download Whisper Tiny, Multilingual")
    find("Whisper Tiny, Multilingual in use",240,False)
    press("Download Whisper Tiny, English only")
    find("Whisper Tiny, English only in use",240,False)
    press("Use Whisper Tiny, Multilingual")
    find("Whisper Tiny, Multilingual in use",60,False)
    press("Dictate")
    find("Start dictation")
    print("Verified installation, model downloads, switching, and ready recorder through native GTK accessibility.")
    press("More audio options")
    press("Transcribe WAV")
    select_wav()
    transcript = find("Transcript", 240)
    value = transcript.queryText().getText(0, -1).lower()
    if "country" not in value or "ask" not in value:
        raise RuntimeError(f"Unexpected public speech sample transcript: {value}")
    print("Decoded the public speech fixture through the installed app's file picker.")
    press("Save to Library")
    find("Saved on this device.", enabled=False)
    press("Library")
    find(lambda label: "country" in label.lower() and "ask" in label.lower(), enabled=False)
    print("Verified the saved native transcript in the Linux library.")
finally:
    app.terminate()
    app.wait(timeout=10)
