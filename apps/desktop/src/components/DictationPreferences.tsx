import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { SoundPicker } from "./SoundPicker";
import { Button, Card, PageHeader } from "./ui";
import { isNativeDesktop } from "../lib/native";
import {
  message,
  speechOptions,
  updateOptions,
  type SpeechOptions,
} from "../lib/dictation";

const field =
  "mt-2 block w-full rounded-control border border-line bg-canvas-subtle p-3 text-sm text-ink";
function PreferencesForm({
  value,
  languages,
}: {
  value: SpeechOptions;
  languages: string[][];
}) {
  const [sound, setSound] = useState(value.sound ?? "studio");
  const [panelSounds, setPanelSounds] = useState(value.panelSounds ?? false);
  const [savingFeedback,setSavingFeedback] = useState(false);
  const [language, setLanguage] = useState(value.language ?? "");
  const [translate, setTranslate] = useState(value.translateToEnglish);
  const [words, setWords] = useState(value.vocabulary.join("\n"));
  const [snippets, setSnippets] = useState(value.snippets);
  const [notice, setNotice] = useState("");
  const [busy, setBusy] = useState(false);
  async function saveFeedback(next: SpeechOptions["sound"], panels: boolean) {
    if(savingFeedback) return; setSavingFeedback(true);
    try {await invoke("dictation_set_feedback",{sound:next,panelSounds:panels});setSound(next);setPanelSounds(panels);}
    catch(e){setNotice(message(e));}finally{setSavingFeedback(false);}
  }
  return (
    <form
      className="space-y-4"
      onSubmit={async (event) => {
        event.preventDefault();
        setBusy(true);
        try {
          await updateOptions({
            sound, panelSounds,
            language: language || null,
            translateToEnglish: translate,
            vocabulary: Array.from(
              new Set(
                words
                  .split("\n")
                  .map((w) => w.trim())
                  .filter(Boolean),
              ),
            ),
            snippets,
          });
          setNotice("Saved on this device.");
        } catch (err) {
          setNotice(message(err));
        } finally {
          setBusy(false);
        }
      }}
    >
      <Card className="space-y-4 p-5">
        <SoundPicker value={sound} disabled={savingFeedback} onChange={next=>void saveFeedback(next,panelSounds)} />
        <label className="flex items-center gap-2 text-sm text-ink"><input type="checkbox" checked={panelSounds} disabled={savingFeedback} onChange={e=>void saveFeedback(sound,e.target.checked)}/>Play sounds when opening and closing panels</label>
        <label className="block text-sm font-semibold text-ink">
          Spoken language
          <select
            className={field}
            value={language}
            onChange={(e) => setLanguage(e.target.value)}
          >
            <option value="">Detect automatically</option>
            {languages.map(([code, name]) => (
              <option key={code} value={code}>
                {name}
              </option>
            ))}
          </select>
        </label>
        <label className="flex items-center gap-2 text-sm text-ink">
          <input
            type="checkbox"
            checked={translate}
            onChange={(e) => setTranslate(e.target.checked)}
          />{" "}
          Translate speech into English
        </label>
      </Card>
      <Card className="space-y-2 p-5">
        <label className="block text-sm font-semibold text-ink">
          Personal dictionary
          <textarea
            rows={4}
            className={field}
            value={words}
            onChange={(e) => setWords(e.target.value)}
            placeholder="One name or term per line"
          />
        </label>
        <p className="text-xs text-ink-soft">
          Help the speech model recognize names and specialized terms.
        </p>
      </Card>
      <Card className="space-y-4 p-5">
        <h2 className="text-sm font-semibold text-ink">Snippets</h2>
        <p className="text-xs text-ink-soft">
          Say a shortcut as its own dictation to insert the full text.
        </p>
        {snippets.map((s, i) => (
          <div key={i} className="grid gap-2 border-t border-line pt-4">
            <label className="text-xs text-ink-soft">
              Spoken shortcut
              <input
                required
                maxLength={160}
                value={s.phrase}
                className={field}
                onChange={(e) =>
                  setSnippets(
                    snippets.map((v, j) =>
                      j === i ? { ...v, phrase: e.target.value } : v,
                    ),
                  )
                }
              />
            </label>
            <label className="text-xs text-ink-soft">
              Expanded text
              <textarea
                required
                maxLength={8192}
                value={s.text}
                className={field}
                onChange={(e) =>
                  setSnippets(
                    snippets.map((v, j) =>
                      j === i ? { ...v, text: e.target.value } : v,
                    ),
                  )
                }
              />
            </label>
            <Button
              variant="quiet"
              className="justify-self-start"
              onClick={() => setSnippets(snippets.filter((_, j) => j !== i))}
            >
              Remove snippet
            </Button>
          </div>
        ))}
        <Button
          variant="secondary"
          onClick={() => setSnippets([...snippets, { phrase: "", text: "" }])}
        >
          Add snippet
        </Button>
      </Card>
      <Button type="submit" disabled={busy}>
        Save preferences
      </Button>
      {notice && (
        <p role="status" className="text-sm text-ink-soft">
          {notice}
        </p>
      )}
    </form>
  );
}

export function DictationPreferences() {
  const [data, setData] = useState<{
    options: SpeechOptions;
    languages: string[][];
  }>();
  const [error, setError] = useState("");
  const native = isNativeDesktop();
  useEffect(() => {
    if (!native) return;
    let mounted = true;
    Promise.all([speechOptions(), invoke<string[][]>("dictation_languages")])
      .then(([options, languages]) => {
        if (mounted) setData({ options, languages });
      })
      .catch((err) => {
        if (mounted) setError(message(err));
      });
    return () => {
      mounted = false;
    };
  }, [native]);
  return (
    <div className="space-y-6">
      <PageHeader title="Dictation" />
      {data ? (
        <PreferencesForm value={data.options} languages={data.languages} />
      ) : (
        <p role="status" className="text-sm text-ink-soft">
          {error ||
            (native
              ? "Loading preferences…"
              : "Open Vyrra Desktop to set your language, dictionary, and snippets.")}
        </p>
      )}
    </div>
  );
}
