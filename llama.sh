#!/bin/bash

THIS_SCRIPT_VERSION="v1.2"
THIS_SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$THIS_SCRIPT_SOURCE" ]]; do
	DIR="$(cd -P "$(dirname "$THIS_SCRIPT_SOURCE")" && pwd)"
	THIS_SCRIPT_SOURCE="$(readlink "$THIS_SCRIPT_SOURCE")"
	[[ "$THIS_SCRIPT_SOURCE" != /* ]] && THIS_SCRIPT_SOURCE="$DIR/$THIS_SCRIPT_SOURCE"
done
AI_HOME_DIR="$(cd -P "$(dirname "$THIS_SCRIPT_SOURCE")" && pwd)"
MODELS_DIR="$AI_HOME_DIR/Models/llama.cpp"

CONFIG="$AI_HOME_DIR/.llama"
LLAMA_LOG="$AI_HOME_DIR/activity-llama.log"
# Directory with per-model metadata: <filename.gguf>.url and <filename.gguf>.txt
KNOWN_MODELS="$AI_HOME_DIR/.known.llama"

PORT=8080
LOG_LEVEL=1
MODEL=""
MODEL_ARGS=()
MODEL_SUMMARY=""
PID=""
EDITOR_CMD=""

# Lists with more entries than this ask for a filter first
FILTER_THRESHOLD=10
# Working set shared by the list/filter helpers
CAND=()
FILTER_USED=0
FILTER_VALUE=""
# Model chosen by choose_note_target()
NOTE_TARGET=""

check4command() {
	if ! command -v "$1" >/dev/null 2>&1; then
		return 1
	fi
	return 0
}

valid_model_name() {
	[[ "$1" =~ ^[a-zA-Z0-9._-]+\.gguf$ ]] && [[ "$1" != .* ]]
}

url_file() {
	printf '%s/%s.url' "$KNOWN_MODELS" "$1"
}

note_file() {
	printf '%s/%s.txt' "$KNOWN_MODELS" "$1"
}

get_model_url() {
	local file line=""
	file=$(url_file "$1")
	[[ -f "$file" ]] || return 0
	IFS= read -r line < "$file" || true
	printf '%s' "${line%$'\r'}"
}

# First line of the model notes, used as preview in lists
get_model_comment() {
	local file line=""
	file=$(note_file "$1")
	[[ -f "$file" ]] || return 0
	IFS= read -r line < "$file" || true
	printf '%s' "${line%$'\r'}"
}

# Preview for lists: first line of the notes, followed by [+n] when n more lines exist
get_model_preview() {
	local file line first="" extra=0 n=0
	file=$(note_file "$1")
	[[ -f "$file" ]] || return 0

	while IFS= read -r line || [[ -n "$line" ]]; do
		line="${line%$'\r'}"
		n=$((n + 1))
		if [[ "$n" -eq 1 ]]; then
			first="$line"
		elif [[ -n "${line//[[:space:]]/}" ]]; then
			extra=$((extra + 1))
		fi
	done < "$file"

	if [[ "$extra" -gt 0 ]]; then
		[[ -n "$first" ]] && first="$first "
		first="$first[+$extra]"
	fi
	printf '%s' "$first"
	return 0
}

set_model_url() {
	printf '%s\n' "$2" > "$(url_file "$1")"
}

set_model_note() {
	printf '%s\n' "$2" > "$(note_file "$1")"
}

append_model_note() {
	local file
	file=$(note_file "$1")
	# Make sure the existing content ends with a newline
	if [[ -s "$file" && -n "$(tail -c 1 "$file")" ]]; then
		echo >> "$file"
	fi
	printf '%s\n' "$2" >> "$file"
}

seed_model() {
	printf '%s\n' "$2" > "$(url_file "$1")"
	printf '%s\n' "$3" > "$(note_file "$1")"
}

seed_known_models() {
	seed_model "DeepSeek-Coder-V2-Lite-Instruct-Q4_K_M.gguf" "https://huggingface.co/bartowski/DeepSeek-Coder-V2-Lite-Instruct-GGUF/resolve/main/DeepSeek-Coder-V2-Lite-Instruct-Q4_K_M.gguf" "Capable model, but too heavy for 16GB RAM."
	seed_model "gemma-4-12B-it-Q4_K_M.gguf" "https://huggingface.co/bartowski/gemma-4-12B-it-GGUF/resolve/main/gemma-4-12B-it-Q4_K_M.gguf" "Strong reasoning and self-correction, but too slow and heavy for M2 Pro / 16GB."
	seed_model "granite-3.3-8b-instruct-Q4_K_M.gguf" "https://huggingface.co/ibm-granite/granite-3.3-8b-instruct-GGUF/resolve/main/granite-3.3-8b-instruct-Q4_K_M.gguf" "Unusable: claims it cannot write files, fails to complete tasks, and hallucinates incompatible code."
	seed_model "LFM2.5-8B-A1B-Q4_K_M.gguf" "https://huggingface.co/LiquidAI/LFM2.5-8B-A1B-GGUF/resolve/main/LFM2.5-8B-A1B-Q4_K_M.gguf" "Rejected: very fast, but ignores tools and produces broken output."
	seed_model "Mellum2-12B-A2.5B-Instruct-Q4_K_M.gguf" "https://huggingface.co/bartowski/Mellum2-12B-A2.5B-Instruct-GGUF/resolve/main/Mellum2-12B-A2.5B-Instruct-Q4_K_M.gguf" "Poor instruction following: runs basic ls searches and then hallucinates the rest."
	seed_model "Ministral-3-8B-Instruct-2512-Q4_K_M.gguf" "https://huggingface.co/mistralai/Ministral-3-8B-Instruct-2512-GGUF/resolve/0102285ad796bd99af90f58de616092e5630e970/Ministral-3-8B-Instruct-2512-Q4_K_M.gguf" "Solid agentic behavior: good exploration, tool usage, coherent diffs, and constraint adherence. Near swap limit on 16GB."
	seed_model "omnicoder-9b-q4_k_m.gguf" "https://huggingface.co/Tesslate/OmniCoder-9B-GGUF/resolve/main/omnicoder-9b-q4_k_m.gguf" "Promising analysis, but incomplete code generation and tends to stall on retries."
	seed_model "OpenCoder-8B-Instruct-Q4_K_M.gguf" "https://huggingface.co/bartowski/OpenCoder-8B-Instruct-GGUF/resolve/main/OpenCoder-8B-Instruct-Q4_K_M.gguf" "Fails to execute tools, misunderstands prompts, and gets stuck in loops."
	seed_model "Ornith-1.5-9B-Q4_K_M.gguf" "https://huggingface.co/ornith-ai/Ornith-1.5-9B-GGUF/resolve/main/Ornith-1.5-9B-Q4_K_M.gguf" "Excellent initial analysis, but stalls during tool-assisted code generation. Worth revisiting later."
	seed_model "Phi-4-mini-instruct-Q4_K_M.gguf" "https://huggingface.co/lmstudio-community/Phi-4-mini-instruct-GGUF/resolve/main/Phi-4-mini-instruct-Q4_K_M.gguf" "Rejected: ignores instructions and requirements, invents architectures."
	seed_model "Qwen3-8B-Q4_K_M.gguf" "https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf" "Unreliable tool usage and inconsistent instruction following."
	seed_model "Qwen_Qwen3.5-9B-Q4_K_M.gguf" "https://huggingface.co/bartowski/Qwen_Qwen3.5-9B-GGUF/resolve/a97475a16d55218110e20e5391d1fe46a8c5128f/Qwen_Qwen3.5-9B-Q4_K_M.gguf" "Fast and capable on isolated tasks, but tends to forget system/project rules on longer generations."
}

# One-time conversion of the v1.x TSV file (.known.llama) into the .known.llama/ directory.
# The directory is built aside and swapped in only when complete, so an interrupted
# migration leaves the old file untouched. The backup of the old file only exists while
# the swap is in progress: it is deleted once the migration succeeds.
migrate_known_models() {
	local backup="$KNOWN_MODELS.bak"
	local staging="$KNOWN_MODELS.migrating"
	local line name rest url note count=0

	[[ -e "$backup" ]] && backup="$KNOWN_MODELS.bak.$(date +%s)"

	rm -rf "$staging"
	if ! mkdir "$staging"; then
		status_line "Error" "❌ Unable to create $staging"
		return 1
	fi

	while IFS= read -r line || [[ -n "$line" ]]; do
		line="${line%$'\r'}"
		[[ "$line" == *$'\t'* ]] || continue

		name="${line%%$'\t'*}"
		rest="${line#*$'\t'}"
		url="${rest%%$'\t'*}"
		note=""
		if [[ "$rest" == *$'\t'* ]]; then
			note="${rest#*$'\t'}"
		fi

		[[ -n "$name" && "$name" != */* && "$name" != .* ]] || continue

		if [[ -n "$url" && "$url" != "-" ]]; then
			printf '%s\n' "$url" > "$staging/$name.url"
		fi
		if [[ -n "$note" ]]; then
			printf '%s\n' "$note" > "$staging/$name.txt"
		fi
		count=$((count + 1))
	done < "$KNOWN_MODELS"

	if ! mv "$KNOWN_MODELS" "$backup"; then
		status_line "Error" "❌ Unable to back up $KNOWN_MODELS"
		rm -rf "$staging"
		return 1
	fi
	if ! mv "$staging" "$KNOWN_MODELS"; then
		status_line "Error" "❌ Migration failed, restoring $KNOWN_MODELS"
		mv "$backup" "$KNOWN_MODELS"
		rm -rf "$staging"
		return 1
	fi

	# Migration completed: the backup is no longer needed
	rm -f "$backup"

	status_line "Migrated" "📦 $count known models -> $(basename "$KNOWN_MODELS")/"
	return 0
}

