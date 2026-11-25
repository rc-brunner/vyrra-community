import { expect, test, type Page } from "@playwright/test";
import { mkdir } from "node:fs/promises";
import { join } from "node:path";

async function openLibrary(page: Page, theme: "light" | "dark") {
  await page.addInitScript((theme) => {
    localStorage.setItem("pvw.appearance.theme", theme);
    const entries = [
      { id: 2, text: "Please bring the blue notebook to the meeting on Friday.", pinned: false, archived: false, createdAt: 1764000000000 },
      { id: 1, text: "Can we move the catch-up to Thursday afternoon? I’ll send the revised drawings after lunch so we can spend the meeting on the two questions we left open.", pinned: false, archived: false, createdAt: 1764000010000 },
    ];
    Object.assign(window, { isTauri: true, __TAURI_INTERNALS__: { invoke: async (cmd: string, args: { id: number; pinned?: boolean | null; archived?: boolean | null }) => {
      if (cmd === "dictation_entries") return structuredClone(entries);
      if (cmd === "dictation_mark") {
        const e = entries.find(v => v.id === args.id)!;
        if (args.pinned != null) e.pinned = args.pinned;
        if (args.archived != null) e.archived = args.archived;
        return;
      }
      if (cmd === "dictation_status") return { phase: "idle", model: "ready", elapsedMs: 0, level: 0, text: "", revision: 0, error: null, delivery: null };
      throw Error("Unexpected IPC command: " + cmd);
    } } });
  }, theme);
  await page.goto("/#/library");
  await expect(page.getByRole("article")).toHaveCount(2);
}

for (const theme of ["light", "dark"] as const) {
  test(`stable hover, keyboard disclosure and reversible archive in ${theme}`, async ({ page }) => {
    await openLibrary(page, theme);
    const row = page.getByRole("article").first();
    const title = row.getByRole("button", { expanded: false });
    const pin = row.getByRole("button", { name: "Pin transcript" });
    const archive = row.getByRole("button", { name: "Archive transcript" });
    const bounds = await title.boundingBox();
    await expect(pin).toHaveCSS("opacity", "0");
    const output = process.env.VYRRA_DESIGN_PROOF;
    if (output) {
      await mkdir(output, { recursive: true });
      await page.screenshot({ path: join(output, theme + "-rest.png") });
    }
    await title.hover();
    await expect(pin).toHaveCSS("opacity", "1");
    expect(await title.boundingBox()).toEqual(bounds);
    if (output) await page.screenshot({ path: join(output, theme + "-hover.png") });
    await page.mouse.move(2, 2);
    await expect(pin).toHaveCSS("opacity", "0");
    await title.focus();
    await expect(pin).toHaveCSS("opacity", "1");
    await page.keyboard.press("Tab");
    await expect(pin).toBeFocused();
    await page.keyboard.press("Space");
    await expect(row.getByRole("button", { name: "Unpin transcript" })).toHaveAttribute("aria-pressed", "true");
    await archive.click();
    await page.getByRole("button", { name: "Archive", exact: true }).click();
    await expect(page.getByRole("article")).toHaveCount(1);
    await page.getByRole("article").hover();
    await page.getByRole("button", { name: "Restore transcript" }).click();
    await page.getByRole("button", { name: "Transcripts", exact: true }).click();
    await expect(page.getByRole("article")).toHaveCount(2);
  });
}

test("coarse pointer and long transcripts stay usable at 390 and 320 CSS pixels", async ({ browser }) => {
  const context = await browser.newContext({ hasTouch: true, isMobile: true, viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
  const page = await context.newPage();
  await openLibrary(page, "light");
  for (const width of [390, 320]) {
    await page.setViewportSize({ width, height: 844 });
    const action = page.getByRole("button", { name: "Pin transcript" }).last();
    await expect(action).toHaveCSS("opacity", "1");
    const rect = await action.boundingBox();
    expect(rect!.width).toBeGreaterThanOrEqual(44);
    expect(rect!.height).toBeGreaterThanOrEqual(44);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
  }
  await page.getByRole("button", { expanded: false }).last().tap();
  await expect(page.getByRole("textbox").last()).toHaveValue(/Thursday/);
  await context.close();
});

test("Reduce Motion removes displacement and transition time", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await openLibrary(page, "dark");
  const pin = page.getByRole("button", { name: "Pin transcript" }).first();
  await expect(pin).toHaveCSS("transform", "none");
  await page.getByRole("article").first().hover();
  await expect(pin).toHaveCSS("transition-duration", "0s");
  await expect(pin).toHaveCSS("opacity", "1");
});

test("record the desktop disclosure for visual review", async ({ browser }) => {
  const output = process.env.VYRRA_DESIGN_PROOF;
  test.skip(!output, "Video is only needed for a visual review.");
  const context = await browser.newContext({ viewport: { width: 1100, height: 680 }, recordVideo: { dir: output!, size: { width: 1100, height: 680 } } });
  const page = await context.newPage();
  await openLibrary(page, "dark");
  const rows = page.getByRole("article");
  await page.waitForTimeout(600);
  await rows.first().hover();
  await page.waitForTimeout(1050);
  await rows.last().hover();
  await page.waitForTimeout(850);
  await page.mouse.move(260, 320);
  await page.waitForTimeout(550);
  await context.close();
  await page.video()!.saveAs(join(output!, "library-disclosure.webm"));
  await page.video()!.delete();
});

test("keyboard focus shows a tooltip and Escape dismisses it",async({page})=>{
  await openLibrary(page,"dark");const pin=page.getByRole("button",{name:"Pin transcript"}).first();await pin.focus();
  await expect(page.getByRole("tooltip")).toHaveText("Pin transcript");await page.keyboard.press("Escape");await expect(page.getByRole("tooltip")).toHaveCount(0);await expect(pin).toBeFocused();
});
