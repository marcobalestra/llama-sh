#!/bin/bash

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
KNOWN_MODELS="$AI_HOME_DIR/.known.llama"

PORT=8080
LOG_LEVEL=1
MODEL=""
MODEL_ARGS=()
MODEL_SUMMARY=""
PID=""

check4command() {
	if ! command -v "$1" >/dev/null 2>&1; then
		return 1
	fi
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
	if [[ ! -f "$KNOWN_MODELS" ]]; then
		cat << 'PREDEFINED_MODELS' > "$KNOWN_MODELS"
DeepSeek-Coder-V2-Lite-Instruct-Q4_K_M.gguf	https://huggingface.co/bartowski/DeepSeek-Coder-V2-Lite-Instruct-GGUF/resolve/main/DeepSeek-Coder-V2-Lite-Instruct-Q4_K_M.gguf	Capable model, but too heavy for 16GB RAM.
gemma-4-12B-it-Q4_K_M.gguf	https://huggingface.co/bartowski/gemma-4-12B-it-GGUF/resolve/main/gemma-4-12B-it-Q4_K_M.gguf	Strong reasoning and self-correction, but too slow and heavy for M2 Pro / 16GB.
granite-3.3-8b-instruct-Q4_K_M.gguf	https://huggingface.co/ibm-granite/granite-3.3-8b-instruct-GGUF/resolve/main/granite-3.3-8b-instruct-Q4_K_M.gguf	Unusable: claims it cannot write files, fails to complete tasks, and hallucinates incompatible code.
LFM2.5-8B-A1B-Q4_K_M.gguf	https://huggingface.co/LiquidAI/LFM2.5-8B-A1B-GGUF/resolve/main/LFM2.5-8B-A1B-Q4_K_M.gguf	Rejected: very fast, but ignores tools and produces broken output.
Mellum2-12B-A2.5B-Instruct-Q4_K_M.gguf	https://huggingface.co/bartowski/Mellum2-12B-A2.5B-Instruct-GGUF/resolve/main/Mellum2-12B-A2.5B-Instruct-Q4_K_M.gguf	Poor instruction following: runs basic ls searches and then hallucinates the rest.
Ministral-3-8B-Instruct-2512-Q4_K_M.gguf	https://huggingface.co/mistralai/Ministral-3-8B-Instruct-2512-GGUF/resolve/0102285ad796bd99af90f58de616092e5630e970/Ministral-3-8B-Instruct-2512-Q4_K_M.gguf	Solid agentic behavior: good exploration, tool usage, coherent diffs, and constraint adherence. Near swap limit on 16GB.
omnicoder-9b-q4_k_m.gguf	https://huggingface.co/Tesslate/OmniCoder-9B-GGUF/resolve/main/omnicoder-9b-q4_k_m.gguf	Promising analysis, but incomplete code generation and tends to stall on retries.
OpenCoder-8B-Instruct-Q4_K_M.gguf	https://huggingface.co/bartowski/OpenCoder-8B-Instruct-GGUF/resolve/main/OpenCoder-8B-Instruct-Q4_K_M.gguf	Fails to execute tools, misunderstands prompts, and gets stuck in loops.
Ornith-1.5-9B-Q4_K_M.gguf	https://huggingface.co/ornith-ai/Ornith-1.5-9B-GGUF/resolve/main/Ornith-1.5-9B-Q4_K_M.gguf	Excellent initial analysis, but stalls during tool-assisted code generation. Worth revisiting later.
Phi-4-mini-instruct-Q4_K_M.gguf	https://huggingface.co/lmstudio-community/Phi-4-mini-instruct-GGUF/resolve/main/Phi-4-mini-instruct-Q4_K_M.gguf	Rejected: ignores instructions and requirements, invents architectures.
Qwen3-8B-Q4_K_M.gguf	https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf	Unreliable tool usage and inconsistent instruction following.
Qwen_Qwen3.5-9B-Q4_K_M.gguf	https://huggingface.co/bartowski/Qwen_Qwen3.5-9B-GGUF/resolve/a97475a16d55218110e20e5391d1fe46a8c5128f/Qwen_Qwen3.5-9B-Q4_K_M.gguf	Fast and capable on isolated tasks, but tends to forget system/project rules on longer generations.
PREDEFINED_MODELS
	fi
	return 0
}

