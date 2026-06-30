import { execFileAsync, runCommand } from "./command.js";
import { getProcessCwd } from "./cwd.js";

export function shellQuote(value) {
  return `'${String(value).replaceAll("'", "'\\''")}'`;
}

export function appleScriptString(value) {
  return `"${String(value).replaceAll("\\", "\\\\").replaceAll("\"", "\\\"")}"`;
}

export async function openTerminalAt(cwd, options = {}) {
  const { runner = execFileAsync } = options;
  const command = `cd ${shellQuote(cwd)}; clear; pwd`;
  const script = [
    "tell application \"Terminal\"",
    "activate",
    `do script ${appleScriptString(command)}`,
    "end tell"
  ].join("\n");

  await runCommand(runner, "osascript", ["-e", script]);
}

export async function openTerminalForProcess(pid, options = {}) {
  const { cwdRunner = execFileAsync, openRunner = execFileAsync } = options;
  const cwd = await getProcessCwd(pid, { runner: cwdRunner });

  if (!cwd) {
    throw new Error(`Could not read cwd for process ${pid}.`);
  }

  await openTerminalAt(cwd, { runner: openRunner });
  return cwd;
}
