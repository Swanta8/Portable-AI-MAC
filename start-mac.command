#!/bin/bash
# ================================================================
# PORTABLE UNCENSORED AI - MAC LAUNCHER
# ================================================================
# Just double-click this file on any Mac to start your portable AI.
# Everything runs from the USB drive. Nothing is installed on the Mac.
# ================================================================

# Move to the USB drive directory where this script lives
cd "$(dirname "$0")"

USB_DIR=$(pwd)
MAC_OLLAMA_DIR="$USB_DIR/ollama_mac"
DATA_DIR="$USB_DIR/ollama/data"

echo "==================================================="
echo "    Launching Portable AI Engine for Mac...      "
echo "==================================================="

# -----------------------------------------------------------------
# STEP 1: Download Mac Ollama Engine (first time only)
# -----------------------------------------------------------------
if [ ! -d "$MAC_OLLAMA_DIR/Ollama.app" ] && [ ! -f "$MAC_OLLAMA_DIR/ollama" ]; then
    echo "First time on Mac! Downloading the AI Engine..."
    mkdir -p "$MAC_OLLAMA_DIR"
    curl -L --progress-bar "https://github.com/ollama/ollama/releases/latest/download/ollama-darwin.zip" -o "$MAC_OLLAMA_DIR/ollama-darwin.zip"
    echo "Extracting..."
    unzip -o -q "$MAC_OLLAMA_DIR/ollama-darwin.zip" -d "$MAC_OLLAMA_DIR/"
    rm "$MAC_OLLAMA_DIR/ollama-darwin.zip"
    
    # Make executable
    if [ -f "$MAC_OLLAMA_DIR/Ollama.app/Contents/MacOS/Ollama" ]; then
        chmod +x "$MAC_OLLAMA_DIR/Ollama.app/Contents/MacOS/Ollama"
    elif [ -f "$MAC_OLLAMA_DIR/ollama" ]; then
        chmod +x "$MAC_OLLAMA_DIR/ollama"
    fi
    
    echo "Mac Engine Setup Complete!"
    echo ""
fi

# -----------------------------------------------------------------
# STEP 2: Download AnythingLLM DMG (kept as-is for portable launch on exFAT)
# -----------------------------------------------------------------
if [ ! -f "$USB_DIR/anythingllm_mac/AnythingLLM_Installer.dmg" ]; then
    echo "First time setup: Downloading AnythingLLM directly to USB..."
    echo "NO installation on the Mac! Everything stays on the drive."
    mkdir -p "$USB_DIR/anythingllm_mac"

    # Download the DMG — we launch directly from the mounted DMG each run,
    # because macOS 26+ refuses to validate code signatures on exFAT volumes.
    curl -L --progress-bar "https://cdn.anythingllm.com/latest/AnythingLLMDesktop-Silicon.dmg" -o "$USB_DIR/anythingllm_mac/AnythingLLM_Installer.dmg"

    echo "AnythingLLM downloaded and ready!"
fi

# -----------------------------------------------------------------
# STEP 3: Launch the AI Engine
# -----------------------------------------------------------------
echo ""
echo "Starting AI Engine from USB..."

# Lock all data paths to the USB drive
export OLLAMA_MODELS="$DATA_DIR"
export STORAGE_DIR="$USB_DIR/anythingllm_data"
mkdir -p "$STORAGE_DIR"

# -----------------------------------------------------------------
# ENSURE ANYTHINGLLM USES EXTERNAL OLLAMA (not built-in)
# -----------------------------------------------------------------
ENV_FILE="$STORAGE_DIR/storage/.env"
mkdir -p "$STORAGE_DIR/storage"

# Read first model
DEFAULT_MODEL="nemomix-local"
if [ -f "$USB_DIR/models/installed-models.txt" ]; then
    DEFAULT_MODEL=$(head -n 1 "$USB_DIR/models/installed-models.txt" | cut -d '|' -f 1)
fi

NEEDS_FIX=0
if [ ! -f "$ENV_FILE" ]; then
    NEEDS_FIX=1
elif ! grep -q "LLM_PROVIDER=ollama" "$ENV_FILE" || grep -q "LLM_PROVIDER=anythingllm_ollama" "$ENV_FILE"; then
    NEEDS_FIX=1
fi

if [ "$NEEDS_FIX" = "1" ]; then
    echo "Configuring AnythingLLM to use external Ollama engine..."
    cat > "$ENV_FILE" << EOF
