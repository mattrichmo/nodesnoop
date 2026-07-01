# NodeSnoop

NodeSnoop finds and manages running Node.js processes from a CLI, a small terminal UI, and a native macOS menu bar app.

## Install

During local development:

```sh
npm install
npm link
```

After publishing:

```sh
npm install -g nodesnoop
```

## CLI

```sh
nodesnoop list
nodesnoop tui
nodesnoop kill all
nodesnoop kill all --force
nodesnoop open <pid>
```

`nodesnoop kill all` sends `SIGTERM` to every detected Node.js process except the `nodesnoop` CLI process itself. Use `--force` to send `SIGKILL`.

`nodesnoop open <pid>` opens Terminal at the process working directory when macOS allows that directory to be read. A process cannot generally be reattached to a new terminal after it is already running unless it was started inside a terminal multiplexer such as `tmux` or `screen`, so NodeSnoop opens the closest useful context: the process cwd.

## TUI

```sh
nodesnoop tui
```

Keys:

- `up` / `down`: move selection
- `k`: kill selected process
- `K`: kill all Node.js processes
- `o`: open Terminal at the selected process cwd
- `r`: refresh
- `q`: quit

## macOS Menu Bar App

Build the native AppKit menu bar app:

```sh
nodesnoop app build
```

By default this builds into `~/Library/Caches/nodesnoop`, which works from a global npm install. For local development output:

```sh
nodesnoop app build --out-dir dist
```

Launch it:

```sh
nodesnoop app open
```

Install it into `~/Applications` and launch it:

```sh
nodesnoop app install
```

The app uses a spruce tree menu bar icon and keeps the menu organized into status, localhost projects, other Node processes, bulk actions, and application sections. It detects project names from nearby `package.json` files, labels common dev servers such as Vite and Next.js, and flags listening localhost ports. Each process has actions to open localhost when available, open Terminal at the project directory, copy its URL/path/PID, or kill it. The menu also includes kill-all, refresh, and Open at Login actions.

Building the macOS app requires Swift and the macOS command line tools.

## Packaging Notes

This package is designed to publish to npm with no runtime dependencies for the CLI/TUI. The macOS app is built locally from included Swift source so the npm package does not need to ship a large Electron runtime or prebuilt binaries per architecture.

## Development

```sh
npm test
npm run app:build
```
