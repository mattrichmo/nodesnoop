import path from "node:path";
import { execFileAsync, runCommand } from "./command.js";

const PS_ARGS = ["-axo", "pid=,ppid=,stat=,comm=,args="];
const NODE_COMMANDS = new Set(["node", "nodejs"]);

export function parsePsLine(line) {
  const match = line.match(/^\s*(\d+)\s+(\d+)\s+(\S+)\s+(\S+)(?:\s+(.*))?$/);
  if (!match) {
    return null;
  }

  const [, pid, ppid, stat, command, args = ""] = match;
  const commandName = path.basename(command).toLowerCase();

  return {
    pid: Number(pid),
    ppid: Number(ppid),
    stat,
    command,
    commandName,
    args: args.trim(),
    raw: line
  };
}

export function isNodeProcess(processInfo) {
  return NODE_COMMANDS.has(processInfo.commandName);
}

export function parsePsOutput(output, options = {}) {
  const { currentPid = process.pid, includeSelf = false } = options;

  return output
    .split(/\r?\n/)
    .map((line) => parsePsLine(line))
    .filter(Boolean)
    .filter((processInfo) => isNodeProcess(processInfo))
    .filter((processInfo) => includeSelf || processInfo.pid !== currentPid);
}

export async function listNodeProcesses(options = {}) {
  const { runner = execFileAsync, currentPid = process.pid, includeSelf = false } = options;
  let output;

  try {
    output = await runCommand(runner, "ps", PS_ARGS);
  } catch (error) {
    throw new Error(`Unable to inspect processes with ps: ${error.message}`, {
      cause: error
    });
  }

  return parsePsOutput(output, { currentPid, includeSelf });
}

export function killProcesses(processes, options = {}) {
  const {
    signal = "SIGTERM",
    killer = process.kill,
    currentPid = process.pid,
    includeSelf = false
  } = options;

  return processes
    .filter((processInfo) => includeSelf || processInfo.pid !== currentPid)
    .map((processInfo) => {
      try {
        killer(processInfo.pid, signal);
        return {
          ok: true,
          pid: processInfo.pid,
          signal
        };
      } catch (error) {
        return {
          ok: false,
          pid: processInfo.pid,
          signal,
          error: error.message,
          code: error.code
        };
      }
    });
}

export async function killAllNodeProcesses(options = {}) {
  const processes = await listNodeProcesses(options);
  const results = killProcesses(processes, options);

  return {
    processes,
    results
  };
}
