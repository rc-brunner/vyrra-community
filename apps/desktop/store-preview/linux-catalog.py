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
                if label == name and (not enabled or element.getState().contains(pyatspi.STATE_ENABLED)):
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
finally:
    app.terminate()
    app.wait(timeout=10)
