import { execFile } from "node:child_process";
import { promisify } from "node:util";

export const execFileAsync = promisify(execFile);

export async function runCommand(runner, command, args = [], options = {}) {
  const result = await runner(command, args, {
    maxBuffer: 10 * 1024 * 1024,
    ...options
  });

  if (typeof result === "string") {
    return result;
  }

  if (Buffer.isBuffer(result)) {
    return result.toString("utf8");
  }

  return result?.stdout?.toString?.("utf8") ?? result?.stdout ?? "";
}
