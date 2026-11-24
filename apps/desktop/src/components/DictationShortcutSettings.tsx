import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { isNativeDesktop } from "../lib/native";
import { message } from "../lib/dictation";
import { Card } from "./ui";

export function DictationShortcutSettings() {
  const [enabled, setEnabled] = useState(false);
  const [ready, setReady] = useState(false);
  const [error, setError] = useState("");
  const native = isNativeDesktop();
  useEffect(() => {
    if (!native) return;
    let active = true;
    invoke<boolean>("dictation_hotkeys").then(value => { if (active) { setEnabled(value); setReady(true); } })
      .catch(err => { if (active) setError(message(err)); });
    return () => { active = false; };
  }, [native]);
  if (!native) return null;
  return <Card className="space-y-3 p-5">
    <label className="flex items-center gap-3 text-sm font-semibold text-ink"><input type="checkbox" checked={enabled} disabled={!ready} onChange={async e => {
      const next = e.target.checked; setReady(false); setError("");
      try { await invoke("dictation_set_hotkeys", { enabled: next }); setEnabled(next); }
      catch (err) { setError(message(err)); } finally { setReady(true); }
    }} /> Dictate in other apps</label>
    <p className="text-sm text-ink-soft">Hold Control + Shift + Space to talk. Press Control + Alt (Option) + Space to start or finish hands-free.</p>
    <p className="text-xs text-ink-soft">Keep the original text field focused for insertion. On Mac, allow Vyrra in System Settings → Privacy &amp; Security → Accessibility.</p>
    {error && <p role="alert" className="text-sm text-danger">{error}</p>}
  </Card>;
}
