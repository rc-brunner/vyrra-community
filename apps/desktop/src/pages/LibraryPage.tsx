import { panelSound } from "../lib/dictation";
import { WritingTools } from "../components/WritingTools";
import { useEffect, useRef, useState } from "react";
import {
  Archive,
  ArchiveRestore,
  Check,
  ChevronDown,
  Copy,
  Download,
  FileAudio2,
  Pin,
  Search,
  Trash2,
  X,
} from "lucide-react";
import { QuietIcon } from "../components/QuietIcon";
import { Button, EmptyState, PageHeader } from "../components/ui";
import {
  deleteEntry,
  markEntry,
  message,
  readEntries,
  saveEntry,
  type Entry,
} from "../lib/dictation";
import { isNativeDesktop } from "../lib/native";
import { invoke } from "@tauri-apps/api/core";

export function SavedTranscript({
  entry,
  reload,
  onMove,
}: {
  entry: Entry;
  reload: () => Promise<void>;
  onMove: (label: string) => void;
}) {
  const [open, setOpen] = useState(false);
  const [draft, setDraft] = useState(entry.text);
  const [deleting, setDeleting] = useState(false);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");
  const summary = useRef<HTMLButtonElement>(null);
  const dirty = draft !== entry.text;

  async function run(action: () => Promise<unknown>, success = "") {
    setBusy(true);
    try {
      await action();
      setNotice(success);
    } catch (err) {
      setNotice(message(err));
    } finally {
      setBusy(false);
    }
  }
  function toggle() {
    panelSound(open);setOpen(!open);
    setDeleting(false);
    setNotice("");
  }
  const panelId = `transcript-${entry.id}`;
  return (
    <article className="vyrra-transcript" data-open={open}>
      <div className="vyrra-transcript-row">
        <button
          className="vyrra-row-summary"
          ref={summary}
          aria-expanded={open}
          aria-controls={panelId}
          onClick={toggle}
        >
          <ChevronDown
            className="vyrra-row-chevron"
            size={13}
            aria-hidden="true"
          />
          <span className="vyrra-row-title">{entry.text}</span>
        </button>
        <div
          className="vyrra-row-actions"
          aria-label="Transcript actions"
          role="group"
        >
          <QuietIcon
            label={entry.pinned ? "Unpin transcript" : "Pin transcript"}
            icon={Pin}
            aria-pressed={entry.pinned}
            className={entry.pinned ? "vyrra-pinned" : ""}
            disabled={busy}
            onClick={() =>
              void run(async () => {
                await markEntry(entry.id, { pinned: !entry.pinned });
                await reload();
              })
            }
          />
          <QuietIcon
            label={entry.archived ? "Restore transcript" : "Archive transcript"}
            icon={entry.archived ? ArchiveRestore : Archive}
            disabled={busy || dirty}
            onClick={() =>
              void run(async () => {
                await markEntry(entry.id, { archived: !entry.archived });
                await reload();
                onMove(
                  entry.archived
                    ? "Restored to transcripts."
                    : "Moved to archive.",
                );
              })
            }
          />
        </div>
      </div>
      <div id={panelId} hidden={!open} className="vyrra-transcript-detail">
        <label
          htmlFor={`entry-${entry.id}`}
          className="block text-xs text-ink-soft"
        >
          <time dateTime={new Date(entry.createdAt).toISOString()}>
            {new Date(entry.createdAt).toLocaleString()}
          </time>
        </label>
        <textarea
          id={`entry-${entry.id}`}
          rows={4}
          value={draft}
          onChange={(e) => {
            setDraft(e.target.value);
            setNotice("");
          }}
          className="mt-2 w-full rounded-control border border-line bg-surface p-3 text-sm text-ink"
        />
        <div className="mt-2 flex flex-wrap items-center gap-1">
          {dirty && (
            <>
              <Button
                disabled={busy || !draft.trim()}
                onClick={() =>
                  void run(async () => {
                    await saveEntry(draft, entry.id);
                    await reload();
                  }, "Changes saved.")
                }
              >
                <Check size={14} />
                Save changes
              </Button>
              <QuietIcon
                label="Discard edits"
                icon={X}
                disabled={busy}
                onClick={() => setDraft(entry.text)}
              />
            </>
          )}
          <WritingTools source={draft} apply={setDraft} />
          <QuietIcon
            label="Copy transcript"
            icon={Copy}
            disabled={busy || !draft}
            onClick={() =>
              void run(() => navigator.clipboard.writeText(draft), "Copied.")
            }
          />
          <QuietIcon
            label="Export transcript as text"
            icon={Download}
            disabled={busy || !draft}
            onClick={() =>
              void run(() => invoke("dictation_export", { text: draft }))
            }
          />
          {deleting ? (
            <>
              <Button
                variant="danger"
                disabled={busy}
                onClick={() =>
                  void run(async () => {
                    await deleteEntry(entry.id);
                    await reload();
                    onMove("Transcript deleted.");
                  })
                }
              >
                Confirm delete
              </Button>
              <Button
                variant="quiet"
                onClick={() => {
                  setDeleting(false);
                  summary.current?.focus();
                }}
              >
                Keep transcript
              </Button>
            </>
          ) : (
            <QuietIcon
              label="Delete transcript"
              icon={Trash2}
              disabled={busy}
              onClick={() => setDeleting(true)}
            />
          )}
        </div>
      </div>
      {notice && (
        <p role="status" className="px-3 py-1 text-xs text-ink-soft">
          {notice}
        </p>
      )}
    </article>
  );
}

