import { invoke } from "@tauri-apps/api/core";
import speechManifest from "../../speech-models.json";

export const speechModels = speechManifest;
export const writer = {
  id: "qwen",
  name: "Qwen 2.5 · 1.5B",
  bytes: 1_124_352_381,
};
export type ModelJob = {
  id: string;
  stage: "choosing" | "transferring" | "importing" | "verifying";
  received: number;
};
export interface ModelStatus {
  installed: string[];
  active: string | null;
  job: ModelJob | null;
  idle: boolean;
}
export interface WriterStatus {
  installed: boolean;
  busy: boolean;
  installing: boolean;
  received: number;
  bytes: number;
}
export const modelStatus = () => invoke<ModelStatus>("dictation_models");
export const writerStatus = () => invoke<WriterStatus>("writing_status");
export function formatSize(bytes: number) {
  return bytes < 1e9
    ? `${Math.round(bytes / 1e6)} MB`
    : `${(bytes / 1e9).toFixed(2)} GB`;
}
export function modelAction(
  id: string,
  action: "download" | "import" | "use" | "remove" | "cancel",
) {
  const writing = id === writer.id;
  switch (action) {
    case "download":
    case "import":
      return invoke<void>(writing ? "writing_install" : "dictation_install", {
        id,
        offline: action === "import",
      });
    case "use":
      return invoke<void>("dictation_select_model", { id });
    case "remove":
      return invoke<void>(
        writing ? "writing_remove" : "dictation_remove_model",
        { id },
      );
    case "cancel":
      return invoke<void>(
        writing ? "writing_cancel" : "dictation_cancel_setup",
      );
  }
}
