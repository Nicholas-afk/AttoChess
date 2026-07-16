import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import test from "node:test";

test("production output contains the challenge, provenance, and social metadata", async () => {
  const clientAssets = await readdir("dist/client/assets");
  const serverAssets = await readdir("dist/server/ssr/assets");
  const content = await Promise.all([
    ...clientAssets.filter((file) => file.endsWith(".js")).map((file) => readFile(`dist/client/assets/${file}`, "utf8")),
    ...serverAssets.filter((file) => file.endsWith(".js")).map((file) => readFile(`dist/server/ssr/assets/${file}`, "utf8")),
  ]);
  const bundle = content.join("\n");
  assert.match(bundle, /278-Byte Chess Challenge|CAN YOU BEAT/);
  assert((await readFile("dist/client/og.png")).byteLength > 10_000);
  assert.match(await readFile("dist/client/third-party-notices.txt", "utf8"), /Permission is hereby granted/);
});
