import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const tokensCss = readFileSync(
  resolve(process.cwd(), "../../packages/design-tokens/src/tokens.css"),
  "utf8",
);

const themes = ["light", "dark"] as const;

type Oklch = { l: number; c: number; h: number };

function parseTheme(theme: (typeof themes)[number]) {
  const block = tokensCss.match(
    new RegExp(`\\[data-appearance="${theme}"\\]\\s*\\{([^}]+)\\}`),
  )?.[1];

  if (!block) throw new Error(`Missing token block for ${theme}`);

  const values = new Map<string, Oklch>();

  for (const match of block.matchAll(
    /--pvw-([\w-]+):\s*oklch\(([\d.]+)\s+([\d.]+)\s+([\d.]+)\)/g,
  )) {
    const [, name, l, c, h] = match;
    if (name && l && c && h) {
      values.set(name, {
        l: Number(l),
        c: Number(c),
        h: Number(h),
      });
    }
  }

  return values;
}

function relativeLuminance({ l, c, h }: Oklch): number {
  const radians = (h * Math.PI) / 180;
  const a = c * Math.cos(radians);
  const b = c * Math.sin(radians);
  const lPrime = l + 0.3963377774 * a + 0.2158037573 * b;
  const mPrime = l - 0.1055613458 * a - 0.0638541728 * b;
  const sPrime = l - 0.0894841775 * a - 1.291485548 * b;
  const lCube = lPrime ** 3;
  const mCube = mPrime ** 3;
  const sCube = sPrime ** 3;
  const red = Math.min(
    1,
    Math.max(
      0,
      4.0767416621 * lCube -
        3.3077115913 * mCube +
        0.2309699292 * sCube,
    ),
  );
  const green = Math.min(
    1,
    Math.max(
      0,
      -1.2684380046 * lCube +
        2.6097574011 * mCube -
        0.3413193965 * sCube,
    ),
  );
  const blue = Math.min(
    1,
    Math.max(
      0,
      -0.0041960863 * lCube -
        0.7034186147 * mCube +
        1.707614701 * sCube,
    ),
  );

  return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
}

function contrastRatio(foreground: Oklch, background: Oklch): number {
  const foregroundLuminance = relativeLuminance(foreground);
  const backgroundLuminance = relativeLuminance(background);
  const lighter = Math.max(foregroundLuminance, backgroundLuminance);
  const darker = Math.min(foregroundLuminance, backgroundLuminance);
  return (lighter + 0.05) / (darker + 0.05);
}

function token(
  values: Map<string, Oklch>,
  theme: string,
  name: string,
): Oklch {
  const value = values.get(name);
  if (!value) throw new Error(`Missing ${name} token for ${theme}`);
  return value;
}

describe("semantic color-token contrast", () => {
  it.each(themes)(
    "%s keeps text and status pairs at WCAG AA contrast",
    (theme) => {
      const values = parseTheme(theme);
      const textPairs = [
        ["ink", "canvas"],
        ["ink", "surface"],
        ["ink-soft", "canvas"],
        ["ink-soft", "surface"],
        ["ink-faint", "canvas"],
        ["ink-faint", "surface"],
        ["on-accent", "accent"],
        ["success", "success-soft"],
        ["warning", "warning-soft"],
        ["danger", "danger-soft"],
        ["info", "info-soft"],
      ] as const;

      for (const [foreground, background] of textPairs) {
        expect(
          contrastRatio(
            token(values, theme, foreground),
            token(values, theme, background),
          ),
          `${theme}: ${foreground} on ${background}`,
        ).toBeGreaterThanOrEqual(4.5);
      }
    },
  );

  it.each(themes)(
    "%s keeps focus and strong boundaries visible",
    (theme) => {
      const values = parseTheme(theme);
      const nonTextPairs = [
        ["focus", "canvas"],
        ["focus", "surface"],
        ["line-strong", "canvas"],
        ["line-strong", "surface"],
      ] as const;

      for (const [foreground, background] of nonTextPairs) {
        expect(
          contrastRatio(
            token(values, theme, foreground),
            token(values, theme, background),
          ),
          `${theme}: ${foreground} on ${background}`,
        ).toBeGreaterThanOrEqual(3);
      }
    },
  );

  it.each(["forest", "indigo", "ocean", "plum", "ember"])(
    "defines the %s accent independently of appearance",
    (accent) => {
      expect(tokensCss).toContain(`[data-accent="${accent}"]`);
    },
  );
});
