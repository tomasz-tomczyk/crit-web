import { defineConfig } from "@playwright/test";

const PORT = process.env.CRIT_WEB_TEST_PORT || "4003";
// 127.0.0.1, not "localhost": macOS resolves localhost to IPv6 ::1 first, but
// the Phoenix/Bandit test server binds IPv4 only → ECONNREFUSED. 127.0.0.1
// works on macOS and CI alike.
const BASE_URL = `http://127.0.0.1:${PORT}`;

// Security/isolation webServer (port 4004). Boots Phoenix with origin
// isolation enabled: PHX_HOST=127.0.0.1.nip.io (canonical) + PREVIEW_HOST
// preview.127.0.0.1.nip.io. nip.io wildcards both names to 127.0.0.1 so they
// share Bandit's loopback listener but the browser treats them as distinct
// origins (matching prod's canonical/preview split). See
// e2e/security.spec.ts.
const SEC_PORT = "4004";
const SEC_CANONICAL_HOST = "127.0.0.1.nip.io";
const SEC_BASE_URL = `http://${SEC_CANONICAL_HOST}:${SEC_PORT}`;

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
      // security.spec.ts has its own project + webServer — exclude it here so
      // it isn't run twice (which would fail in the non-isolated project).
      testIgnore: /security\.spec\.ts/,
      use: { browserName: "chromium" },
    },
    {
      // Security suite runs against its own isolated webServer (port 4004).
      // The baseURL override routes browser navigation in security.spec.ts to
      // the canonical isolated-host URL; the spec targets the preview host
      // explicitly via PREVIEW_ORIGIN constants.
      name: "security-chromium",
      testMatch: /security\.spec\.ts/,
      use: {
        browserName: "chromium",
        baseURL: SEC_BASE_URL,
      },
    },
  ],

  webServer: [
    {
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
    {
      // Isolated Phoenix instance for the security/isolation spec.
      // Shares the same DB (idempotent ecto.migrate) and loopback (Port
      // 4004) as the canonical instance; only PREVIEW_HOST + PHX_HOST differ,
      // enabling HostGate + the canonical→preview 308 redirect.
      command: `MIX_ENV=test mix do ecto.migrate --quiet + phx.server`,
      url: `${SEC_BASE_URL}/health`,
      reuseExistingServer: !process.env.CI,
      timeout: 60_000,
      env: {
        MIX_ENV: "test",
        PORT: SEC_PORT,
        PHX_HOST: SEC_CANONICAL_HOST,
        PREVIEW_HOST: "preview.127.0.0.1.nip.io",
        E2E: "true",
        PHX_SERVER: "true",
        DB_PORT: process.env.DB_PORT || "5432",
      },
    },
  ],
});
