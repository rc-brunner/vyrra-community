/**
 * A source-linked parity inventory for the current reference feature matrix.
 *
 * This is a product-planning contract, not an entitlement or runtime manifest.
 * `delivery` describes what this repository can honestly claim today:
 *
 * - `prototype`: an explicit, non-operational interface contract is present.
 * - `adapter-required`: native, model, provider, or storage work is required.
 * - `planned`: the capability has no complete product surface or adapter yet.
 */

export const CAPABILITY_REFERENCE_URL =
  "https://docs.vowen.ai/pricing";

export type CapabilityTarget =
  | "library"
  | "meetings"
  | "automations"
  | "models"
  | "settings";

export type CapabilityCategoryId =
  | "transcription"
  | "meeting-notes"
  | "ai"
  | "productivity"
  | "integrations"
  | "perks";

export interface CapabilityCategory {
  readonly id: CapabilityCategoryId;
  readonly label: string;
  readonly description: string;
  readonly target: CapabilityTarget;
}

export type CapabilityParity = "baseline" | "advanced";
export type CapabilityDelivery =
  | "prototype"
  | "adapter-required"
  | "planned";

export interface Capability {
  readonly id: string;
  readonly category: Exclude<CapabilityCategoryId, "perks">;
  readonly title: string;
  readonly description: string;
  readonly parity: CapabilityParity;
  readonly delivery: CapabilityDelivery;
  readonly deliveryDetail: string;
  readonly target: CapabilityTarget;
  readonly sourceUrl: string;
}

export interface RoadmapCapability {
  readonly id: string;
  readonly title: string;
  readonly description: string;
  readonly status: "roadmap";
  readonly target: CapabilityTarget;
  readonly sourceUrl: string;
}

export interface VendorServiceReference {
  readonly id: string;
  readonly category: "perks";
  readonly title: string;
  readonly description: string;
  readonly status: "reference-only";
  readonly target: "settings";
  readonly sourceUrl: string;
}

export interface DocumentedProExtension {
  readonly id: string;
  readonly title: string;
  readonly description: string;
  readonly delivery: CapabilityDelivery;
  readonly deliveryDetail: string;
  readonly target: CapabilityTarget;
  readonly sourceUrl: string;
  readonly sourceNote: string;
}

export const CAPABILITY_CATEGORIES = [
  {
    id: "transcription",
    label: "Transcription",
    description:
      "Speech engines, language coverage, file processing, and exports.",
    target: "models",
  },
  {
    id: "meeting-notes",
    label: "Meeting notes",
    description:
      "Consent-aware capture, speaker structure, summaries, and review.",
    target: "meetings",
  },
  {
    id: "ai",
    label: "AI assistance",
    description:
      "User-configured enhancement, commands, profiles, and memory.",
    target: "models",
  },
  {
    id: "productivity",
    label: "Productivity",
    description:
      "Shortcuts, reusable text, workflows, utilities, and data portability.",
    target: "automations",
  },
  {
    id: "integrations",
    label: "Integrations",
    description:
      "Explicitly authorized external connections and device sync.",
    target: "settings",
  },
  {
    id: "perks",
    label: "Vendor service references",
    description:
      "Commercial service promises tracked as references, not product features.",
    target: "settings",
  },
] as const satisfies readonly CapabilityCategory[];

