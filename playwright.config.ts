import { defineConfig } from "@playwright/test";

const PORT = process.env.CRIT_WEB_TEST_PORT || "4003";
// 127.0.0.1, not "localhost": macOS resolves localhost to IPv6 ::1 first, but
// the Phoenix/Bandit test server binds IPv4 only → ECONNREFUSED. 127.0.0.1
// works on macOS and CI alike.
const BASE_URL = `http://127.0.0.1:${PORT}`;

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
      // Local Postgres maps host 5433 → container 5432; CI runs Postgres on
      // 5432 and sets no DB_PORT. Forward it so the managed webServer's
      // ecto.create/migrate reaches the right port (otherwise it exits
      // instantly and every spec hits a dead port).
      DB_PORT: process.env.DB_PORT || "5432",
    },
  },
});
