# 🦙 llama.sh  v1.2

## A Self-Contained Local AI Agent Ecosystem

**A lightweight, zero-config Bash manager that turns `llama.cpp` into a self-contained local ecosystem for running,
benchmarking, and experimenting with AI agents on your machine.**

Out of the box, `llama.sh` bootstraps your environment, downloads GGUF models from Hugging Face,
dynamically tunes `llama-server` parameters to match your available RAM,
and exposes both an OpenAI-compatible API and `llama.cpp`'s **built-in Web UI** (`http://localhost:8080`)
so you can start chatting and testing immediately.

When you are ready for full agentic coding workflows inside your IDE, the same local server plugs directly into
**ACP (Agent Client Protocol)** clients (such as JetBrains IDEs, Zed, or Neovim) using
**[Pi Coding Agent](https://github.com)** or **[OpenCode](https://opencode.ai)**.

---

## ✨ Key Features

- **Self-Contained Local Ecosystem:** Automatically sets up your local directory structure
 (`Models/llama.cpp`, `.llama` state, `.known.llama/` registry, `activity-llama.log`)
 and checks/installs `llama-server` (plus `pi` if desired) when missing.
- **Hardware-Aware Auto-Tuning (macOS & Debian/Ubuntu):** Measures real-time available memory (`memory_pressure` on macOS, `/proc/meminfo` on Linux) against the selected `.gguf` file size to automatically configure `--ctx-size`, batch/ubatch sizes, `--fit`, reasoning budgets, and family-specific sampling parameters (Qwen3, Devstral, thinking models, etc.).
- **Built-in Web UI + OpenAI-Compatible API:** Starts `llama-server` with `--alias localLLM`, `--jinja`, and flash attention enabled—ready for immediate browser testing at `http://localhost:8080` or any OpenAI-compatible agent harness.
- **Curated Model Registry & Notes (`.known.llama/`):** Add Hugging Face URLs or shorthand paths (`/user/repo/resolve/main/model.gguf`), resume interrupted downloads (`curl -C -`), and attach personal multi-line benchmark notes to each model, edited inline or in your favorite editor.
- **Instant Filtering:** Find models by a simple case-insensitive substring (`./llama.sh m qwen`), matched on name, URL, and the first line of your notes.
- **Dual Mode (CLI & Interactive Shell):** Run quick one-liner commands (`./llama.sh r`) or launch `./llama.sh` with no arguments for a 3-column interactive menu with live log tailing.

---

## 🚀 Quick Start

1. **Download the script** into a dedicated directory (e.g., `~/AI/`):

   ```bash
   mkdir -p ~/AI && cd ~/AI
   curl -O https://raw.githubusercontent.com/marcobalestra/llama-sh/main/llama.sh
   chmod +x llama.sh
   ```

2. **Launch the interactive shell:**

   `./llama.sh`
   
   On first run, `llama.sh` creates `Models/llama.cpp/` and seeds `.known.llama/` with a curated list of tested GGUF models and real-world benchmark notes.

3. **Download, select, and start:**
   - Run `d` (`download`) to pick a model from the registry or paste any `.gguf` URL.
   - Run `m` (`model`) to select the downloaded `.gguf`.
   - Run `s` (`start`) to launch `llama-server` and watch the live startup log (press `Enter` to exit log view).

---

## 🛠️ Commands & Usage

Run `./llama.sh` without arguments for the interactive menu, or pass a command directly:

| Command | Alias | Description |
| :--- | :--- | :--- |
| `./llama.sh` | *(none)* | Open the interactive shell |
| `./llama.sh help` | `-h`, `--help` | List of available commands |
| `./llama.sh start` | `s` | Start `llama-server` with auto-tuned presets |
| `./llama.sh stop` | `q`, `.` | Gracefully stop `llama-server` |
| `./llama.sh restart` | `r` | Restart `llama-server` |
| `./llama.sh status` | `h` | Show active model, computed RAM/context preset, port, and PID |
| `./llama.sh model [filter]` | `m`, `select` | Select the active `.gguf` model (with saved notes) |
| `./llama.sh hf <url> [note]` | `add` | Add a Hugging Face URL or `/owner/repo/...` path to `.known.llama/` |
| `./llama.sh download [filter\|url]` | `d` | Download a model from `.known.llama/`, a direct URL, or a Hugging Face `/owner/repo/...` path |
| `./llama.sh delete [filter]` | `rm` | Delete a local `.gguf` file from disk |
| `./llama.sh comment [text]` | `c` | Replace the note of the active model with `text`; without `text`, open the notes menu |
| `./llama.sh list [filter]` | `l` | List all known and downloaded models with notes |
| `./llama.sh editor [cmd]` | `ed` | Show or set the editor used for notes |
| `./llama.sh tail` | `t` | Live-tail `activity-llama.log` (press `Enter` to stop) |
| `./llama.sh log <1-4>` |  | Set `llama-server` log verbosity (`1`–`4`) |
| `./llama.sh port <port>` | `p` | Change listening port (default: `8080`) |
| `./llama.sh version` | `-v`, `--version` | Print script version |

---

## 📚 Known Models, Notes & Filters

### The `.known.llama/` registry

Per-model metadata lives in the `.known.llama/` directory, next to the script.
Each model `<filename.gguf>` has two optional plain-text files:

| File | Content |
| :--- | :--- |
| `.known.llama/<filename.gguf>.url` | Direct download URL |
| `.known.llama/<filename.gguf>.txt` | Notes and benchmarks (multi-line). Lists show the **first line** as preview (`ⓘ`), followed by `[+n]` when `n` more non-empty lines exist |

Both files are plain text and can be edited by hand.

**Upgrading from v1.x:** the old `.known.llama` TSV file is converted automatically on first run.
The old file is removed once the conversion has succeeded; if anything fails, it is left untouched.
Default models are added only when the directory is new or empty.

### Notes (`c`)

```bash
./llama.sh c "Fast, good tool usage"   # replaces the notes of the active model
./llama.sh c                           # menu: View, Edit, Replace, Add, Delete, Model
```

The menu acts on the active model. *Model* switches to another model (any known or local one,
using the usual filter rules) and shows the menu again for it, so you can annotate models
you have not selected, or have not even downloaded yet.

*Edit* opens the notes file in your editor, chosen in this order: saved preference, `$VISUAL`, `$EDITOR`, `vi`, `nano`.

```bash
./llama.sh editor              # show saved and effective editor
./llama.sh editor "code -w"    # save preference (stored in the 5th line of .llama)
./llama.sh editor default      # clear preference
```

GUI editors must wait for the file to be closed (e.g. `code -w`).
Paths with spaces inside the editor command are not supported.

### Filters

`list`, `model`, `download` and `delete` accept an optional filter:

```bash
./llama.sh l qwen        # known models
./llama.sh m 9b          # local models
./llama.sh d gemma       # downloadable models (an http(s):// argument is a URL, anything else a filter)
./llama.sh rm phi        # local models
```

- A filter is a case-insensitive substring matched on file name, URL, and the first line of the notes.
- Without a filter, lists of up to 10 entries are shown as they are. Longer lists ask for a filter first (Enter = show all). The same applies in the interactive shell.
- `m` selects immediately when a filter matches a single model; `d` asks for confirmation before downloading.
- `d` also accepts a Hugging Face path (`./llama.sh d /owner/repo/resolve/main/model.gguf`), exactly like `add`: a leading `/` gets the `https://huggingface.co` host and `/blob/` links become `/resolve/`.
- The v1.1 `l url` option is gone: the filter already searches URLs, so `l http` behaves the same.

---

## 🌐 From Web UI to IDE Integration via ACP (Pi or OpenCode)

### 1. Immediate Testing via Web UI

Once `llama-server` is active, open **`http://localhost:8080`** in your browser.

`llama.cpp`'s native web interface lets you test prompts, system instructions, and tool-calling behavior right away without installing anything else.

### 2. Connecting Pi or OpenCode to `localLLM`

Both **Pi** and **OpenCode** can talk to your local `llama-server` over its OpenAI-compatible
endpoint (`http://localhost:8080/v1`) using the fixed alias `localLLM`
so switching models in `llama.sh` requires zero config changes in your agent).