LLM_PROVIDER=ollama
OLLAMA_BASE_PATH=http://127.0.0.1:11434
OLLAMA_MODEL_PREF=$DEFAULT_MODEL
OLLAMA_MODEL_TOKEN_LIMIT=4096
EMBEDDING_ENGINE=native
VECTOR_DB=lancedb
EOF
fi

# -------------------------------------------------------
# SHOW INSTALLED MODELS
# -------------------------------------------------------
if [ -f "$USB_DIR/models/installed-models.txt" ]; then
    echo ""
    echo "Installed models:"
    while IFS="|" read -r local_name nice_name tag; do
        if [ ! -z "$nice_name" ]; then
            echo "  - $nice_name [$tag]"
        fi
    done < "$USB_DIR/models/installed-models.txt"
    echo ""
fi

# Start Ollama in background
if [ -f "$MAC_OLLAMA_DIR/Ollama.app/Contents/MacOS/Ollama" ]; then
    "$MAC_OLLAMA_DIR/Ollama.app/Contents/MacOS/Ollama" serve > /dev/null 2>&1 &
elif [ -f "$MAC_OLLAMA_DIR/ollama" ]; then
    "$MAC_OLLAMA_DIR/ollama" serve > /dev/null 2>&1 &
else
    echo "Error: Could not find the Ollama binary on the USB drive!"
fi
OLLAMA_PID=$!

sleep 3

echo ""
echo "==================================================="
echo "  SYSTEM ONLINE: Your AI is running from the USB!  "
echo "==================================================="
echo ""

# -----------------------------------------------------------------
# STEP 4: Launch AnythingLLM
# -----------------------------------------------------------------
echo ""
echo "Starting AI Interface from USB..."

# CRITICAL: We MUST wipe Electron path caches for true portability!
# This fixes the "JavaScript error" when moving USBs between different Macs.
[ -f "$STORAGE_DIR/config.json" ] && rm "$STORAGE_DIR/config.json"
[ -d "$STORAGE_DIR/Cache" ] && rm -rf "$STORAGE_DIR/Cache"
[ -d "$STORAGE_DIR/Code Cache" ] && rm -rf "$STORAGE_DIR/Code Cache"
[ -d "$STORAGE_DIR/GPUCache" ] && rm -rf "$STORAGE_DIR/GPUCache"

# Launch AnythingLLM by mounting the DMG and opening the app from the mount.
# (Apps signed for macOS 26+ won't validate from exFAT — the DMG is internally
# APFS so signature & xattrs survive.)
DMG_PATH="$USB_DIR/anythingllm_mac/AnythingLLM_Installer.dmg"
APP_PATH_USB="$USB_DIR/anythingllm_mac/AnythingLLM.app"
ANYTHINGLLM_MOUNT=""

if [ -f "$DMG_PATH" ]; then
    echo "Mounting AnythingLLM (no install — runs from DMG)..."
    ANYTHINGLLM_MOUNT=$(hdiutil attach -nobrowse "$DMG_PATH" | awk -F'\t' '$3 ~ /^\/Volumes\// {print $3; exit}')
    if [ -n "$ANYTHINGLLM_MOUNT" ] && [ -d "$ANYTHINGLLM_MOUNT/AnythingLLM.app" ]; then
        echo "Opening AnythingLLM..."
        open -a "$ANYTHINGLLM_MOUNT/AnythingLLM.app" --args --user-data-dir="$STORAGE_DIR"
    else
        echo "ERROR: Could not mount DMG or find AnythingLLM.app inside it!"
        ANYTHINGLLM_MOUNT=""
    fi
elif [ -d "$APP_PATH_USB" ]; then
    # Legacy fallback for older installs without DMG (may fail on macOS 26+)
    echo "Opening AnythingLLM (legacy direct launch)..."
    open -a "$APP_PATH_USB" --args --user-data-dir="$STORAGE_DIR"
else
    echo "ERROR: Neither AnythingLLM DMG nor app found on USB!"
fi

echo ""
echo "Keep this terminal open while you chat!"
echo "Press [ENTER] to shut down the AI safely."
echo ""

# Wait for user, then clean shutdown
read -p "Hit [ENTER] to turn off the Engine..."
kill $OLLAMA_PID 2>/dev/null
killall AnythingLLM 2>/dev/null
sleep 1
if [ -n "$ANYTHINGLLM_MOUNT" ]; then
    hdiutil detach "$ANYTHINGLLM_MOUNT" >/dev/null 2>&1 || hdiutil detach "$ANYTHINGLLM_MOUNT" -force >/dev/null 2>&1 || true
fi
echo "AI shut down. You may safely eject the USB."