check_setup() {
	mkdir -p "$MODELS_DIR"
	if [[ ! -d "$MODELS_DIR" ]]; then
		status_line "Error" "❌ Unable to create dir: $MODELS_DIR"
		return 1
	fi
	if ! check4command "llama-server"; then
		if check4command "brew"; then
			status_line "Installing" "☁️  Installing llama-server via Homebrew..."
			brew install llama.cpp
		elif [[ "$(uname -s)" == "Linux" ]] && check4command "apt-get"; then
			status_line "Installing" "☁️  Trying to install llama.cpp via apt..."
			sudo apt-get update && sudo apt-get install -y llama.cpp
		fi

		if ! check4command "llama-server"; then
			status_line "Error" "❌ llama-server not found. Install llama.cpp (e.g. via Homebrew or build from https://github.com) and ensure 'llama-server' is in PATH."
			return 1
		fi
		status_line "Installed" "🦙 llama-server is ready"
	fi
	if ! check4command "pi"; then
		if ! check4command "npm"; then
			status_line "Error" "❌ Unable to install Pi (npm isn't installed)"
			return 1
		fi
	
		status_line "Installing" "☁️ Install Pi Coding Agent"
	
		npm install -g --ignore-scripts @earendil-works/pi-coding-agent || {
			status_line "Error" "❌ Error installing Pi"
			return 1
		}
	
		if ! check4command "pi"; then
			status_line "Error" "❌ Pi command not found after installation"
			return 1
		fi
	
		status_line "Installed" "🪢 Pi Coding Agent was installed"
	fi

	if [[ -f "$KNOWN_MODELS" ]]; then
		migrate_known_models || return 1
	elif [[ ! -d "$KNOWN_MODELS" ]]; then
		if ! mkdir -p "$KNOWN_MODELS"; then
			status_line "Error" "❌ Unable to create dir: $KNOWN_MODELS"
			return 1
		fi
	fi
	if [[ -z "$(ls -A "$KNOWN_MODELS" 2>/dev/null)" ]]; then
		seed_known_models
	fi
	return 0
}