#### **Pi (`~/.pi/agent/models.json`):**

  ```json
  {
    "providers": {
      "llamacpp": {
        "baseUrl": "http://localhost:8080/v1",
        "api": "openai-completions",
        "apiKey": "local",
        "models": [
          {
            "id": "localLLM",
            "name": "Local llama.cpp",
            "reasoning": false,
            "input": ["text"],
            "contextWindow": 20480,
            "maxTokens": 4096
          }
        ]
      }
    }
  }
  ```

#### **OpenCode (`~/.config/opencode/opencode.json`):**

  ```json
  {
    "$schema": "https://opencode.ai/config.json",
    "provider": {
      "llamacpp": {
        "npm": "@ai-sdk/openai-compatible",
        "name": "llama.cpp (local)",
        "options": {
          "baseURL": "http://localhost:8080/v1",
          "apiKey": "local"
        },
        "models": {
          "localLLM": {
            "name": "Local llama.cpp",
            "tools": true
          }
        }
      }
    }
  }
  ```

### 3. IDE Integration via ACP (`~/.jetbrains/acp.json`)

Wire **Pi** or **OpenCode** into any ACP-compatible IDE (such as WebStorm, IntelliJ IDEA, or Zed):

```json
{
  "agent_servers": {
    "Pi (Local)": {
      "command": "pi",
      "args": ["--acp", "--provider", "llamacpp", "--model", "localLLM"]
    },
    "OpenCode (Local)": {
      "command": "opencode",
      "args": ["acp", "--model", "llamacpp/localLLM"]
    }
  }
}
```

---

## 💻 Requirements

- **OS:** macOS (Apple Silicon recommended) or Linux (Debian/Ubuntu)
- **Core tools:** `bash` (3.2+), `curl`, `awk`, `ps`, and `lsof` (or `ss` on Linux)
- **Automatic dependency bootstrap:**
  - **`llama.cpp` (`llama-server`):** If not found in `PATH`, `llama.sh` automatically attempts to install it via **Homebrew** (`brew install llama.cpp`) or **`apt-get`** on Debian/Ubuntu, or guides you to build/install it if unavailable in system repositories.
  - **`Pi Coding Agent` (`pi`):** If not found in `PATH` and `npm` is available, `llama.sh` automatically installs `@earendil-works/pi-coding-agent` globally (`npm install -g --ignore-scripts`).

---

## 📄 License

MIT