import { expect, test } from "@playwright/test";
import type { Page } from "@playwright/test";
import { createRequire } from "node:module";
import type { AxeStatic } from "axe-core";

const require = createRequire(import.meta.url);
async function catalog(page: Page) {
  await page.addInitScript(() => {
    const speech = {
      installed: ["base", "tiny.en"],
      active: "base" as string | null,
      idle: true,
      job: null as null | { id: string; stage: string; received: number },
    };
    let complete: (() => void) | undefined;
    let fail: ((message: string) => void) | undefined;
    Object.assign(window, {
      isTauri: true,
      completeModel: () => complete?.(),
      failModel: () => fail?.("Download interrupted. Please retry."),
      __TAURI_INTERNALS__: {
        invoke: async (
          cmd: string,
          args: { id: string; offline?: boolean },
        ) => {
          switch (cmd) {
            case "dictation_models":
              return structuredClone(speech);
            case "writing_status":
              return {
                installed: false,
                busy: false,
                installing: false,
                received: 0,
                bytes: 1124352381,
              };
            case "dictation_install": {
              speech.job = {
                id: args.id,
                stage: args.offline ? "importing" : "transferring",
                received: 24000000,
              };
              try {
                await new Promise<void>((resolve, reject) => {
                  complete = resolve;
                  fail = reject;
                });
                speech.installed.push(args.id);
                speech.active = args.id;
              } finally {
                speech.job = null;
              }
              return;
            }
            case "dictation_cancel_setup":
              fail?.("Model setup canceled.");
              return;
            case "dictation_select_model":
              speech.active = args.id;
              return;
            case "dictation_remove_model":
              speech.installed = speech.installed.filter(
                (id) => id !== args.id,
              );
              if (speech.active === args.id) speech.active = null;
              return;
            default:
              throw Error("Unexpected native command " + cmd);
          }
        },
      },
    });
  });
  await page.goto("/#/models");
  await expect(
    page.getByRole("button", { name: "Whisper Base, Multilingual in use" }),
  ).toBeVisible();
}

test("download, cancel, retry, switch and remove keep the control in place", async ({
  page,
}) => {
  await catalog(page);
  const row = page
    .getByRole("region", { name: "Multilingual" })
    .locator(".model-row")
    .filter({ hasText: "Whisper Tiny" });
  const primary = row.locator(".model-primary button");
  const before = await primary.boundingBox();
  const secondary = row.locator(".model-secondary");
  await expect(secondary).toHaveCSS("opacity", "0");
  await row.hover();
  await expect(secondary).toHaveCSS("opacity", "1");
  await row
    .getByRole("button", { name: "Import Whisper Tiny, Multilingual" })
    .focus();
  await page.mouse.move(1, 1);
  await expect(secondary).toHaveCSS("opacity", "1");
  await primary.click();
  await expect(primary).toHaveAttribute("aria-busy", "true");
  await expect(primary.locator("svg")).toHaveCSS(
    "animation-name",
    "vyrra-spin",
  );
  await expect(row).toContainText("30%");
  expect(await primary.boundingBox()).toEqual(before);
  await row.getByRole("button", { name: /Cancel setup/ }).click();
  await expect(row.getByRole("button", { name: /^Download / })).toBeEnabled();
  await primary.click();
  await page.evaluate(() => Reflect.get(window, "failModel")());
  await expect(page.getByRole("alert")).toHaveText(/interrupted/);
  await expect(
    page.getByRole("button", { name: "Whisper Base, Multilingual in use" }),
  ).toBeVisible();
  await primary.click();
  await page.evaluate(() => Reflect.get(window, "completeModel")());
  await expect(primary).toHaveAccessibleName(
    "Whisper Tiny, Multilingual in use",
  );
  expect(await primary.boundingBox()).toEqual(before);
  await page
    .getByRole("button", { name: "Use Whisper Tiny, English only" })
    .click();
  await row.hover();
  const remove = row.getByRole("button", {
    name: "Remove Whisper Tiny, Multilingual",
  });
  await remove.click();
  await page.keyboard.press("Escape");
  await expect(remove).toBeFocused();
  await remove.click();
  await row.getByRole("button", { name: /Confirm removal/ }).click();
  await expect(primary).toHaveAccessibleName(
    "Download Whisper Tiny, Multilingual",
  );
});

test("Find shortcut, text input and Escape restore keyboard focus", async ({
  page,
}) => {
  await catalog(page);
  const find = page.getByRole("button", { name: "Find", exact: true });
  await expect(find.locator("kbd")).toHaveText("/");
  await page.keyboard.press("/");
  const input = page.getByRole("searchbox", { name: "Find a model" });
  await expect(input).toBeFocused();
  await input.fill("turbo");
  await expect(page.locator(".model-row")).toHaveCount(1);
  await input.press("/");
  await expect(page.getByText("No matching models.")).toBeVisible();
  await input.press("Escape");
  await expect(find).toBeFocused();
  await expect(page.locator(".model-row")).toHaveCount(11);
  await page.getByText("Sources & files").click();
  await expect(
    page.getByRole("link", { name: "Qwen tokenizer" }),
  ).toBeVisible();
});

for (const scheme of ["light", "dark"] as const) {
  test(`catalog contrast and keyboard semantics in ${scheme}`, async ({
    page,
  }) => {
    await page.emulateMedia({ colorScheme: scheme });
    await catalog(page);
    await page.addScriptTag({ path: require.resolve("axe-core/axe.min.js") });
    const issues = await page.evaluate(async () => {
      const axe = Reflect.get(window, "axe") as AxeStatic;
      return (await axe.run(document.querySelector("main")!)).violations.map(
        (v) => v.id,
      );
    });
    expect(issues).toEqual([]);
    await expect(page.locator(".model-row").first()).toHaveCSS(
      "min-height",
      "52px",
    );
    await expect(page.locator(".model-name").first()).toHaveCSS(
      "font-size",
      "13px",
    );
  });
}

test("touch layout fits, keeps actions visible, and honors reduced motion during transfer", async ({
  browser,
}) => {
  const context = await browser.newContext({
    viewport: { width: 390, height: 780 },
    hasTouch: true,
    reducedMotion: "reduce",
  });
  const page = await context.newPage();
  await catalog(page);
  const row = page
    .getByRole("region", { name: "Multilingual" })
    .locator(".model-row")
    .first();
  await expect(row.locator(".model-secondary")).toHaveCSS("opacity", "1");
  const primary = row.locator(".model-primary button");
  expect((await primary.boundingBox())?.height).toBeGreaterThanOrEqual(44);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
  await primary.tap();
  await expect(primary).toHaveAttribute("aria-busy", "true");
  await expect(primary.locator("svg")).toHaveCSS("animation-name", "none");
  await expect(row).toContainText("30%");
  await context.close();
});
