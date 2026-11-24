import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

import { RecordingIndicator } from "./components/RecordingIndicator";
import { App } from "./App";
import "./styles.css";

const rootElement = document.getElementById("root");

if (!rootElement) {
  throw new Error("Application root is missing");
}

createRoot(rootElement).render(
  <StrictMode>
    {window.location.hash === "#/recording-indicator" ? <RecordingIndicator /> : <App />}
  </StrictMode>,
);
