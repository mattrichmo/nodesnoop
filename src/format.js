export function truncate(value, maxLength) {
  const text = String(value ?? "");
  if (text.length <= maxLength) {
    return text;
  }

  return `${text.slice(0, Math.max(0, maxLength - 3))}...`;
}

function pad(value, width) {
  return String(value).padEnd(width, " ");
}

export function formatProcessTable(processes, options = {}) {
  const { maxArgs = 96 } = options;

  if (processes.length === 0) {
    return "No Node.js processes found.";
  }

  const rows = processes.map((processInfo) => ({
    pid: String(processInfo.pid),
    ppid: String(processInfo.ppid),
    stat: processInfo.stat,
    command: processInfo.commandName,
    args: truncate(processInfo.args || processInfo.command, maxArgs)
  }));

  const widths = {
    pid: Math.max(3, ...rows.map((row) => row.pid.length)),
    ppid: Math.max(4, ...rows.map((row) => row.ppid.length)),
    stat: Math.max(4, ...rows.map((row) => row.stat.length)),
    command: Math.max(7, ...rows.map((row) => row.command.length))
  };

  const header = [
    pad("PID", widths.pid),
    pad("PPID", widths.ppid),
    pad("STAT", widths.stat),
    pad("COMMAND", widths.command),
    "ARGS"
  ].join("  ");

  const body = rows
    .map((row) => [
      pad(row.pid, widths.pid),
      pad(row.ppid, widths.ppid),
      pad(row.stat, widths.stat),
      pad(row.command, widths.command),
      row.args
    ].join("  "))
    .join("\n");

  return `${header}\n${body}`;
}

export function formatKillResults(results) {
  if (results.length === 0) {
    return "No Node.js processes found.";
  }

  const killed = results.filter((result) => result.ok);
  const failed = results.filter((result) => !result.ok);
  const lines = [];

  if (killed.length > 0) {
    lines.push(`Sent ${killed[0].signal} to ${killed.length} Node.js process${killed.length === 1 ? "" : "es"}.`);
  }

  for (const result of failed) {
    lines.push(`Failed to kill ${result.pid}: ${result.error}`);
  }

  return lines.join("\n");
}
