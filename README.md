# 🦙 llama.sh  

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
 (`Models/llama.cpp`, `.llama` state, `.known.llama` registry, `activity-llama.log`)
 and checks/installs `llama-server` (plus `pi` if desired) when missing.
- **Hardware-Aware Auto-Tuning (macOS & Debian/Ubuntu):** Measures real-time available memory (`memory_pressure` on macOS, `/proc/meminfo` on Linux) against the selected `.gguf` file size to automatically configure `--ctx-size`, batch/ubatch sizes, `--fit`, reasoning budgets, and family-specific sampling parameters (Qwen3, Devstral, thinking models, etc.).
- **Built-in Web UI + OpenAI-Compatible API:** Starts `llama-server` with `--alias localLLM`, `--jinja`, and flash attention enabled—ready for immediate browser testing at `http://localhost:8080` or any OpenAI-compatible agent harness.
- **Curated Model Registry & Notes (`.known.llama`):** Add Hugging Face URLs or shorthand paths (`/user/repo/resolve/main/model.gguf`), resume interrupted downloads (`curl -C -`), and attach personal benchmark notes to each model.
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
   
   On first run, `llama.sh` creates `Models/llama.cpp/` and seeds `.known.llama` with a curated list of tested GGUF models and real-world benchmark notes.

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
| `./llama.sh model` | `m`, `select` | Select the active `.gguf` model (with saved notes) |
| `./llama.sh hf <url> [note]` | `add` | Add a Hugging Face URL or `/owner/repo/...` path to `.known.llama` |
| `./llama.sh download [url]` | `d` | Download a model from `.known.llama` or a direct URL |
| `./llama.sh delete` | `rm` | Delete a local `.gguf` file from disk |
| `./llama.sh comment [text]` | `c` | View or update the benchmark note for the active model |
| `./llama.sh list` | `l` | List all known and downloaded models with notes |
| `./llama.sh tail` | `t` | Live-tail `activity-llama.log` (press `Enter` to stop) |
| `./llama.sh log <1-4>` |  | Set `llama-server` log verbosity (`1`–`4`) |
| `./llama.sh port <port>` | `p` | Change listening port (default: `8080`) |
| `./llama.sh version` | `-v`, `--version` | Print script version |

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
- **Core tools:** `bash`, `curl`, `awk`, `ps`, and `lsof` (or `ss` on Linux)
- **Automatic dependency bootstrap:**
  - **`llama.cpp` (`llama-server`):** If not found in `PATH`, `llama.sh` automatically attempts to install it via **Homebrew** (`brew install llama.cpp`) or **`apt-get`** on Debian/Ubuntu, or guides you to build/install it if unavailable in system repositories.
  - **`Pi Coding Agent` (`pi`):** If not found in `PATH` and `npm` is available, `llama.sh` automatically installs `@earendil-works/pi-coding-agent` globally (`npm install -g --ignore-scripts`).

---

## 📄 License

MIT