export function LibraryPage() {
  const native = isNativeDesktop();
  const [entries, setEntries] = useState<Entry[]>([]);
  const [loading, setLoading] = useState(native);
  const [error, setError] = useState("");
  const [query, setQuery] = useState("");
  const [archived, setArchived] = useState(false);
  const [feedback, setFeedback] = useState("");
  const listHeading = useRef<HTMLHeadingElement>(null);
  function onMove(label: string) {
    setFeedback(label);
    listHeading.current?.focus({ preventScroll: true });
  }
  async function reload() {
    const data = await readEntries();
    setEntries(data);
    setError("");
  }
  useEffect(() => {
    if (!native) return;
    let active = true;
    readEntries()
      .then((data) => {
        if (active) setEntries(data);
      })
      .catch((err) => {
        if (active) setError(message(err));
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [native]);
  const matches = entries
    .filter(
      (e) =>
        e.archived === archived &&
        e.text.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase()),
    )
    .sort((a, b) => Number(b.pinned) - Number(a.pinned) || b.id - a.id);
  return (
    <div className="space-y-9">
      <PageHeader title="Library" />
      <section aria-label="Saved transcripts" className="space-y-4">
        <h2 className="sr-only" tabIndex={-1} ref={listHeading}>
          {archived ? "Archive" : "Saved transcripts"}
        </h2>
        <p aria-live="polite" className="sr-only">
          {feedback}
        </p>
        {loading ? (
          <p role="status">Opening your library…</p>
        ) : error ? (
          <div role="alert">
            {error}{" "}
            <Button
              variant="quiet"
              onClick={() =>
                void reload().catch((err) => setError(message(err)))
              }
            >
              Retry
            </Button>
          </div>
        ) : entries.length === 0 ? (
          <EmptyState
            icon={<FileAudio2 size={21} aria-hidden="true" />}
            title="Nothing here yet"
            description={
              native
                ? "Choose Save to Library after dictation to keep a transcript on this device."
                : "Your transcripts will appear here."
            }
          />
        ) : (
          <>
            <label className="flex items-center gap-3 rounded-control border border-line bg-surface px-4">
              <Search size={16} aria-hidden="true" />
              <input
                type="search"
                aria-label="Search library"
                placeholder="Search transcripts"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                className="min-h-11 flex-1 bg-transparent text-sm text-ink"
              />
            </label>
            {(archived || entries.some((e) => e.archived)) && (
              <div
                role="group"
                aria-label="Library view"
                className="flex gap-1"
              >
                <Button
                  variant={archived ? "quiet" : "secondary"}
                  aria-pressed={!archived}
                  onClick={() => setArchived(false)}
                >
                  Transcripts
                </Button>
                <Button
                  variant={archived ? "secondary" : "quiet"}
                  aria-pressed={archived}
                  onClick={() => setArchived(true)}
                >
                  Archive
                </Button>
              </div>
            )}
            <div className="vyrra-transcript-list">
              {matches.length ? (
                matches.map((entry) => (
                  <SavedTranscript
                    key={entry.id}
                    entry={entry}
                    reload={reload}
                    onMove={onMove}
                  />
                ))
              ) : (
                <p className="text-sm text-ink-soft">
                  {query
                    ? "No matching transcripts."
                    : archived
                      ? "Your archive is empty."
                      : "No active transcripts."}
                </p>
              )}
            </div>
          </>
        )}
      </section>
    </div>
  );
}
