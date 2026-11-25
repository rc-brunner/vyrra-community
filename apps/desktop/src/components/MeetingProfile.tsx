import { useEffect, useState } from "react";
import { Camera, KeyRound, RotateCcw } from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import { meetings, type MeetingView } from "../lib/meetings";
import { isNativeDesktop } from "../lib/native";
import { message } from "../lib/dictation";
import { QuietIcon } from "./QuietIcon";
import { Button, Card, PageHeader } from "./ui";
const field =
  "mt-1 w-full rounded-control border border-line bg-canvas-subtle px-3 py-2 text-sm text-ink";
function ProfileForm({
  view,
  reload,
}: {
  view: MeetingView;
  reload: () => Promise<void>;
}) {
  const [name, setName] = useState(view.profile.name),
    [server, setServer] = useState(view.profile.server),
    [source, setSource] = useState(view.profile.source);
  const [notice, setNotice] = useState(""),
    [busy, setBusy] = useState(false);
  async function run(call: () => Promise<unknown>, text: string) {
    setBusy(true);
    setNotice("");
    try {
      await call();
      await reload();
      setNotice(text);
    } catch (e) {
      setNotice(message(e));
    } finally {
      setBusy(false);
    }
  }
  return (
    <form
      className="space-y-4"
      onSubmit={(e) => {
        e.preventDefault();
        void run(
          () => invoke("meeting_profile", { name, server, source }),
          "Meeting preferences saved.",
        );
      }}
    >
      <Card className="space-y-4 p-5">
        <div className="flex items-center gap-3">
          <div className="participant-avatar">
            <img
              src={`data:image/png;base64,${view.avatar}`}
              alt="Meeting participant picture"
            />
            <div className="avatar-tools">
              <QuietIcon
                label="Choose participant picture"
                icon={Camera}
                disabled={busy}
                onClick={() =>
                  void run(
                    () => invoke("meeting_picture", { reset: false }),
                    "",
                  )
                }
              />
            </div>
          </div>
          <label className="flex-1 text-sm font-semibold text-ink">
            Participant name
            <input
              required
              maxLength={64}
              className={field}
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
          </label>
          {view.profile.image && (
            <QuietIcon
              label="Restore Vyrra icon"
              icon={RotateCcw}
              disabled={busy}
              onClick={() =>
                void run(
                  () => invoke("meeting_picture", { reset: true }),
                  "Vyrra icon restored.",
                )
              }
            />
          )}
        </div>
        <p className="text-xs text-ink-soft">
          New participants use this name and picture. They introduce themselves
          as Vyrra note-takers in chat.
        </p>
      </Card>
      <Card className="space-y-4 p-5">
        {view.sources.length > 0 && (
          <label className="block text-sm font-semibold text-ink">
            Local meeting audio
            <select
              className={field}
              value={source}
              onChange={(e) => setSource(e.target.value)}
            >
              {view.sources.map(([id, title]) => (
                <option key={id} value={id}>
                  {title}
                </option>
              ))}
            </select>
          </label>
        )}
        <label className="block text-sm font-semibold text-ink">
          Self-hosted Attendee server
          <input
            className={field}
            value={server}
            type="url"
            placeholder="https://meetings.example.com"
            onChange={(e) => setServer(e.target.value)}
          />
        </label>
        <div className="flex items-center gap-2">
          <QuietIcon
            icon={KeyRound}
            label="Import server API key from file"
            disabled={!server || busy}
            onClick={() =>
              void run(() => invoke("meeting_key", { server }), "")
            }
          />
          <span className="text-xs text-ink-soft">
            Import a key file into the system credential store.
          </span>
        </div>
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
export function MeetingProfile() {
  const [view, setView] = useState<MeetingView>(),
    [error, setError] = useState("");
  const native = isNativeDesktop();
  const reload = async () => setView(await meetings());
  useEffect(() => {
    if (native)
      void meetings()
        .then(setView)
        .catch((e) => setError(message(e)));
  }, [native]);
  return (
    <section className="space-y-5">
      <PageHeader title="Meetings" />
      {view ? (
        <ProfileForm view={view} reload={reload} />
      ) : (
        <p role="status" className="text-sm text-ink-soft">
          {error ||
            (native ? "Loading…" : "Open Vyrra Desktop to set up meetings.")}
        </p>
      )}
    </section>
  );
}