status_line() {
	printf "   %14s : %s\n" "$1" "$2"
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
	fi

	[[ "$PORT" =~ ^[0-9]+$ ]] && [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] || PORT=8080
	[[ "$LOG_LEVEL" =~ ^[1-4]$ ]] || LOG_LEVEL=1
	[[ "$PID" =~ ^[0-9]+$ ]] || PID=""

	MODEL=$(get_selected_model)

	write_config
}

write_config() {
	local tmp="$CONFIG.tmp.$$"

	printf '%s\n%s\n%s\n%s\n' "$MODEL" "$PORT" "$LOG_LEVEL" "$PID" > "$tmp"
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

get_model_comment() {
	local target_name="$1"
	local line name rest

	[[ -f "$KNOWN_MODELS" ]] || return 0

	while IFS= read -r line || [[ -n "$line" ]]; do
		name="${line%%$'\t'*}"
		[[ "$name" == "$target_name" && "$line" == *$'\t'* ]] || continue
		rest="${line#*$'\t'}"
		if [[ "$rest" == *$'\t'* ]]; then
			echo "${rest#*$'\t'}"
		fi
		return 0
	done < "$KNOWN_MODELS"
}

select_model() {
	local models=()
	for file in "$MODELS_DIR"/*.gguf; do
		[[ -f "$file" ]] && models+=("$file")
	done
	if [ ${#models[@]} -eq 0 ]; then
		status_line "Error" "❌ No .gguf models found in $MODELS_DIR"
		return 1
	fi

	status_line "Current model" "💚 $(model_name)"
	status_line "Select a model" "⬇︎"

	local i=1
	local mname mcomment
	for m in "${models[@]}"; do
		mname=$(basename "$m")
		status_line "$i" "$mname"
		mcomment=$(get_model_comment "$mname")
		[[ -n "$mcomment" ]] && printf '%19s %s\n' "" "ⓘ  $mcomment"
		((i++))
	done

	read -rp "Choose [1-${#models[@]}]: " choice

	if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#models[@]} ]; then
		status_line "Error" "❌ Invalid choice."
		return 1
	fi

	MODEL="${models[$((choice-1))]}"
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

add_model() {
	local input="$1"
	local note="${2:-To be tested}"

	if [ -z "$input" ]; then
		status_line "Usage" "⚠️  $0 hf <url-or-path> [note]"
		return 1
	fi

	# If URL starts with "/", it's prefixed with Hugging Face host
	if [[ "$input" == /* ]]; then
		input="https://huggingface.co$input"
	fi

	# Convert link /blob/ copied from browser, if any, into /resolve/ (Hugging Face only)
	if [[ "$input" == https://huggingface.co/* ]]; then
		input="${input/\/blob\///resolve/}"
	fi

	local filename
	filename=$(basename "$input")

	touch "$KNOWN_MODELS"

	if awk -F'\t' -v f="$filename" '$1 == f { found=1; exit } END { exit !found }' "$KNOWN_MODELS" 2>/dev/null; then
		status_line "Skip" "ℹ️  '$filename' already exists in .known.llama"
		return 0
	fi

	printf "%s\t%s\t%s\n" "$filename" "$input" "$note" >> "$KNOWN_MODELS"
	status_line "Added" "✅ '$filename' added to .known.llama"
}

download_model() {
	local url="$2"

	if [[ -z "$url" ]]; then
		local models=()
		local urls=()
		local comments=()
		local line filename rest saved_url comment

		if [[ -f "$KNOWN_MODELS" ]]; then
			while IFS= read -r line || [[ -n "$line" ]]; do
				filename="${line%%$'\t'*}"
				[[ -n "$filename" && "$line" == *$'\t'* ]] || continue

				rest="${line#*$'\t'}"
				saved_url="${rest%%$'\t'*}"

				[[ -n "$saved_url" && "$saved_url" != "-" ]] || continue

				comment=""
				if [[ "$rest" == *$'\t'* ]]; then
					comment="${rest#*$'\t'}"
				fi
				
				if [[ ! -f "$MODELS_DIR/$filename" ]]; then
					models+=("$filename")
					urls+=("$saved_url")
					comments+=("$comment")
				fi
			done < "$KNOWN_MODELS"
		fi

		if [[ ${#models[@]} -gt 0 ]]; then
			echo "Known models available for download:"

			for ((i=0; i<${#models[@]}; i++)); do
				status_line "$((i+1))" "${models[$i]}"
				[[ -n "${comments[$i]}" ]] &&
					printf '%19s %s\n' "" "ⓘ  ${comments[$i]}"
			done

			read -rp "Choose [1-${#models[@]}] or enter URL: " choice

			if [[ "$choice" =~ ^[0-9]+$ ]]; then
				if [[ "$choice" -lt 1 || "$choice" -gt ${#models[@]} ]]; then
					status_line "Error" "❌ Invalid choice."
					return 1
				fi
				url="${urls[$((choice-1))]}"
			else
				url="$choice"
			fi
		else
			read -rp "Enter model URL: " url
		fi
	fi
	local filename="${url%%\?*}"
	filename="${filename##*/}"

	if [[ -z "$filename" ]] || ! [[ "$filename" =~ ^[a-zA-Z0-9._-]+\.gguf$ ]]; then
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

	save_known_model "$filename" "$url"

	status_line "Downloaded" "👮 $filename"
}

