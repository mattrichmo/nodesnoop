import assert from "node:assert/strict";
import test from "node:test";
import { appleScriptString, shellQuote } from "../src/terminal.js";

test("shellQuote quotes paths for a shell cd command", () => {
  assert.equal(shellQuote("/tmp/it's here"), "'/tmp/it'\\''s here'");
});

test("appleScriptString escapes quotes and backslashes", () => {
  assert.equal(appleScriptString("cd \"a\\b\""), "\"cd \\\"a\\\\b\\\"\"");
});