status_line() {
	printf "   %24s : %s\n" "$1" "$2"
}

get_selected_model() {
	local saved
	saved=$(sed -n '1p' "$CONFIG" 2>/dev/null)
	if [ -n "$saved" ] && [ -f "$saved" ]; then
		echo "$saved"
	fi
}

load_config() {
	if [ -f "$CONFIG" ]; then
		PORT=$(sed -n '2p' "$CONFIG")
		LOG_LEVEL=$(sed -n '3p' "$CONFIG")
		PID=$(sed -n '4p' "$CONFIG")
		EDITOR_CMD=$(sed -n '5p' "$CONFIG")
	fi

	[[ "$PORT" =~ ^[0-9]+$ ]] && [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] || PORT=8080
	[[ "$LOG_LEVEL" =~ ^[1-4]$ ]] || LOG_LEVEL=1
	[[ "$PID" =~ ^[0-9]+$ ]] || PID=""

	MODEL=$(get_selected_model)

	write_config
}

write_config() {
	local tmp="$CONFIG.tmp.$$"

	printf '%s\n%s\n%s\n%s\n%s\n' "$MODEL" "$PORT" "$LOG_LEVEL" "$PID" "$EDITOR_CMD" > "$tmp"
	mv "$tmp" "$CONFIG"
}

model_name() {
	if [ -n "$MODEL" ]; then
		basename "$MODEL"
	else
		echo "none"
	fi
}

process_is_llama() {
	local pid="$1"
	local command

	[[ "$pid" =~ ^[0-9]+$ ]] || return 1
	kill -0 "$pid" 2>/dev/null || return 1

	command=$(ps -p "$pid" -o command= 2>/dev/null) || return 1

	case "$command" in
		*llama-server*) return 0 ;;
		*) return 1 ;;
	esac
}

# ---------------------------------------------------------------------------
# Lists and filters
# ---------------------------------------------------------------------------

# Case-insensitive substring match of $1 against any of the remaining arguments.
# nocasematch is enabled only here, and the previous state is restored.
matches_filter() {
	local filter="$1" hit=1 had=0 text
	shift

	shopt -q nocasematch && had=1
	shopt -s nocasematch
	for text in "$@"; do
		if [[ "$text" == *"$filter"* ]]; then
			hit=0
			break
		fi
	done
	[[ "$had" -eq 1 ]] || shopt -u nocasematch

	return "$hit"
}

# Narrow CAND[] down by filter ($1), matched on name, URL and first line of the notes.
# Without a filter, lists longer than FILTER_THRESHOLD ask for one (Enter = show all).
narrow_candidates() {
	local filter="$1"
	local all=("${CAND[@]}")
	local name

	FILTER_USED=0
	FILTER_VALUE=""

	if [[ -z "$filter" && ${#all[@]} -gt $FILTER_THRESHOLD ]]; then
		read -rp "${#all[@]} entries. Filter (Enter = show all): " filter || filter=""
	fi
	[[ -n "$filter" ]] || return 0

	FILTER_USED=1
	FILTER_VALUE="$filter"
	CAND=()
	for name in "${all[@]}"; do
		if matches_filter "$filter" "$name" "$(get_model_url "$name")" "$(get_model_comment "$name")"; then
			CAND+=("$name")
		fi
	done
	return 0
}

# Names with a .url and/or .txt file in .known.llama/, in alphabetical order
list_known_names() {
	local f name

	CAND=()
	for f in "$KNOWN_MODELS"/*; do
		case "$f" in
			*.txt) [[ -f "${f%.txt}.url" ]] && continue ;;
			*.url) ;;
			*) continue ;;
		esac
		[[ -f "$f" ]] || continue
		name="${f##*/}"
		CAND+=("${name%.*}")
	done
}

list_local_names() {
	local f

	CAND=()
	for f in "$MODELS_DIR"/*.gguf; do
		[[ -f "$f" ]] && CAND+=("${f##*/}")
	done
}

# Known models plus local .gguf files that have no metadata yet
list_note_targets() {
	local f name

	list_known_names
	for f in "$MODELS_DIR"/*.gguf; do
		[[ -f "$f" ]] || continue
		name="${f##*/}"
		[[ -e "$(url_file "$name")" || -e "$(note_file "$name")" ]] && continue
		CAND+=("$name")
	done
}

print_entry() {
	local label="$1" name="$2" comment

	status_line "$label" "$name"
	comment=$(get_model_preview "$name")
	[[ -n "$comment" ]] && printf '%19s %s\n' "" "ⓘ  $comment"
	return 0
}

print_candidates() {
	local i=1 name

	for name in "${CAND[@]}"; do
		print_entry "$i" "$name"
		((i++))
	done
}

