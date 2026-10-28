import { describe, expect, it } from "vitest";
import { isSecretName } from "../../src/models/environment-variable.js";

describe("isSecretName", () => {
  it.each([
    "SECRET_KEY",
    "GITHUB_TOKEN",
    "DB_PASSWORD",
    "DB_PASS",
    "PASS",
    "MYSQL_PASSWD",
    "ENCRYPTION_PASSPHRASE",
    "API_KEY",
    "APIKEY",
    "STRIPE_API_SECRET_KEY",
    "PRIVATE_KEY",
    "PRIVATE-KEY",
    "AWS_CREDENTIALS",
  ])("treats %s as a secret", (name) => {
    expect(isSecretName(name)).toBe(true);
  });

  it.each([
    "DATABASE_URL",
    "PORT",
    "NODE_ENV",
    // `PASS` as a substring must not trigger the heuristic.
    "PASSPORT_URL",
    "COMPASS_API",
    "BYPASS_CACHE",
    "PASSENGER_COUNT",
  ])("treats %s as non-secret", (name) => {
    expect(isSecretName(name)).toBe(false);
  });
});
