#!/bin/bash
# Envision Construction - Daily Sync & Maintenance Orchestrator
# Saturday, July 25, 2026

# Configuration
PROJECT_ROOT="$HOME/GitHub"
CC_ROOT="$PROJECT_ROOT/central-command"
PWM_ROOT="$PROJECT_ROOT/prometheus-workspace-mcp"
GEMINI_MEMORY_ROOT="$PROJECT_ROOT/gemini-memory"
LOG_DIR="$HOME/.gemini/logs"
LOG_FILE="$LOG_DIR/daily_sync.log"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GEMINI_EXEC="/Users/avireddy/.local/bin/gemini"

mkdir -p "$LOG_DIR"

echo "[$TIMESTAMP] Starting daily sync..." >> "$LOG_FILE"

# 1. Update prometheus-workspace-mcp (Reindexing)
echo "[$TIMESTAMP] Reindexing Workspace..." >> "$LOG_FILE"
if cd "$PWM_ROOT" 2>/dev/null; then
    # Use the local virtual environment if it exists
    if [ -f ".venv/bin/python3" ]; then
        PYTHON_EXEC="./.venv/bin/python3"
    else
        PYTHON_EXEC="python3"
    fi
    # Run the local reindexer script
    if [ -f "turbovec_indexer.py" ]; then
        $PYTHON_EXEC turbovec_indexer.py >> "$LOG_FILE" 2>&1
    else
        echo "Warning: turbovec_indexer.py not found in $PWM_ROOT" >> "$LOG_FILE"
    fi
else
    echo "Error: Could not navigate to $PWM_ROOT" >> "$LOG_FILE"
fi

# 2. Update central-command State
echo "[$TIMESTAMP] Updating central-command state..." >> "$LOG_FILE"
if cd "$CC_ROOT" 2>/dev/null; then
    # Update the last_updated field in STATE.md
    if [ -f ".planning/STATE.md" ]; then
        sed -i '' "s/last_updated: \".*\"/last_updated: \"$TIMESTAMP\"/" .planning/STATE.md
        git add .planning/STATE.md
        git commit -m "chore: daily state sync $TIMESTAMP" --quiet >> "$LOG_FILE" 2>&1
    else
        echo "Warning: STATE.md not found in $CC_ROOT/.planning/" >> "$LOG_FILE"
    fi
else
    echo "Error: Could not navigate to $CC_ROOT" >> "$LOG_FILE"
fi

# 3. Intelligent Analysis Dispatch (Baton-Passing)
echo "[$TIMESTAMP] Dispatching high-tier analysis..." >> "$LOG_FILE"
# Use 'gemini' CLI for orchestration.
if [ -f "$GEMINI_EXEC" ]; then
    # Use -p/--prompt for non-interactive mode.
    $GEMINI_EXEC --prompt "
    Analyze the last 24h of activity across the Envision platform repositories.
    Generate a concise summary of work completed and identify the top priority for today.
    If you detect significant blockers or architectural deviations, invoke the 'generalist' 
    subagent with model='opus' for a deep-dive remediation plan.
    Append the result to your project's MEMORY.md.
    " >> "$LOG_FILE" 2>&1
else
    echo "Warning: '$GEMINI_EXEC' not found. Skipping analysis dispatch." >> "$LOG_FILE"
fi

echo "[$TIMESTAMP] Daily sync complete." >> "$LOG_FILE"
