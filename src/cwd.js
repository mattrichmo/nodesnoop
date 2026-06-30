import { execFileAsync, runCommand } from "./command.js";

export async function getProcessCwd(pid, options = {}) {
  const { runner = execFileAsync } = options;

  try {
    const output = await runCommand(runner, "lsof", [
      "-a",
      "-p",
      String(pid),
      "-d",
      "cwd",
      "-Fn"
    ]);

    const cwdLine = output
      .split(/\r?\n/)
      .find((line) => line.startsWith("n"));

    return cwdLine ? cwdLine.slice(1) : null;
  } catch {
    return null;
  }
}