delete_model() {
	local models=()
	for file in "$MODELS_DIR"/*.gguf; do
		[[ -f "$file" ]] && models+=("$file")
	done
	
	if [ ${#models[@]} -eq 0 ]; then
		status_line "Error" "❌ No models found."
		return 1
	fi

	local i=1
	local mname mcomment
	for m in "${models[@]}"; do
		mname=$(basename "$m")
		status_line "$i" "$mname"
		mcomment=$(get_model_comment "$mname")
		[[ -n "$mcomment" ]] && printf '%19s %s\n' "" "ⓘ  $mcomment"
		((i++))
	done
	
	read -rp "Choose [1-${#models[@]}]: " choice

	if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#models[@]} ]; then
		status_line "Error" "❌ Invalid choice."
		return 1
	fi

	local target="${models[$((choice-1))]}"

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

save_known_model() {
	local filename="$1"
	local url="$2"
	local tmp="$KNOWN_MODELS.tmp.$$"
	local found=0

	while IFS= read -r line || [[ -n "$line" ]]; do
		local name="${line%%$'\t'*}"
		local rest="${line#*$'\t'}"
		local saved_url="${rest%%$'\t'*}"
		local comment=""

		if [[ "$rest" == *$'\t'* ]]; then
			comment="${rest#*$'\t'}"
		fi

		if [[ "$name" == "$filename" ]]; then
			printf '%s\t%s\t%s\n' "$filename" "$url" "$comment"
			found=1
		else
			printf '%s\n' "$line"
		fi
	done < "$KNOWN_MODELS" > "$tmp"

	if [[ "$found" -eq 0 ]]; then
		printf '%s\t%s\t\n' "$filename" "$url" >> "$tmp"
	fi

	mv "$tmp" "$KNOWN_MODELS"
}

comment_model() {
	shift

	if [[ -z "$MODEL" ]]; then
		status_line "Error" "💔 No model selected."
		return 1
	fi

	local filename
	filename=$(basename "$MODEL")
	local comment="$*"
	local found=0
	local current=""
	local line name rest url
	local tmp="$KNOWN_MODELS.tmp.$$"

	touch "$KNOWN_MODELS" || return 1

	while IFS= read -r line || [[ -n "$line" ]]; do
		name="${line%%$'\t'*}"
		[[ "$line" == *$'\t'* ]] || continue
		rest="${line#*$'\t'}"

		if [[ "$name" == "$filename" ]]; then
			found=1
			if [[ "$rest" == *$'\t'* ]]; then
				current="${rest#*$'\t'}"
			fi
			break
		fi
	done < "$KNOWN_MODELS"

	if [[ -z "$comment" ]]; then
		status_line "Model" "💚 $filename"
		if [[ "$found" -eq 0 ]]; then
			status_line "Comment" "ⓘ  [No comment]"
		else
			status_line "Comment" "ⓘ  ${current:-No comment}"
		fi
		return 0
	fi

	if [[ "$comment" == *$'\t'* || "$comment" == *$'\n'* ]]; then
		status_line "Error" "❌ Tabs and newlines are not allowed in comments."
		return 1
	fi

	if [[ "$found" -eq 0 ]]; then
		printf '%s\t-\t%s\n' "$filename" "$comment" >> "$KNOWN_MODELS"
	else
		while IFS= read -r line || [[ -n "$line" ]]; do
			name="${line%%$'\t'*}"
			if [[ "$name" == "$filename" ]]; then
				rest="${line#*$'\t'}"
				url="${rest%%$'\t'*}"
				printf '%s\t%s\t%s\n' "$filename" "$url" "$comment"
			else
				printf '%s\n' "$line"
			fi
		done < "$KNOWN_MODELS" > "$tmp"

		mv "$tmp" "$KNOWN_MODELS" || return 1
	fi

	status_line "Comment" "ⓘ  Updated for $filename"
}

list_known_models() {
	local filter_url=0

	[[ "$1" == "url" ]] && filter_url=1

	if [[ ! -s "$KNOWN_MODELS" ]]; then
		status_line "Error" "💔 No known models."
		return 1
	fi

	local line filename rest url comment

	while IFS= read -r line || [[ -n "$line" ]]; do
		filename="${line%%$'\t'*}"
		[[ -n "$filename" && "$line" == *$'\t'* ]] || continue

		rest="${line#*$'\t'}"
		url="${rest%%$'\t'*}"
		comment=""

		if [[ "$rest" == *$'\t'* ]]; then
			comment="${rest#*$'\t'}"
		fi

		if [[ "$filter_url" -eq 1 && ( -z "$url" || "$url" == "-" ) ]]; then
			continue
		fi
		
		if [[ -f "$MODELS_DIR/$filename" ]]; then
			local cname
			cname=$(model_name)
			if [[ "$filename" == "$cname" ]]; then
				status_line "Current" "💚 $filename"
			else
				status_line "Available" "📀 $filename"
			fi
		else
			status_line "Known" "☁️  $filename"
		fi
		[[ -n "$comment" ]] && printf '%19s %s\n' "" "ⓘ  $comment"
		echo ""
	done < "$KNOWN_MODELS"
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
				read -rp "Comment (empty to show current): " value
				comment_model comment "$value"
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
			x|14)
				echo "👋 Bye!"
				break
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
			select_model
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
			list_known_models
			;;
		rm|delete)
			delete_model
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
		help|-h|--help)
			echo
			status_line "Syntax" "$0 [command]"
			status_line "(no command)" "🦙 Interactive shell"
			echo
			echo "Commands:"
			status_line "s start" "🟢 Start llama-server"
			status_line ". q stop" "🔴 Stop llama-server"
			status_line "h status" "🟠 Llama-server status"
			status_line "r restart" "🔵 Restart llama-server"
			status_line "m model" "💚 Select current active model"
			status_line "hf add" "🌤️  Add a downloadable model URI"
			status_line "d download" "☁️  Download a model"
			status_line "rm delete" "🗑️  Delete a downloaded model"
			status_line "c comment" "ⓘ  View or edit current model comment"
			status_line "l list" "👮 List all known models"
			status_line "t tail" "🔍 Tail log (live view)"
			status_line "log" "📝 Set log level ($LOG_LEVEL [1..4])"
			status_line "p port" "🚪 Change port (:$PORT)"
			echo
			;;
		*)
			status_line "Parameters" "❓ Use: $0 {start|stop|status|restart|model|add|download|delete|comment|list|tail|log|port}"
			status_line "Shell" "❓ Use: $0 (without parameters) for interactive shell"
			exit 1
			;;
	esac
fi
