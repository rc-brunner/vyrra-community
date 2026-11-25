import { execFileSync } from "node:child_process";
import { mkdir } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium, expect } from "@playwright/test";

const endpoint = "http://127.0.0.1:9222";
const images = resolve("store-screenshots");
const chooseFile = fileURLToPath(new URL("select-file.ps1", import.meta.url));
const audio = fileURLToPath(new URL("blue-notebook.wav", import.meta.url));
await mkdir(images, { recursive: true });
await expect.poll(async () => {
  try {
    return (await fetch(endpoint + "/json/version")).ok;
  } catch {
    return false;
  }
}, { timeout: 45000 }).toBe(true);

const browser = await chromium.connectOverCDP(endpoint);
try {
  const context = browser.contexts()[0];
  const appWindow = () => context.pages().find((page) => {
    const url = new URL(page.url());
    return url.hostname === "tauri.localhost" && !url.hash.includes("indicator");
  });
  await expect.poll(() => Boolean(appWindow()), { timeout: 30000 }).toBe(true);
  const page = appWindow();
  page.on("crash", () => console.log("Windows WebView2 reported a renderer crash."));
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.bringToFront();
  await expect(page.getByRole("heading", { name: "Speak naturally." })).toBeVisible();

  async function capture(name) {
    await page.mouse.move(1400, 880);
    await page.evaluate(() => document.fonts.ready);
    await page.screenshot({ path: resolve(images, name), animations: "disabled" });
  }

  const download = page.getByRole("button", { name: "Download speech model" });
  await expect(download).toBeEnabled({ timeout: 30000 });
  await capture("03-model-setup.png");
  await download.click();
  const start = page.getByRole("button", { name: "Start dictation" });
  await expect(start).toBeEnabled({ timeout: 240000 });
  console.log("The packaged app downloaded and prepared its speech model.");
  await capture("04-ready.png");
  await page.getByRole("button", { name: "More audio options" }).click();
  await page.getByRole("button", { name: "Transcribe WAV" }).click();
  const decodeStarted = Date.now();
  execFileSync("powershell.exe", ["-NoProfile", "-NonInteractive", "-File", chooseFile, audio], { stdio: "inherit", timeout: 45000 });
  const transcript = page.getByRole("textbox", { name: "Transcript", exact: true });
  await expect(transcript).toHaveValue(/blue notebook/i, { timeout: 90000 });
  await expect(transcript).toHaveValue(/design review/i);
  console.log(`The Windows release transcribed the blue notebook and design review phrases in ${((Date.now() - decodeStarted) / 1000).toFixed(1)} seconds including file selection.`);
  await capture("01-dictation.png");
  await page.getByRole("button", { name: "Save to Library" }).click();
  await expect(page.getByText("Saved on this device.")).toBeVisible();
  await page.getByRole("navigation", { name: "Primary", exact: true }).getByRole("link", { name: "Library" }).click();
  await expect(page.getByText(/blue notebook/i).first()).toBeVisible();
  await capture("02-library.png");
  console.log("Saved the decoded transcript and found it in the local library.");
} finally {
  await browser.close();
}
