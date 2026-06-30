import readline from "node:readline";
import { formatProcessTable } from "./format.js";
import { killAllNodeProcesses, killProcesses, listNodeProcesses } from "./processes.js";
import { openTerminalForProcess } from "./terminal.js";

function clearScreen(output) {
  output.write("\x1b[?25l\x1b[H\x1b[2J");
}

function showCursor(output) {
  output.write("\x1b[?25h");
}

function renderProcessRow(processInfo, selected, output) {
  const row = `${String(processInfo.pid).padEnd(7)} ${String(processInfo.ppid).padEnd(7)} ${processInfo.stat.padEnd(6)} ${processInfo.args || processInfo.command}`;
  output.write(selected ? `\x1b[7m${row}\x1b[0m\n` : `${row}\n`);
}

export async function runTui(options = {}) {
  const {
    input = process.stdin,
    output = process.stdout
  } = options;

  if (!input.isTTY || !output.isTTY) {
    output.write(`${formatProcessTable(await listNodeProcesses())}\n`);
    return 0;
  }

  let selectedIndex = 0;
  let processes = [];
  let message = "";
  let running = true;

  async function refresh() {
    try {
      processes = await listNodeProcesses();
      selectedIndex = Math.min(selectedIndex, Math.max(0, processes.length - 1));
      message = processes.length === 0 ? "No Node.js processes found." : "";
    } catch (error) {
      processes = [];
      selectedIndex = 0;
      message = error.message;
    }
  }

  function render() {
    clearScreen(output);
    output.write("nodesnoop\n");
    output.write("q quit  r refresh  k kill selected  K kill all  o open terminal at cwd\n\n");

    if (processes.length > 0) {
      output.write("PID     PPID    STAT   COMMAND\n");
      processes.forEach((processInfo, index) => {
        renderProcessRow(processInfo, index === selectedIndex, output);
      });
    }

    if (message) {
      output.write(`\n${message}\n`);
    }
  }

  async function stop() {
    running = false;
    input.setRawMode(false);
    showCursor(output);
    output.write("\n");
  }

  async function handleKey(_text, key) {
    if (!running) {
      return;
    }

    if (key.ctrl && key.name === "c") {
      await stop();
      return;
    }

    if (key.name === "q") {
      await stop();
      return;
    }

    if (key.name === "up") {
      selectedIndex = Math.max(0, selectedIndex - 1);
    } else if (key.name === "down") {
      selectedIndex = Math.min(Math.max(0, processes.length - 1), selectedIndex + 1);
    } else if (key.name === "r") {
      await refresh();
    } else if (key.sequence === "K") {
      const { results } = await killAllNodeProcesses();
      const killedCount = results.filter((result) => result.ok).length;
      await refresh();
      message = results.length === 0 ? "No Node.js processes found." : `Sent SIGTERM to ${killedCount} process(es).`;
    } else if (key.name === "k") {
      const selected = processes[selectedIndex];
      if (selected) {
        const [result] = killProcesses([selected]);
        await refresh();
        message = result.ok ? `Sent ${result.signal} to ${result.pid}.` : `Failed to kill ${result.pid}: ${result.error}`;
      }
    } else if (key.name === "o") {
      const selected = processes[selectedIndex];
      if (selected) {
        try {
          const cwd = await openTerminalForProcess(selected.pid);
          message = `Opened Terminal at ${cwd}.`;
        } catch (error) {
          message = error.message;
        }
      }
    }

    render();
  }

  readline.emitKeypressEvents(input);
  input.setRawMode(true);
  input.on("keypress", handleKey);

  await refresh();
  render();

  while (running) {
    await new Promise((resolve) => setTimeout(resolve, 100));
  }

  input.off("keypress", handleKey);
  return 0;
}
