import assert from "node:assert/strict";
import test from "node:test";
import {
  killAllNodeProcesses,
  killProcesses,
  listNodeProcesses,
  parsePsOutput
} from "../src/processes.js";

const FIXTURE = `
  101     1 S    /usr/local/bin/node /usr/local/bin/vite --host
  102     1 S    /bin/zsh -l
  103   101 S    /opt/homebrew/bin/node /Users/me/app/server.js
  104     1 S    /usr/bin/python3 script.py
`;

test("parsePsOutput returns node processes only", () => {
  const processes = parsePsOutput(FIXTURE, { currentPid: 999 });

  assert.deepEqual(processes.map((processInfo) => processInfo.pid), [101, 103]);
  assert.equal(processes[0].commandName, "node");
  assert.equal(processes[0].args, "/usr/local/bin/vite --host");
});

test("parsePsOutput excludes the current process by default", () => {
  const processes = parsePsOutput(FIXTURE, { currentPid: 101 });

  assert.deepEqual(processes.map((processInfo) => processInfo.pid), [103]);
});

test("listNodeProcesses accepts an injected runner", async () => {
  const processes = await listNodeProcesses({
    currentPid: 999,
    runner: async () => ({ stdout: FIXTURE })
  });

  assert.deepEqual(processes.map((processInfo) => processInfo.pid), [101, 103]);
});

test("killProcesses reports successes and failures", () => {
  const killed = [];
  const results = killProcesses(
    [
      { pid: 101 },
      { pid: 103 }
    ],
    {
      killer(pid, signal) {
        if (pid === 103) {
          const error = new Error("not allowed");
          error.code = "EPERM";
          throw error;
        }

        killed.push([pid, signal]);
      },
      signal: "SIGKILL",
      currentPid: 999
    }
  );

  assert.deepEqual(killed, [[101, "SIGKILL"]]);
  assert.equal(results[0].ok, true);
  assert.equal(results[1].ok, false);
  assert.equal(results[1].code, "EPERM");
});

test("killAllNodeProcesses lists before killing", async () => {
  const killed = [];
  const result = await killAllNodeProcesses({
    currentPid: 999,
    runner: async () => FIXTURE,
    killer(pid, signal) {
      killed.push([pid, signal]);
    }
  });

  assert.deepEqual(result.processes.map((processInfo) => processInfo.pid), [101, 103]);
  assert.deepEqual(killed, [
    [101, "SIGTERM"],
    [103, "SIGTERM"]
  ]);
});
