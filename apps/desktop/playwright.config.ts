import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: "./e2e",
  fullyParallel: true,
  use: { baseURL: "http://127.0.0.1:1447", viewport: { width: 1100, height: 680 } },
  webServer: {
    command: "pnpm exec vite --host 127.0.0.1 --port 1447 --strictPort",
    url: "http://127.0.0.1:1447", reuseExistingServer: !process.env.CI,
  },
});