select_model() {
	local filter="$1" choice

	list_local_names
	if [ ${#CAND[@]} -eq 0 ]; then
		status_line "Error" "❌ No .gguf models found in $MODELS_DIR"
		return 1
	fi

	narrow_candidates "$filter"
	if [ ${#CAND[@]} -eq 0 ]; then
		status_line "Error" "❌ No model matches '$FILTER_VALUE'."
		return 1
	fi

	status_line "Current model" "💚 $(model_name)"

	if [[ "$FILTER_USED" -eq 1 && ${#CAND[@]} -eq 1 ]]; then
		choice=1
	else
		status_line "Select a model" "⬇︎"
		print_candidates

		read -rp "Choose [1-${#CAND[@]}]: " choice

		if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#CAND[@]} ]; then
			status_line "Error" "❌ Invalid choice."
			return 1
		fi
	fi

	MODEL="$MODELS_DIR/${CAND[$((choice-1))]}"
	write_config
	status_line "Selected model" "👮 $(model_name)"

	if process_is_llama "$PID"; then
		read -rp "Restart now llama.cpp using new model? [y/N]: " ans
		if [[ "$ans" =~ ^[yY]$ ]]; then
			stop
			sleep 1
			start
		fi
	fi
}

set_log_level() {
	local level="$2"

	if ! [[ "$level" =~ ^[1-4]$ ]]; then
		echo "❌ 📝 Log level must be between 1 and 4."
		return 1
	fi

	if [ "$LOG_LEVEL" -eq "$level" ]; then
		status_line "Log level" "📝 already set to $LOG_LEVEL."
		return 0
	fi

	local running=0
	process_is_llama "$PID" && running=1

	LOG_LEVEL="$level"
	write_config

	status_line "Log level" "📝 [$LOG_LEVEL]"

	if [ "$running" -eq 1 ]; then
		stop
		sleep 1
		start
	fi
}

set_port() {
	local port="$2"

	if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1025 ] || [ "$port" -gt 65535 ]; then
		echo "❌ 🚪 Port must be between 1025 and 65535."
		return 1
	fi

	if [ "$PORT" -eq "$port" ]; then
		status_line "Port" "🚪 already set to $PORT."
		return 0
	fi

	local running=0
	process_is_llama "$PID" && running=1

	PORT="$port"
	write_config

	status_line "Port" "🚪 $PORT"

	if [ "$running" -eq 1 ]; then
		stop
		sleep 1
		start
	fi
}

# First usable editor: saved preference, $VISUAL, $EDITOR, vi, nano
resolve_editor() {
	local candidate first

	for candidate in "$EDITOR_CMD" "$VISUAL" "$EDITOR" vi nano; do
		[[ -n "$candidate" ]] || continue
		read -r first _ <<< "$candidate"
		if [[ -n "$first" ]] && check4command "$first"; then
			printf '%s' "$candidate"
			return 0
		fi
	done
	return 1
}

set_editor() {
	shift
	local cmd="$*" first

	if [[ -z "$cmd" ]]; then
		status_line "Editor" "✏️  saved: ${EDITOR_CMD:-none} | in use: $(resolve_editor || echo none)"
		return 0
	fi

	if [[ "$cmd" == "default" ]]; then
		EDITOR_CMD=""
		write_config
		status_line "Editor" "✏️  preference cleared (in use: $(resolve_editor || echo none))"
		return 0
	fi

	if [[ "$cmd" == *$'\n'* ]]; then
		status_line "Error" "❌ Editor command must be a single line."
		return 1
	fi

	read -r first _ <<< "$cmd"
	if ! check4command "$first"; then
		status_line "Error" "❌ Command not found: $first"
		return 1
	fi

	EDITOR_CMD="$cmd"
	write_config
	status_line "Editor" "✏️  $EDITOR_CMD"
}

# "/owner/repo/..." gets the Hugging Face host; Hugging Face /blob/ links become /resolve/
normalize_model_url() {
	local input="$1"

	if [[ "$input" == /* ]]; then
		input="https://huggingface.co$input"
	fi

	if [[ "$input" == https://huggingface.co/* ]]; then
		input="${input/\/blob\///resolve/}"
	fi

	printf '%s' "$input"
}

add_model() {
	local input="$1"
	local note="${2:-To be tested}"

	if [ -z "$input" ]; then
		status_line "Usage" "⚠️  $0 hf <url-or-path> [note]"
		return 1
	fi

	input=$(normalize_model_url "$input")

	local filename="${input%%\?*}"
	filename="${filename##*/}"

	if ! valid_model_name "$filename"; then
		status_line "Error" "❌ Invalid model URL or filename."
		return 1
	fi

	if [[ -n "$(get_model_url "$filename")" ]]; then
		status_line "Skip" "ℹ️  '$filename' already has a URL in $(basename "$KNOWN_MODELS")/"
		return 0
	fi

	set_model_url "$filename" "$input"
	# Keep notes already written for this model, if any
	[[ -f "$(note_file "$filename")" ]] || set_model_note "$filename" "$note"
	status_line "Added" "✅ '$filename' added to $(basename "$KNOWN_MODELS")/"
}

download_model() {
	local url="$2"

	# "/owner/repo/..." is a Hugging Face path, not a filter
	[[ "$url" == /* ]] && url=$(normalize_model_url "$url")

	if [[ "$url" != http://* && "$url" != https://* ]]; then
		# Empty or not a URL: pick from known models not yet downloaded, using $url as filter
		local filter="$url" all name saved_url choice
		url=""

		list_known_names
		all=("${CAND[@]}")
		CAND=()
		for name in "${all[@]}"; do
			if [[ -n "$(get_model_url "$name")" && ! -f "$MODELS_DIR/$name" ]]; then
				CAND+=("$name")
			fi
		done

		if [[ ${#CAND[@]} -gt 0 ]]; then
			narrow_candidates "$filter"
		fi

		if [[ ${#CAND[@]} -eq 0 ]]; then
			if [[ -n "$filter" || "$FILTER_USED" -eq 1 ]]; then
				status_line "Error" "❌ No downloadable model matches '${FILTER_VALUE:-$filter}'."
				return 1
			fi
			read -rp "Enter model URL: " url
		elif [[ "$FILTER_USED" -eq 1 && ${#CAND[@]} -eq 1 ]]; then
			read -rp "Download ${CAND[0]}? [Y/n]: " choice
			[[ "$choice" =~ ^[nN]$ ]] && return 0
			url=$(get_model_url "${CAND[0]}")
		else
			echo "Known models available for download:"
			print_candidates

			read -rp "Choose [1-${#CAND[@]}] or enter URL: " choice

			if [[ "$choice" =~ ^[0-9]+$ ]]; then
				if [[ "$choice" -lt 1 || "$choice" -gt ${#CAND[@]} ]]; then
					status_line "Error" "❌ Invalid choice."
					return 1
				fi
				url=$(get_model_url "${CAND[$((choice-1))]}")
			else
				url="$choice"
			fi
		fi
	fi
	url=$(normalize_model_url "$url")
	local filename="${url%%\?*}"
	filename="${filename##*/}"

	if ! valid_model_name "$filename"; then
		status_line "Error" "❌ Invalid model URL or filename."
		return 1
	fi

	if [ -f "$MODELS_DIR/$filename" ]; then
		status_line "Skip" "ℹ️  '$filename' is already downloaded."
		return 0
	fi

	local destination="$MODELS_DIR/$filename"
	local partial="$destination.part"

	mkdir -p "$MODELS_DIR"

	status_line "Downloading" "☁️  $filename..."

	local resume=()
	[[ -f "$partial" ]] && resume=(-C -)

	if ! curl -fL --progress-bar "${resume[@]}" "$url" -o "$partial"; then
		status_line "Error" "❌ Download failed. Partial file retained: $partial"
		return 1
	fi

	if [[ ! -s "$partial" ]]; then
		status_line "Error" "❌ Download failed: empty file."
		return 1
	fi

	if ! mv "$partial" "$destination"; then
		status_line "Error" "❌ Unable to move downloaded model."
		return 1
	fi

	set_model_url "$filename" "$url"

	status_line "Downloaded" "👮 $filename"
}

delete_model() {
	local filter="$1" choice

	list_local_names
	if [ ${#CAND[@]} -eq 0 ]; then
		status_line "Error" "❌ No models found."
		return 1
	fi

	narrow_candidates "$filter"
	if [ ${#CAND[@]} -eq 0 ]; then
		status_line "Error" "❌ No model matches '$FILTER_VALUE'."
		return 1
	fi

	if [[ "$FILTER_USED" -eq 1 && ${#CAND[@]} -eq 1 ]]; then
		choice=1
	else
		print_candidates

		read -rp "Choose [1-${#CAND[@]}]: " choice

		if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#CAND[@]} ]; then
			status_line "Error" "❌ Invalid choice."
			return 1
		fi
	fi

	local target="$MODELS_DIR/${CAND[$((choice-1))]}"

	read -rp "👍 Delete $(basename "$target")? [y/N]: " ans
	[[ "$ans" =~ ^[yY]$ ]] || return 0

	if process_is_llama "$PID"; then
		local running_model
		running_model=$(ps -p "$PID" -o command=)

		if [[ "$running_model" == *"$target"* ]]; then
			status_line "Current" "💚 Selected model will be deleted"
			status_line "Stopping" "⚠️ Stopping server before deletion..."
			stop
		fi
	fi

	rm -f "$target"

	if [ "$MODEL" = "$target" ]; then
		MODEL=$(get_selected_model)
		write_config
		if [[ "$(model_name)" == "none" ]]; then
			status_line "Selected model" "💔 none"
		else
			status_line "Selected model" "💚 $(model_name)"
		fi
	fi

	status_line "Deleted" "🗑️  $(basename "$target")"
}

show_model_notes() {
	local name="$1" file line
	file=$(note_file "$name")

	if [[ ! -s "$file" ]]; then
		status_line "Comment" "ⓘ  [No comment]"
		return 0
	fi

	status_line "Comment" "ⓘ"
	while IFS= read -r line || [[ -n "$line" ]]; do
		printf '%19s %s\n' "" "${line%$'\r'}"
	done < "$file"
}

edit_model_notes() {
	local name="$1" file editor content
	local parts=()
	file=$(note_file "$name")

	if [[ ! -t 0 || ! -t 1 ]]; then
		status_line "Error" "❌ An interactive terminal is required to edit notes."
		return 1
	fi

	if ! editor=$(resolve_editor); then
		status_line "Error" "❌ No editor found. Set one with: $0 editor <cmd>"
		return 1
	fi

	read -r -a parts <<< "$editor"
	"${parts[@]}" "$file"

	# Do not leave empty notes behind
	if [[ -f "$file" ]]; then
		content=$(<"$file")
		if [[ -z "${content//[[:space:]]/}" ]]; then
			rm -f "$file"
		fi
	fi
	status_line "Comment" "ⓘ  Saved for $name"
}

# Pick any known or local model for the notes menu. Sets NOTE_TARGET.
choose_note_target() {
	local choice

	NOTE_TARGET=""

	list_note_targets
	if [[ ${#CAND[@]} -eq 0 ]]; then
		status_line "Error" "💔 No models found."
		return 1
	fi

	narrow_candidates ""
	if [[ ${#CAND[@]} -eq 0 ]]; then
		status_line "Error" "❌ No model matches '$FILTER_VALUE'."
		return 1
	fi

	if [[ "$FILTER_USED" -eq 1 && ${#CAND[@]} -eq 1 ]]; then
		NOTE_TARGET="${CAND[0]}"
		return 0
	fi

	status_line "Select a model" "⬇︎"
	print_candidates

	read -rp "Choose [1-${#CAND[@]}]: " choice || choice=""
	if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#CAND[@]} ]; then
		status_line "Error" "❌ Invalid choice."
		return 1
	fi
	NOTE_TARGET="${CAND[$((choice-1))]}"
}

# Notes menu for model $1. [m]odel switches the target and shows the menu again.
comment_menu() {
	local name="$1" action text ans icon

	while true; do
		icon="📀"
		[[ -n "$MODEL" && "$name" == "$(basename "$MODEL")" ]] && icon="💚"
		status_line "Model" "$icon $name"
		read -rp "[v]iew [e]dit [r]eplace [a]dd [d]elete [m]odel (Enter = view): " action || return 0

		case "$action" in
			""|[vV]*)
				show_model_notes "$name"
				return 0
				;;
			[eE]*)
				edit_model_notes "$name"
				return $?
				;;
			[rR]*)
				read -rp "New comment (empty = cancel): " text
				if [[ -z "$text" ]]; then
					status_line "Comment" "ⓘ  Unchanged"
				else
					set_model_note "$name" "$text"
					status_line "Comment" "ⓘ  Updated for $name"
				fi
				return 0
				;;
			[aA]*)
				read -rp "Line to add (empty = cancel): " text
				if [[ -z "$text" ]]; then
					status_line "Comment" "ⓘ  Unchanged"
				else
					append_model_note "$name" "$text"
					status_line "Comment" "ⓘ  Added to $name"
				fi
				return 0
				;;
			[dD]*)
				read -rp "Delete all notes for $name? [y/N]: " ans
				if [[ "$ans" =~ ^[yY]$ ]]; then
					rm -f "$(note_file "$name")"
					status_line "Comment" "ⓘ  Deleted for $name"
				fi
				return 0
				;;
			[mM]*)
				if choose_note_target; then
					name="$NOTE_TARGET"
				fi
				;;
			*)
				status_line "Error" "❌ Invalid choice."
				return 1
				;;
		esac
	done
}

# With text: replaces the notes of the current model.
# Without text: notes menu for the current model (or a model to pick, if none is selected).
comment_model() {
	shift

	local name text="$*"

	if [[ -n "$text" ]]; then
		if [[ -z "$MODEL" ]]; then
			status_line "Error" "💔 No model selected."
			return 1
		fi
		name=$(basename "$MODEL")
		set_model_note "$name" "$text"
		status_line "Comment" "ⓘ  Updated for $name"
		return 0
	fi

	if [[ -n "$MODEL" ]]; then
		name=$(basename "$MODEL")
	else
		choose_note_target || return 1
		name="$NOTE_TARGET"
	fi
	comment_menu "$name"
}

list_known_models() {
	local filter="$1" name cname comment

	list_known_names
	if [[ ${#CAND[@]} -eq 0 ]]; then
		status_line "Error" "💔 No known models."
		return 1
	fi

	narrow_candidates "$filter"
	if [[ ${#CAND[@]} -eq 0 ]]; then
		status_line "Error" "💔 No known model matches '$FILTER_VALUE'."
		return 1
	fi

	cname=$(model_name)
	for name in "${CAND[@]}"; do
		if [[ -f "$MODELS_DIR/$name" ]]; then
			if [[ "$name" == "$cname" ]]; then
				status_line "Current" "💚 $name"
			else
				status_line "Available" "📀 $name"
			fi
		else
			status_line "Known" "☁️  $name"
		fi
		comment=$(get_model_preview "$name")
		[[ -n "$comment" ]] && printf '%19s %s\n' "" "ⓘ  $comment"
		echo ""
	done
}

port_is_ours() {
	local pid="$1"

	if check4command "lsof"; then
		lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null |
			grep -Fxq "$pid"
	elif check4command "ss"; then
		ss -tulpn 2>/dev/null |
			awk -v port="$PORT" -v pid="pid=$pid," '
				$1 == "LISTEN" && $5 ~ (":" port "$") && index($0, pid) { found=1; exit }
				END { exit !found }
			'
	else
		return 1
	fi
}

status() {
	status_line "Alias model" "🎭️ localLLM"
	status_line "Selected model" "💚 $(model_name)"
	if [ -n "$MODEL" ] && [ -f "$MODEL" ]; then
		resolve_model_preset
		status_line "Preset" "⚙️  $MODEL_SUMMARY"
	fi
	status_line "Log level" "📝 $LOG_LEVEL"
	status_line "Port" "🚪 $PORT"
	echo

	if [ -z "$PID" ]; then
		status_line "llama.cpp" "🔴 NOT running (no PID)."
		echo
		return 1
	fi

	if ! process_is_llama "$PID"; then
		status_line "llama.cpp" "🔴 NOT running (invalid PID $PID)."
		PID=""
		write_config
		echo
		return 1
	fi

	if ! port_is_ours "$PID"; then
		status_line "llama.cpp" "🟠 process active (PID $PID), but 🚪 port $PORT not listening."
		status_line "Model" "👮 $(model_name)"
		echo
		return 1
	fi

	status_line "llama.cpp" "🟢 active (PID $PID)"
	echo
	return 0
}

wait_port() {
	local pid="$1"

	for i in {1..60}; do
		process_is_llama "$pid" || return 1

		if port_is_ours "$pid"; then
			return 0
		fi

		sleep 1
	done

	return 1
}

watch_log() {
	local key

	echo
	echo "[Press enter to stop log]"
	echo

	touch "$LLAMA_LOG"
	tail -n 30 -f "$LLAMA_LOG" &
	local tail_pid=$!

	trap 'kill "$tail_pid" 2>/dev/null; wait "$tail_pid" 2>/dev/null; trap - INT TERM; return 0' INT TERM

	while IFS= read -r -s -n 1 key; do
		[[ "$key" == "" ]] && break
	done

	trap - INT TERM
	kill "$tail_pid" 2>/dev/null
	wait "$tail_pid" 2>/dev/null
}

get_file_size_bytes() {
	local file="$1"
	if stat -f%z "$file" >/dev/null 2>&1; then
		stat -f%z "$file"
	else
		stat -c%s "$file" 2>/dev/null || echo 0
	fi
}

get_total_ram_mb() {
	local total_bytes=0
	if [[ "$(uname -s)" == "Darwin" ]]; then
		total_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
		echo $(( total_bytes / 1024 / 1024 ))
	elif [[ -r /proc/meminfo ]]; then
		awk '/^MemTotal:/ { printf "%d\n", $2 / 1024; exit }' /proc/meminfo
	else
		echo 0
	fi
}

get_memory_pressure_pct() {
	local pct

	pct=$(memory_pressure -Q 2>/dev/null |
		awk -F': ' '/System-wide memory free percentage:/ {
			gsub(/%/, "", $2)
			print $2
			exit
		}')

	[[ "$pct" =~ ^[0-9]+$ ]] || return 1
	(( pct <= 100 )) || return 1

	echo "$pct"
}

get_available_ram_mb() {
	local used_by_llama_kb=0
	if process_is_llama "$PID"; then
		used_by_llama_kb=$(ps -p "$PID" -o rss= 2>/dev/null || echo 0)
	fi

	if [[ "$(uname -s)" == "Darwin" ]]; then
		local total_bytes pressure_pct
		total_bytes=$(sysctl -n hw.memsize 2>/dev/null) || return 1
		pressure_pct=$(get_memory_pressure_pct) || return 1
		echo $(( (total_bytes * pressure_pct / 100 + used_by_llama_kb * 1024) / 1024 / 1024 ))
	elif [[ -r /proc/meminfo ]]; then
		local avail_kb
		avail_kb=$(awk '/^MemAvailable:/ { print $2; exit }' /proc/meminfo)
		[[ "$avail_kb" =~ ^[0-9]+$ ]] || return 1
		echo $(( (avail_kb + used_by_llama_kb) / 1024 ))
	else
		return 1
	fi
}

resolve_model_preset() {
	local name
	name=$(basename "$MODEL")

	local total_mb avail_mb model_bytes model_mb headroom_mb

	total_mb=$(get_total_ram_mb)
	avail_mb=$(get_available_ram_mb) || {
		status_line "Warning" "⚠️ Unable to estimate available RAM; using conservative preset."
		avail_mb=0
	}

	model_bytes=$(get_file_size_bytes "$MODEL")
	model_mb=$(( model_bytes / 1024 / 1024 ))
	headroom_mb=$(( avail_mb - model_mb ))

	(( headroom_mb < 0 )) && headroom_mb=0

	local ctx=20480
	local batch=1024
	local ubatch=512
	local fit_target=1536
	local reasoning="off"
	local extra=()
	local sampling=(--temp 0.35 --top-p 0.9 --min-p 0.05 --repeat-penalty 1.08 --repeat-last-n 128)

	# 1. Dynamic sizing based on available RAM vs GGUF file weight
	if (( headroom_mb >= 14000 )); then
		ctx=32768
		batch=2048
		ubatch=512
		fit_target=2048
	elif (( headroom_mb >= 3000 )); then
		ctx=20480
		batch=1024
		ubatch=512
		fit_target=1536
	elif (( headroom_mb >= 1200 )); then
		ctx=14336
		batch=512
		ubatch=256
		fit_target=1536
	else
		ctx=12288
		batch=512
		ubatch=256
		fit_target=1024
	fi

	# 2. Reasoning / Thinking models fine-tuning
	case "$name" in
		*Thinking*|*R1*|*QwQ*|*Ornith*)
			reasoning="on"
			extra+=(--reasoning-budget 2048)
			(( headroom_mb < 3000 )) && extra+=(--no-reasoning-preserve)
			;;
	esac

	# 3. Family-specific adjustments
	case "$name" in
		*Qwen3*)
			sampling=(--temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.05 --repeat-penalty 1.05 --repeat-last-n 128)
			;;
		*Devstral*)
			sampling=(--temp 0.15 --top-p 0.95 --min-p 0.01 --repeat-penalty 1.05 --repeat-last-n 128)
			;;
		*Ornith*)
			(( headroom_mb >= 1024 && ctx < 24576 )) && ctx=24576
			;;
	esac

	MODEL_SUMMARY="ctx: $ctx | batch: $batch/$ubatch | reasoning: $reasoning | RAM: ${avail_mb}/${total_mb}MB"

	MODEL_ARGS=(
		--ctx-size "$ctx"
		-b "$batch"
		-ub "$ubatch"
		--fit on
		--fit-ctx 8192
		--fit-target "$fit_target"
		--reasoning "$reasoning"
		"${extra[@]}"
		"${sampling[@]}"
	)
}

stop() {
	if [ -z "$PID" ]; then
		status_line "llama.cpp" "👀 isn't running."
		echo
		return 0
	fi

	if ! process_is_llama "$PID"; then
		status_line "llama.cpp" "👀 Invalid or obsolete PID. No process was terminated."
		echo
		PID=""
		write_config
		return 0
	fi
	
	status_line "Model" "💚 $(model_name)"
	status_line "Stopping" "💀 llama.cpp (PID $PID)..."
	kill "$PID"

	for i in {1..15}; do
		process_is_llama "$PID" || break
		sleep 1
	done

	if process_is_llama "$PID"; then
		status_line "Killing" "☠️ llama.cpp force stop (PID $PID)..."
		kill -9 "$PID"
	fi

	PID=""
	write_config
	echo
	status_line "llama.cpp" "🔴 stopped."
	echo
}

start() {
	if [[ -z "$MODEL" ]]; then
		status_line "Error" "💔 Select a model before starting llama-server."
		echo
		return 1
	fi
	if [[ ! -f "$MODEL" ]]; then
		status_line "Error" "❌ Model not found: $MODEL"
		echo
		return 1
	fi

	if [ -n "$PID" ]; then
		if process_is_llama "$PID"; then
			if status; then
				echo "🦙 Already running."
				return 0
			fi

			status_line "llama-server" "🟠 running, 🚪 waiting for port..."
			if wait_port "$PID"; then
				status
				return 0
			fi

			status_line "llama-server" "👹 didn't start. 📝 Check $LLAMA_LOG"
			return 1
		fi

		PID=""
		write_config
	fi

	if (echo >/dev/tcp/127.0.0.1/"$PORT") >/dev/null 2>&1; then
		status_line "Port" "❌ $PORT busy 🚪 in use by another process."
		return 1
	fi

	resolve_model_preset
	
	status_line "Starting" "🦙 llama-server ($MODEL_SUMMARY)..."

	nohup llama-server \
		--model "$MODEL" \
		--alias localLLM \
		--host 0.0.0.0 \
		--port "$PORT" \
		--parallel 1 \
		--cache-type-k q8_0 \
		--cache-type-v q4_0 \
		--cache-reuse 256 \
		--flash-attn on \
		--jinja \
		"${MODEL_ARGS[@]}" \
		-lv "$LOG_LEVEL" \
		> "$LLAMA_LOG" 2>&1 &
		
	PID=$!
	write_config

	if ! wait_port "$PID"; then
		status_line "llama.cpp" "🔴 didn't start 📝 Check $LLAMA_LOG"
		if ! process_is_llama "$PID"; then
			PID=""
			write_config
		fi
		return 1
	fi

	status
}

interactive_shell() {
	local action
	local value
	local url
	local COLUMNS=112

	echo
	status_line "Interactive shell" "🦙 Enter number or command"
	echo

	select action in \
		"  s 🟢 Start            " \
		". q 🔴 Stop             " \
		"  h 🟠 Status           " \
		"  r 🔵 Restart          " \
		"  m 💚 Select model     " \
		"  c ⓘ  Comment model    " \
		"add 🌤️  Add model URL    " \
		"  d ☁️  Download model   " \
		" rm 🗑️  Delete model     " \
		"  l 👮 List known models" \
		"  t 🔍 Tail log         " \
		"log 📝 Set log level    " \
		"  p 🚪 Set port         " \
		" ed ✏️  Set editor       " \
		"  x 👋 Exit             "
	do
		case "$REPLY" in
			s|1)
				start
				watch_log
				;;
			.|q|2)
				stop
				;;
			h|3)
				status
				;;
			r|4)
				stop
				sleep 1
				start
				watch_log
				;;
			m|5)
				select_model
				;;
			c|6)
				comment_model comment
				;;
			add|7)
				read -rp "URL (empty to stop): " url
				if [[ -n "$url" ]]; then
					read -rp "Comment (can be empty): " value
					add_model "$url" "$value"
				fi
				;;
			d|8)
				download_model download
				;;
			rm|9)
				delete_model
				;;
			l|10)
				list_known_models
				;;
			t|11)
				watch_log
				;;
			log|12)
				read -rp "Log level [1-4]: " value
				set_log_level log "$value"
				;;
			p|13)
				read -rp "Port [1025-65535]: " value
				set_port port "$value"
				;;
			ed|editor|14)
				status_line "Editor" "✏️  saved: ${EDITOR_CMD:-none} | in use: $(resolve_editor || echo none)"
				read -rp "Editor command (empty = keep, 'default' = reset; e.g. vim, nano, code -w): " value
				[[ -n "$value" ]] && set_editor editor "$value"
				;;
			x|15)
				echo "👋 Bye!"
				break
				;;
			help|-h|--help)
				show_help
				;;
			version|-v|--version)
				show_version
				;;
			*)
				echo "❌ Invalid choice."
				;;
		esac
		echo
		echo "[Press enter to show commands]"
		echo
	done
}

show_help() {
	echo
	status_line "Syntax" "$0 [command]"
	status_line "(no command)" "🦙 Interactive shell"
	echo
	echo "Commands:"
	status_line "s start" "🟢 Start llama-server"
	status_line ". q stop" "🔴 Stop llama-server"
	status_line "h status" "🟠 Llama-server status"
	status_line "r restart" "🔵 Restart llama-server"
	status_line "m model [filter]" "💚 Select current active model"
	status_line "hf add" "🌤️  Add a downloadable model URI"
	status_line "d download [filter|url]" "☁️  Download a model"
	status_line "rm delete [filter]" "🗑️  Delete a downloaded model"
	status_line "c comment [text]" "ⓘ  Set current model comment (no text: menu)"
	status_line "l list [filter]" "👮 List known models"
	status_line "t tail" "🔍 Tail log (live view)"
	status_line "log" "📝 Set log level ($LOG_LEVEL [1..4])"
	status_line "p port" "🚪 Change port (:$PORT)"
	status_line "ed editor [cmd]" "✏️  Show or set the notes editor"
	echo
	echo "Filters are case-insensitive substrings matched on name, URL and first comment line."
	echo "Without a filter, lists longer than $FILTER_THRESHOLD entries ask for one (Enter = show all)."
	echo
}

show_version(){
	echo
	status_line "Script" "🦙 Self-Contained Local AI Agent Ecosystem"
	status_line "Version" "🔖 $THIS_SCRIPT_VERSION"
	status_line "Author" "🏹 Marco Balestra"
	if check4command "llama-server"; then
		llama_ver=$(llama-server --version 2>&1 | awk '/^version:/ { sub(/^version:[[:space:]]*/, ""); print; exit }')
		[[ -z "$llama_ver" ]] && llama_ver=$(llama-server --version 2>&1 | head -n 1)
		status_line "llama-server" "⚙️  ${llama_ver:-unknown}"
	fi
	echo
}

if ! check_setup; then
	status_line "Error" "❌ Cannot run"
	exit 1
fi

load_config

if [[ $# -eq 0 ]]; then
	interactive_shell
else
	case "${1}" in
		s|start)
			start
			;;
		.|q|stop)
			stop
			;;
		h|status)
			status
			;;
		r|restart)
			stop
			sleep 1
			start
			;;
		m|model|select)
			select_model "$2"
			;;
		hf|add)
			add_model "$2" "$3"
			;;
		d|download)
			download_model "$@"
			;;
		c|comment)
			comment_model "$@"
			;;
		l|list)
			list_known_models "$2"
			;;
		rm|delete)
			delete_model "$2"
			;;
		t|tail)
			watch_log
			;;
		log)
			set_log_level "$@"
			;;
		p|port)
			set_port "$@"
			;;
		ed|editor)
			set_editor "$@"
			;;
		help|-h|--help)
			show_help
			;;
		version|-v|--version)
			show_version
			;;
		*)
			status_line "Commands" "❓ Use: $0 {start|stop|status|restart|model|add|download|delete|comment|list|tail|log|port|editor}"
			status_line "Options" "❓ Use: $0 {-h|--help|help|-v|--version|version}"
			status_line "Shell" "❓ Use: $0 (without parameters or options) for interactive shell"
			exit 1
			;;
	esac
fi
