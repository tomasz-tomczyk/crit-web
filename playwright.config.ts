import { defineConfig } from "@playwright/test";

const PORT = process.env.CRIT_WEB_TEST_PORT || "4003";
const BASE_URL = `http://localhost:${PORT}`;

export default defineConfig({
  testDir: "./e2e",
  fullyParallel: false,
  retries: 0,
  workers: 1,
  reporter: [["html", { open: "never" }], ["list"]],

  use: {
    baseURL: BASE_URL,
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
  },

  projects: [
    {
      name: "chromium",
      use: { browserName: "chromium" },
    },
  ],

  webServer: {
    command: `MIX_ENV=test mix do ecto.create --quiet + ecto.migrate --quiet + phx.server`,
    url: `${BASE_URL}/health`,
    reuseExistingServer: !process.env.CI,
    timeout: 60_000,
    env: {
      MIX_ENV: "test",
      PORT: PORT,
      E2E: "true",
      PHX_SERVER: "true",
    },
  },
});
