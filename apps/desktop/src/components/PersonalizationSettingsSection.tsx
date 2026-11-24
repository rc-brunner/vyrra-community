import { AppWindow, FilePenLine, LockKeyhole, Plus } from "lucide-react";

import { Button, Card, PageHeader, SectionHeading } from "./ui";

const fieldClassName =
  "mt-2 w-full rounded-control border border-line bg-canvas-subtle px-3.5 text-sm text-ink placeholder:text-ink-faint disabled:cursor-not-allowed disabled:opacity-65";

export function PersonalizationSettingsSection() {
  return (
    <div className="space-y-9">
      <PageHeader
        eyebrow="Settings · Personalization"
        title="Make Vyrra sound like you."
      />

      <div
        id="personalization-read-only"
        role="status"
        className="flex items-center gap-3 border-y border-line py-3 text-sm text-ink-soft"
      >
        <LockKeyhole
          className="size-4 shrink-0 text-ink-faint"
          aria-hidden="true"
        />
        <p>
          Personalization is read-only in this build. Changes are not saved or
          applied.
        </p>
      </div>

      <section
        aria-labelledby="personal-instructions-heading"
        className="space-y-4"
      >
        <SectionHeading
          id="personal-instructions-heading"
          title="Personal instructions"
          description="Choose the words, tone, and formatting Vyrra should use."
        />

        <Card className="p-5 sm:p-6">
          <fieldset
            disabled
            aria-describedby="personalization-read-only"
            className="space-y-5"
          >
            <legend className="sr-only">Personal instructions</legend>

            <div className="flex items-center gap-3">
              <span className="grid size-9 shrink-0 place-items-center rounded-full border border-line text-ink-soft">
                <FilePenLine size={16} aria-hidden="true" />
              </span>
              <div>
                <h3 className="text-sm font-semibold text-ink">
                  Writing preferences
                </h3>
                <p className="mt-0.5 text-xs text-ink-faint">All apps</p>
              </div>
            </div>

            <label
              htmlFor="global-instructions-preview"
              className="block text-xs font-semibold text-ink-soft"
            >
              Instructions
              <textarea
                id="global-instructions-preview"
                rows={4}
                placeholder="For example: keep my wording natural, preserve names, and use short paragraphs."
                className={`${fieldClassName} resize-none py-3 leading-6`}
              />
            </label>

            <div className="flex flex-wrap justify-end gap-2">
              <Button variant="quiet">Clear</Button>
              <Button>Save instructions</Button>
            </div>
          </fieldset>
        </Card>
      </section>

      <section aria-labelledby="profile-heading" className="space-y-4">
        <SectionHeading
          id="profile-heading"
          title="App profiles"
          description="Use a different style in selected apps."
          action={
            <Button
              variant="secondary"
              disabled
              aria-describedby="personalization-read-only"
            >
              <Plus size={15} aria-hidden="true" />
              New profile
            </Button>
          }
        />

        <Card className="p-5 sm:p-6">
          <fieldset
            disabled
            aria-describedby="personalization-read-only"
            className="space-y-5"
          >
            <legend className="sr-only">App profile</legend>

            <div className="flex items-center gap-3">
              <span className="grid size-9 shrink-0 place-items-center rounded-full border border-line text-ink-soft">
                <AppWindow size={16} aria-hidden="true" />
              </span>
              <div>
                <h3 className="text-sm font-semibold text-ink">New profile</h3>
                <p className="mt-0.5 text-xs text-ink-faint">
                  No apps selected
                </p>
              </div>
            </div>

            <div className="grid gap-4 sm:grid-cols-2">
              <label className="text-xs font-semibold text-ink-soft">
                Profile name
                <input
                  type="text"
                  placeholder="Work"
                  className={`${fieldClassName} min-h-11`}
                />
              </label>

              <label className="text-xs font-semibold text-ink-soft">
                Use in
                <select className={`${fieldClassName} min-h-11`}>
                  <option>Select apps</option>
                </select>
              </label>
            </div>

            <label
              htmlFor="profile-instructions-preview"
              className="block text-xs font-semibold text-ink-soft"
            >
              Profile instructions
              <textarea
                id="profile-instructions-preview"
                rows={3}
                placeholder="Add app-specific vocabulary or style."
                className={`${fieldClassName} resize-none py-3 leading-6`}
              />
            </label>
          </fieldset>
        </Card>
      </section>
    </div>
  );
}
