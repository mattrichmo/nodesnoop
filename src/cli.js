import process from "node:process";
import path from "node:path";
import { formatKillResults, formatProcessTable } from "./format.js";
import { buildMenuBarApp, installMenuBarApp, openMenuBarApp } from "./macos.js";
import { killAllNodeProcesses, listNodeProcesses } from "./processes.js";
import { openTerminalForProcess } from "./terminal.js";
import { runTui } from "./tui.js";

function printHelp(output) {
  output.write(`nodesnoop

Usage:
  nodesnoop list [--json]
  nodesnoop tui
  nodesnoop kill all [--force|--signal <signal>] [--dry-run] [--json]
  nodesnoop open <pid>
  nodesnoop app build [--out-dir <dir>]
  nodesnoop app open [--out-dir <dir>]
  nodesnoop app install [--out-dir <dir>]

Commands:
  list              Show running Node.js processes.
  tui               Open the interactive terminal UI.
  kill all          Send a signal to all running Node.js processes.
  open <pid>        Open Terminal at a process working directory when readable.
  app build         Build the native macOS menu bar app.
  app open          Build and launch the menu bar app.
  app install       Install the menu bar app into ~/Applications and launch it.
`);
}

function parseKillArgs(args) {
  const options = {
    signal: "SIGTERM",
    dryRun: false,
    json: false
  };

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];

    if (arg === "--force" || arg === "-9") {
      options.signal = "SIGKILL";
    } else if (arg === "--signal" || arg === "-s") {
      options.signal = args[index + 1] ?? options.signal;
      index += 1;
    } else if (arg === "--dry-run") {
      options.dryRun = true;
    } else if (arg === "--json") {
      options.json = true;
    }
  }

  return options;
}

function parseAppArgs(args) {
  const options = {};

  for (let index = 0; index < args.length; index += 1) {
    if (args[index] === "--out-dir") {
      const outDir = args[index + 1];
      if (outDir) {
        options.outDir = path.resolve(process.cwd(), outDir);
      }
      index += 1;
    }
  }

  return options;
}

export async function runCli(argv = process.argv.slice(2), io = {}) {
  const {
    stdout = process.stdout,
    stderr = process.stderr
  } = io;

  const [command = "list", ...args] = argv;

  try {
    if (command === "help" || command === "--help" || command === "-h") {
      printHelp(stdout);
      return 0;
    }

    if (command === "list" || command === "ls") {
      const json = args.includes("--json");
      const processes = await listNodeProcesses();
      stdout.write(json ? `${JSON.stringify(processes, null, 2)}\n` : `${formatProcessTable(processes)}\n`);
      return 0;
    }

    if (command === "tui" || command === "top") {
      return await runTui();
    }

    if (command === "kill" || command === "kill-all") {
      const killTarget = command === "kill-all" ? "all" : args.shift();
      if (killTarget !== "all") {
        stderr.write("Usage: nodesnoop kill all [--force|--signal <signal>] [--dry-run]\n");
        return 1;
      }

      const options = parseKillArgs(args);
      const processes = await listNodeProcesses();

      if (options.dryRun) {
        stdout.write(`${formatProcessTable(processes)}\n`);
        return 0;
      }

      const result = await killAllNodeProcesses({ signal: options.signal });
      stdout.write(options.json ? `${JSON.stringify(result, null, 2)}\n` : `${formatKillResults(result.results)}\n`);
      return result.results.some((killResult) => !killResult.ok) ? 1 : 0;
    }

    if (command === "open") {
      const pid = Number(args[0]);
      if (!Number.isInteger(pid) || pid <= 0) {
        stderr.write("Usage: nodesnoop open <pid>\n");
        return 1;
      }

      const cwd = await openTerminalForProcess(pid);
      stdout.write(`Opened Terminal at ${cwd}\n`);
      return 0;
    }

    if (command === "app" || command === "menubar") {
      const appCommand = command === "menubar" ? "open" : args[0];
      const appOptions = parseAppArgs(command === "menubar" ? args : args.slice(1));

      if (appCommand === "build") {
        const appPath = await buildMenuBarApp(appOptions);
        stdout.write(`Built ${appPath}\n`);
        return 0;
      }

      if (appCommand === "open") {
        const appPath = await openMenuBarApp(appOptions);
        stdout.write(`Opened ${appPath}\n`);
        return 0;
      }

      if (appCommand === "install") {
        const appPath = await installMenuBarApp(appOptions);
        stdout.write(`Installed ${appPath}\n`);
        return 0;
      }

      stderr.write("Usage: nodesnoop app <build|open|install>\n");
      return 1;
    }

    stderr.write(`Unknown command: ${command}\n\n`);
    printHelp(stderr);
    return 1;
  } catch (error) {
    stderr.write(`${error.message}\n`);
    return 1;
  }
}
