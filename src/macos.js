import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { execFileAsync, runCommand } from "./command.js";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const APP_NAME = "NodeSnoop.app";

export function defaultOutDir() {
  if (process.platform === "darwin") {
    return path.join(os.homedir(), "Library", "Caches", "nodesnoop");
  }

  return path.join(os.tmpdir(), "nodesnoop");
}

export function builtAppPath(outDir = defaultOutDir()) {
  return path.join(outDir, APP_NAME);
}

export async function buildMenuBarApp(options = {}) {
  const { outDir = defaultOutDir(), runner = execFileAsync } = options;
  const script = path.join(ROOT, "scripts", "build-macos-app.sh");

  await runCommand(runner, "/bin/bash", [script, outDir], { cwd: ROOT });
  return builtAppPath(outDir);
}

export async function openMenuBarApp(options = {}) {
  const { runner = execFileAsync } = options;
  const appPath = await buildMenuBarApp(options);
  await runCommand(runner, "/usr/bin/open", ["-n", appPath]);
  return appPath;
}

export async function installMenuBarApp(options = {}) {
  const {
    targetDir = path.join(os.homedir(), "Applications"),
    runner = execFileAsync
  } = options;
  const appPath = await buildMenuBarApp(options);
  const targetPath = path.join(targetDir, APP_NAME);

  await fs.mkdir(targetDir, { recursive: true });
  await fs.rm(targetPath, { recursive: true, force: true });
  await fs.cp(appPath, targetPath, { recursive: true });
  await runCommand(runner, "/usr/bin/open", [targetPath]);

  return targetPath;
}