export const CURRENT_CAPABILITIES = [
  {
    id: "transcription-local-models",
    category: "transcription",
    title: "Local transcription models",
    description:
      "Run user-installed speech models locally behind verified manifests.",
    parity: "baseline",
    delivery: "adapter-required",
    deliveryDetail:
      "The model activation gate is prototyped; no native runtime adapter is connected.",
    target: "models",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "transcription-cloud-models",
    category: "transcription",
    title: "Cloud transcription models",
    description:
      "Use an explicitly selected remote speech provider without silent fallback.",
    parity: "baseline",
    delivery: "adapter-required",
    deliveryDetail:
      "No provider manifest or tested cloud transcription adapter is available.",
    target: "models",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "transcription-language-coverage",
    category: "transcription",
    title: "Broad language coverage",
    description:
      "Expose the reference matrix's 99-language target only when model metadata verifies it.",
    parity: "baseline",
    delivery: "adapter-required",
    deliveryDetail:
      "Language support must come from validated runtime metadata, not a static claim.",
    target: "models",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "transcription-windows-gpu",
    category: "transcription",
    title: "Windows GPU acceleration",
    description:
      "Use compatible Windows graphics hardware for supported local workloads.",
    parity: "baseline",
    delivery: "adapter-required",
    deliveryDetail:
      "Hardware detection and an accelerated Windows runtime are not connected.",
    target: "models",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "transcription-history",
    category: "transcription",
    title: "Voice history",
    description:
      "Review revisioned transcripts with provenance and retention state.",
    parity: "baseline",
    delivery: "planned",
    deliveryDetail:
      "The library is an honest empty state without durable transcript storage.",
    target: "library",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "transcription-manual-files",
    category: "transcription",
    title: "Manual file transcription without an app quota",
    description:
      "Transcribe user-selected audio or video files without a product quota.",
    parity: "advanced",
    delivery: "adapter-required",
    deliveryDetail:
      "File parsing, isolation, duration limits, and transcription workers are absent.",
    target: "library",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "transcription-realtime-preview",
    category: "transcription",
    title: "Real-time transcription preview",
    description:
      "Display provisional words while capture continues, then finalize them explicitly.",
    parity: "advanced",
    delivery: "adapter-required",
    deliveryDetail:
      "Streaming capture and incremental transcription adapters are not connected.",
    target: "models",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "transcription-speaker-diarization",
    category: "transcription",
    title: "File speaker diarization",
    description:
      "Separate speakers in imported transcription jobs with reviewable labels.",
    parity: "advanced",
    delivery: "adapter-required",
    deliveryDetail:
      "No verified diarization model or post-processing adapter is available.",
    target: "library",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "transcription-translate-english",
    category: "transcription",
    title: "Automatic translation to English",
    description:
      "Create an English derivative while preserving the source-language transcript.",
    parity: "advanced",
    delivery: "adapter-required",
    deliveryDetail:
      "Translation needs a verified model route and revisioned derivative storage.",
    target: "models",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "transcription-parallel-queue",
    category: "transcription",
    title: "Parallel transcription queue",
    description:
      "Run bounded file jobs concurrently with visible progress and cancellation.",
    parity: "advanced",
    delivery: "planned",
    deliveryDetail:
      "No durable job queue, worker isolation, or recovery path exists.",
    target: "library",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "transcription-structured-exports",
    category: "transcription",
    title: "Caption and structured exports",
    description:
      "Export SRT, VTT, JSON, CSV, or Markdown with source revision metadata.",
    parity: "baseline",
    delivery: "planned",
    deliveryDetail:
      "No transcript artifact exists to export and no exporter is implemented.",
    target: "library",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "transcription-document-exports",
    category: "transcription",
    title: "PDF and text exports",
    description:
      "Export reviewable PDF or plain-text derivatives from a selected revision.",
    parity: "advanced",
    delivery: "planned",
    deliveryDetail:
      "Document exporters and provenance-preserving export receipts are absent.",
    target: "library",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "meeting-unlimited-recording",
    category: "meeting-notes",
    title: "Meeting recording without an app quota",
    description:
      "Capture meetings without a product quota while keeping consent visible.",
    parity: "advanced",
    delivery: "adapter-required",
    deliveryDetail:
      "The capture surface is a preflight prototype; native audio capture is not active.",
    target: "meetings",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "meeting-auto-detect",
    category: "meeting-notes",
    title: "Meeting detection",
    description:
      "Recognize a likely meeting and ask before starting any capture.",
    parity: "advanced",
    delivery: "adapter-required",
    deliveryDetail:
      "Calendar and application-detection adapters are absent; auto-recording is prohibited.",
    target: "meetings",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "meeting-pause-resume",
    category: "meeting-notes",
    title: "Pause and resume recording",
    description:
      "Pause capture without ending the session and show the effective state.",
    parity: "advanced",
    delivery: "adapter-required",
    deliveryDetail:
      "A native capture session controller and recovery journal are required.",
    target: "meetings",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "meeting-mute-background",
    category: "meeting-notes",
    title: "Mute background audio during recording",
    description:
      "Temporarily suppress playback through an explicit, reversible control.",
    parity: "advanced",
    delivery: "adapter-required",
    deliveryDetail:
      "System-audio routing is platform-specific and has no verified adapter.",
    target: "meetings",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "meeting-speaker-diarization",
    category: "meeting-notes",
    title: "Meeting speaker diarization",
    description:
      "Separate meeting speakers and let the user review names before saving.",
    parity: "advanced",
    delivery: "adapter-required",
    deliveryDetail:
      "No supported diarization route or reversible speaker editor exists.",
    target: "meetings",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "meeting-built-in-summary",
    category: "meeting-notes",
    title: "Built-in summary template",
    description:
      "Create a cited summary derivative while keeping the transcript usable.",
    parity: "baseline",
    delivery: "adapter-required",
    deliveryDetail:
      "The summary activation contract is visible, but no reasoning adapter is configured.",
    target: "meetings",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "meeting-custom-summary-templates",
    category: "meeting-notes",
    title: "Custom summary templates",
    description:
      "Save user-authored structures for cited meeting summaries.",
    parity: "advanced",
    delivery: "planned",
    deliveryDetail:
      "Template storage, validation, versioning, and preview are not implemented.",
    target: "meetings",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "meeting-custom-instructions",
    category: "meeting-notes",
    title: "Custom note instructions",
    description:
      "Apply user-authored guidance to derived notes without altering source text.",
    parity: "advanced",
    delivery: "planned",
    deliveryDetail:
      "Instruction storage and an auditable derivation pipeline are absent.",
    target: "meetings",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "meeting-chat",
    category: "meeting-notes",
    title: "Chat with notes and transcripts",
    description:
      "Ask scoped questions with citations to exact local source revisions.",
    parity: "advanced",
    delivery: "adapter-required",
    deliveryDetail:
      "No retrieval index, citation contract, or verified reasoning adapter exists.",
    target: "meetings",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "meeting-import-media",
    category: "meeting-notes",
    title: "Import media into meeting notes",
    description:
      "Turn selected audio or video into a meeting record through an isolated import.",
    parity: "advanced",
    delivery: "adapter-required",
    deliveryDetail:
      "Media parsing, transcription, and durable meeting storage are unavailable.",
    target: "meetings",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "ai-byok-enhancement",
    category: "ai",
    title: "Bring-your-own-key AI enhancement",
    description:
      "Optionally refine transcript text through a user-configured provider.",
    parity: "baseline",
    delivery: "adapter-required",
    deliveryDetail:
      "Secrets cannot enter the renderer; a secure credential and provider boundary is required.",
    target: "models",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "ai-command-mode",
    category: "ai",
    title: "Command Mode without an app quota",
    description:
      "Transform selected dictation into an explicit user-requested action or draft.",
    parity: "advanced",
    delivery: "adapter-required",
    deliveryDetail:
      "Command routing needs capture, reasoning, authorization, and receipt contracts.",
    target: "models",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "ai-per-app-tones",
    category: "ai",
    title: "Per-app voice profiles without an app quota",
    description:
      "Choose speech and writing behavior for explicitly matched applications.",
    parity: "advanced",
    delivery: "adapter-required",
    deliveryDetail:
      "Profile UI and trusted focused-application detection are not connected.",
    target: "settings",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "ai-memory",
    category: "ai",
    title: "User memory without an app quota",
    description:
      "Store user-reviewed preferences with provenance, scope, and deletion controls.",
    parity: "advanced",
    delivery: "planned",
    deliveryDetail:
      "No durable memory schema, review surface, or retention policy exists.",
    target: "models",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "ai-global-instructions",
    category: "ai",
    title: "Global AI instructions",
    description:
      "Apply user-authored formatting and style guidance across eligible tasks.",
    parity: "advanced",
    delivery: "planned",
    deliveryDetail:
      "Instruction scope, precedence, versioning, and provider execution are not implemented.",
    target: "settings",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "ai-dictionary-corrections",
    category: "ai",
    title: "Reviewable dictionary corrections",
    description:
      "Suggest recurring corrections for explicit approval before vocabulary changes.",
    parity: "advanced",
    delivery: "planned",
    deliveryDetail:
      "The dictionary and a safe correction-review workflow are not implemented.",
    target: "library",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "ai-multiple-api-providers",
    category: "ai",
    title: "Multiple custom AI providers",
    description:
      "Configure more than one tested provider through a secure adapter boundary.",
    parity: "advanced",
    delivery: "adapter-required",
    deliveryDetail:
      "No provider adapter suite or secure credential broker has passed verification.",
    target: "models",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "productivity-custom-shortcut",
    category: "productivity",
    title: "Custom shortcut",
    description:
      "Record a chord or double-tap gesture with visible conflict feedback.",
    parity: "baseline",
    delivery: "prototype",
    deliveryDetail:
      "The renderer configuration works ephemerally; global registration still needs a native adapter.",
    target: "settings",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "productivity-alternative-shortcuts",
    category: "productivity",
    title: "Alternative and multiple shortcuts",
    description:
      "Assign more than one gesture to an action with deterministic precedence.",
    parity: "advanced",
    delivery: "prototype",
    deliveryDetail:
      "Multiple bindings can be added, edited, and removed ephemerally; global registration still needs a native adapter.",
    target: "settings",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "productivity-dictionary-threads",
    category: "productivity",
    title: "Dictionary and reusable threads",
    description:
      "Keep vocabulary and reusable text in user-controlled, reviewable stores.",
    parity: "baseline",
    delivery: "planned",
    deliveryDetail:
      "Neither a dictionary nor a durable reusable-thread store exists.",
    target: "library",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "productivity-text-expander",
    category: "productivity",
    title: "Text expansions without an app quota",
    description:
      "Expand user-defined abbreviations only through an explicit local rule.",
    parity: "advanced",
    delivery: "planned",
    deliveryDetail:
      "Expansion storage, collision handling, and native text insertion are absent.",
    target: "automations",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "productivity-workflows",
    category: "productivity",
    title: "Workflows without an app quota",
    description:
      "Compose local and external steps with authority proportional to risk.",
    parity: "advanced",
    delivery: "prototype",
    deliveryDetail:
      "The approval model and empty state are prototyped; no workflow engine can run.",
    target: "automations",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "productivity-workflow-webhooks-scripts",
    category: "productivity",
    title: "Workflow webhooks and custom scripts",
    description:
      "Run bounded integration steps with preview, authorization, and receipts.",
    parity: "advanced",
    delivery: "adapter-required",
    deliveryDetail:
      "Sandboxing, webhook delivery, idempotency, and connector adapters are absent.",
    target: "automations",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "productivity-custom-utilities",
    category: "productivity",
    title: "Custom utilities without an app quota",
    description:
      "Save focused, user-authored transformations with explicit input and output.",
    parity: "advanced",
    delivery: "planned",
    deliveryDetail:
      "Utility schemas, execution isolation, and durable storage are not implemented.",
    target: "automations",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "productivity-data-portability",
    category: "productivity",
    title: "Data import and export",
    description:
      "Move user-controlled settings and records through a versioned portable format.",
    parity: "advanced",
    delivery: "planned",
    deliveryDetail:
      "There is no durable data schema, migration path, or validated archive format.",
    target: "settings",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "integration-obsidian",
    category: "integrations",
    title: "Obsidian integration",
    description:
      "Write approved note derivatives into a user-selected local vault.",
    parity: "advanced",
    delivery: "adapter-required",
    deliveryDetail:
      "Vault authorization, path safety, conflict handling, and receipts are absent.",
    target: "settings",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "integration-webhooks",
    category: "integrations",
    title: "Webhook integration",
    description:
      "Send an approved, scoped payload to an explicitly configured endpoint.",
    parity: "advanced",
    delivery: "adapter-required",
    deliveryDetail:
      "No network adapter, secret boundary, delivery retry, or receipt contract exists.",
    target: "automations",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "integration-cloud-sync",
    category: "integrations",
    title: "Cloud sync across three devices",
    description:
      "Sync selected text and settings through user-authorized storage.",
    parity: "advanced",
    delivery: "adapter-required",
    deliveryDetail:
      "Cloud authorization, encryption, conflict resolution, and sync adapters are absent.",
    target: "settings",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
] as const satisfies readonly Capability[];

/**
 * Current Pro documentation contains a few shipped or experimental surfaces
 * that are not rows in the canonical pricing matrix. They stay separate so the
 * 40-row matrix remains mechanically auditable.
 */
export const DOCUMENTED_PRO_EXTENSIONS = [
  {
    id: "extension-live-meeting-questions",
    title: "Questions during a live meeting",
    description:
      "Ask questions grounded only in the current live transcript while capture remains visible.",
    delivery: "adapter-required",
    deliveryDetail:
      "Streaming transcription, scoped retrieval, citations, and a verified reasoning adapter are absent.",
    target: "meetings",
    sourceUrl: "https://docs.vowen.ai/meeting-notes/recording",
    sourceNote:
      "Detailed recording docs describe this as shipped, while the pricing page still lists it as coming soon.",
  },
  {
    id: "extension-read-only-connectors",
    title: "Read-only context connectors",
    description:
      "Search or read explicitly authorized external context without create, edit, send, or delete authority.",
    delivery: "adapter-required",
    deliveryDetail:
      "No connector manifests, grants, provider adapters, or provenance receipts exist.",
    target: "automations",
    sourceUrl: "https://docs.vowen.ai/integrations/connectors",
    sourceNote:
      "The integration docs call connectors experimental and Pro-only; the pricing matrix omits them.",
  },
  {
    id: "extension-command-context",
    title: "Context-aware command workspace",
    description:
      "Review selected text, files, screenshots, memory, profiles, and connector context before an AI transformation.",
    delivery: "planned",
    deliveryDetail:
      "Context collection, redaction, request preview, result review, and paste/discard controls are not implemented.",
    target: "automations",
    sourceUrl: "https://docs.vowen.ai/ai-features/command-mode",
    sourceNote:
      "The detailed Command Mode docs are broader than the single pricing-matrix row.",
  },
] as const satisfies readonly DocumentedProExtension[];

/**
 * Commercial promises belong to the referenced vendor, not this product.
 * They remain visible for parity research but must never render as included
 * product capabilities or implementation claims.
 */
export const VENDOR_SERVICE_REFERENCES = [
  {
    id: "vendor-priority-support",
    category: "perks",
    title: "Priority support",
    description:
      "A vendor support commitment, not a software capability in this workspace.",
    status: "reference-only",
    target: "settings",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "vendor-feature-request-timing",
    category: "perks",
    title: "Feature-request delivery timing",
    description:
      "A vendor delivery-time promise that this project does not adopt.",
    status: "reference-only",
    target: "settings",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "vendor-early-access",
    category: "perks",
    title: "Early access",
    description:
      "A vendor release-channel promise, tracked only as market context.",
    status: "reference-only",
    target: "settings",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "vendor-future-updates",
    category: "perks",
    title: "Future updates included",
    description:
      "A vendor licensing promise, not an entitlement offered by this prototype.",
    status: "reference-only",
    target: "settings",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
] as const satisfies readonly VendorServiceReference[];

/**
 * These items are explicitly future-facing in the reference source. Keeping
 * them outside `CURRENT_CAPABILITIES` prevents roadmap language from becoming
 * an accidental shipped-feature claim.
 */
export const ROADMAP_CAPABILITIES = [
  {
    id: "roadmap-ios-app",
    title: "iOS app",
    description: "A mobile companion for iOS.",
    status: "roadmap",
    target: "settings",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "roadmap-live-meeting-questions",
    title: "Questions during live meetings",
    description:
      "The pricing page still lists this as future, while detailed recording docs describe it as shipped; tracked as a source conflict, not a product promise.",
    status: "roadmap",
    target: "meetings",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "roadmap-android-app",
    title: "Android app",
    description: "A mobile companion for Android.",
    status: "roadmap",
    target: "settings",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "roadmap-shareable-records",
    title: "Shareable notes and transcripts",
    description:
      "Publish an explicitly selected derivative through a revocable share.",
    status: "roadmap",
    target: "library",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "roadmap-team-plan",
    title: "Team workspace",
    description:
      "A multi-user administration, ownership, and collaboration model.",
    status: "roadmap",
    target: "settings",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "roadmap-app-tagging",
    title: "IDE and chat tagging",
    description:
      "Route explicitly tagged context from supported development and chat tools.",
    status: "roadmap",
    target: "automations",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "roadmap-coding-agent-integration",
    title: "Coding-agent integrations",
    description:
      "Connect approved voice commands to supported local coding agents.",
    status: "roadmap",
    target: "automations",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "roadmap-calendar-integration",
    title: "Calendar integration",
    description:
      "Use authorized event metadata for meeting preparation and reminders.",
    status: "roadmap",
    target: "meetings",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
  {
    id: "roadmap-cli",
    title: "Command-line interface",
    description:
      "Expose bounded workspace operations through a documented local CLI.",
    status: "roadmap",
    target: "automations",
    sourceUrl: CAPABILITY_REFERENCE_URL,
  },
] as const satisfies readonly RoadmapCapability[];
