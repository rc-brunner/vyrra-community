import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

import { RecordingIndicator } from "./components/RecordingIndicator";
import { MeetingIndicator } from "./pages/MeetingsPage";
import { App } from "./App";
import "./styles.css";

const rootElement = document.getElementById("root");

if (!rootElement) {
  throw new Error("Application root is missing");
}

createRoot(rootElement).render(
  <StrictMode>
    {window.location.hash === "#/recording-indicator" ? <RecordingIndicator /> : window.location.hash === "#/meeting-indicator" ? <MeetingIndicator /> : <App />}
  </StrictMode>,
);
