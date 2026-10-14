# zj

Intent-aware navigation and command suggestions for zsh, powered by
[Jev](https://typesafe.ai) and [zoxide](https://github.com/ajeetdsouza/zoxide).

Describe where you want to go or which previous command you want to run.
`zj` shows an inline suggestion. Review it, then press **Enter** to run it.

```text
zj go to payments backend  ⇢ cd -- '/workspace/payments/backend'
zj show recent commits    ⇢ git log --oneline -5
```

Command suggestions come from your history, so the second example requires a
matching command to have been run previously. Jev selects existing candidates;
it does not generate new shell commands.

## Installation

Requirements:

- **zsh 5.9+**
- **Node.js 24+** (runs TypeScript directly) and npm
- A **TypeSafe API key** for Jev ranking
- **zoxide**, recommended for remembered directory ranking

fzf is not required: `zj` displays suggestions inline rather than opening a picker.

```sh
git clone https://github.com/sanai2550/zj.git ~/.local/share/zj
cd ~/.local/share/zj
npm ci
```

Store your API key outside this repository. For example, create a private file:

```sh
mkdir -p ~/.config/zj
touch ~/.config/zj/env.zsh
chmod 600 ~/.config/zj/env.zsh
```

Edit that file with your editor and add:

```zsh
export TYPESAFE_API_KEY='YOUR_TYPESAFE_API_KEY'
```

Add to `~/.zshrc`, after your shell framework and other suggestion plugins:

```zsh
source "$HOME/.config/zj/env.zsh"
source "$HOME/.local/share/zj/zsh/jev-shell-history.plugin.zsh"
```

If using zoxide, initialize it as well:

```zsh
eval "$(zoxide init zsh)"
```

Start a fresh shell:

```sh
exec zsh
```

## Usage

From your workspace, type an intent prefixed with `zj`:

```text
zj go to java payments
zj jump to frontend
zj show recent commits
```

| Key | Behavior |
| --- | --- |
| **Enter** | Accept and execute the displayed `zj` suggestion |
| **→**, **End**, or **Ctrl-E** | Accept at the end of the line, allowing edits before execution |
| **Ctrl-C** | Cancel the current input |

If no current `zj` suggestion is ready, Enter keeps your input and asks you to
wait. Review suggestions before executing them, especially commands from history
that modify or delete data.

`zj` is a prompt trigger, not a standalone executable. Ordinary input still gets
history suggestions, but **Enter runs what you typed**, not the suggestion.
For vi mode, bind Ctrl-E to `end-of-line` if desired.

## Current-folder navigation

`zj` discovers directories **beneath your current working directory**, including
folders you have never visited. No workspace-wide or home-directory scan is used.

- Remembered zoxide descendants are considered first, in frequency/recency order.
- Unvisited folders are discovered breadth-first, up to **four levels** deep.
- Discovery has a **150 ms traversal budget** and a directory candidate limit of
  `JEV_HISTORY_LIMIT` (100 by default). Large trees may omit some folders.
- Hidden folders, symlinks, `node_modules`, `vendor`, `dist`, `build`, `target`,
  and `__pycache__` are skipped during discovery.
- Filesystem discovery works even when zoxide is unavailable.

For explicit `go to`, `cd`, `jump to`, or `navigate to` requests, directories
matching **every requested word** in their relative path take priority. A unique
full-word match is selected directly without an API call. Multiple full matches,
or requests without a full match, use Jev ranking.

The current-folder restriction applies to directory candidates. History commands
remain available regardless of where they were originally run.

## Ranking

Jev receives candidate IDs and answers two questions:

- **Choice:** Which candidate best matches the input? Returns candidate probabilities.
- **Noul:** Does any candidate plausibly match? Helps suppress unrelated suggestions.

The highest-ranked candidate is shown only when the confidence gates permit it.
Zoxide scores are not compared directly with Jev probabilities.

The inline score is Jev's candidate probability, except for deterministic matches:
`1.000` can mean an exact rule match rather than model confidence. Background
requests do not block typing, and stale responses are discarded.

## Privacy and credentials

**Jev ranking sends your typed input and candidate command/path text to the
TypeSafe API.** Candidates can contain sensitive history entries or directory
names. This is not a fully local tool, and candidates are not automatically
redacted. Avoid using it with sensitive shell history.

- Keep API keys outside the repository; never commit your private environment file.
- Do not enable `JEV_DEBUG_LOG` for sensitive sessions: it records typed buffers
  and suggestion output.
- The repository ignores common environment files, private key files, logs,
  shell history, and `node_modules`. Ignore rules do not protect already-tracked files.

## Configuration

Set overrides before sourcing the plugin. The `JEV_` names are retained for
compatibility.

| Variable | Default | Purpose |
| --- | --- | --- |
| `JEV_HISTORY_LIMIT` | `100` | History candidate limit and directory candidate limit |
| `JEV_MIN_CHARS` | `2` | Minimum input/intent length |
| `JEV_THRESHOLD` | `0.5` | Minimum Noul confidence for fuzzy suggestions |
| `JEV_MIN_SCORE` | `0.3` | Minimum top-candidate probability in fuzzy mode |
| `JEV_STRONG_SCORE` | `0.9` | Top probability that can override the Noul threshold |
| `JEV_SHOW_SCORE` | `1` | Display the suggestion score |
| `JEV_HIGHLIGHT` | `fg=8` | Suggestion styling |
| `JEV_NODE` | `node` | Node executable |
| `JEV_MODEL` | SDK default | TypeSafe model override |
| `JEV_DEBUG_LOG` | Unset | Optional sensitive debug log |

## CLI inspection and tests

From the repository directory, with `TYPESAFE_API_KEY` in the environment:

```sh
node src/cli.ts --buffer 'zj go to backend' --json
node src/cli.ts --buffer 'git st' --list 5
node src/cli.ts --help

npm test
npm run typecheck
npm run test:e2e
```

Directory discovery uses the CLI process's current working directory. End-to-end
tests use a temporary history fixture and require an API key.

## Attribution

Built on [mrnugget/jev-shell-history](https://github.com/mrnugget/jev-shell-history),
extended with intent-triggered directory discovery, exact navigation matching,
and Enter-to-accept execution.
