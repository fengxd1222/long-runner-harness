#!/bin/bash
# long-runner-dispatch.sh v4.0 - 统一调度器脚本
# 基于 Anthropic autonomous-coding 模式
# https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents

set -e

# Configuration
PROJECT_DIR="${1:-.}"
BATCH_SIZE="${2:-0}"  # 0 = unlimited
DELAY_SECONDS="${DELAY_SECONDS:-3}"
MAX_RETRIES="${MAX_RETRIES:-3}"
LOG_DIR="logs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

print_header() {
    echo ""
    echo "=========================================="
    echo " Long-Runner Dispatcher v4.0"
    echo " Browser-First Testing + Session Isolation"
    echo "=========================================="
    echo ""
}

# Validate project directory
cd "$PROJECT_DIR" || {
    log_error "Project directory not found: $PROJECT_DIR"
    exit 1
}

# Check required files
if [ ! -f "feature_list.json" ]; then
    log_error "feature_list.json not found. Run '/long-runner init' first."
    exit 1
fi

if [ ! -f ".claude_settings.json" ]; then
    log_warning ".claude_settings.json not found. Creating default..."
    cat > .claude_settings.json << 'EOF'
{
  "sandbox": {
    "enabled": true,
    "autoAllowBashIfSandboxed": true
  },
  "permissions": {
    "defaultMode": "acceptEdits",
    "allow": [
      "Read(./**)",
      "Write(./**)",
      "Edit(./**)",
      "Glob(./**)",
      "Grep(./**)",
      "Bash(npm:*)",
      "Bash(node:*)",
      "Bash(git:*)",
      "Bash(python:*)",
      "Bash(python3:*)",
      "Bash(pip:*)",
      "Bash(cargo:*)",
      "Bash(make:*)",
      "Bash(./init.sh)",
      "Bash(ls:*)",
      "Bash(cat:*)",
      "Bash(head:*)",
      "Bash(tail:*)",
      "Bash(wc:*)",
      "Bash(grep:*)",
      "Bash(mkdir:*)",
      "Bash(cp:*)",
      "Bash(chmod:*)",
      "Bash(sleep:*)",
      "Bash(pwd)",
      "Bash(ps:*)",
      "Bash(lsof:*)",
      "Bash(pkill:*)",
      "mcp__playwright__*"
    ]
  }
}
EOF
    log_success "Created .claude_settings.json"
fi

# Create log directory
mkdir -p "$LOG_DIR"
mkdir -p "evidence"

# Detect feature_list.json format (flat array or {features: [...]})
detect_format() {
    python3 -c "
import json
with open('feature_list.json') as f:
    data = json.load(f)
if isinstance(data, list):
    print('flat')
elif isinstance(data, dict) and 'features' in data:
    print('wrapped')
else:
    print('unknown')
" 2>/dev/null
}

# Get next feature (supports both formats)
get_next_feature() {
    python3 -c "
import json, sys

with open('feature_list.json') as f:
    data = json.load(f)

# Support both flat array and {features: [...]} formats
features = data if isinstance(data, list) else data.get('features', [])

for feature in features:
    if not feature.get('passes', False):
        deps = feature.get('depends_on', [])
        all_deps_met = all(
            any(f.get('id') == dep and f.get('passes', False) for f in features)
            for dep in deps
        )
        if all_deps_met:
            desc = feature.get('description', 'No description')[:60]
            print(f\"{feature['id']}|||{desc}\")
            sys.exit(0)

# No feature found
sys.exit(1)
" 2>/dev/null
}

# Count remaining features
count_remaining() {
    python3 -c "
import json
with open('feature_list.json') as f:
    data = json.load(f)
features = data if isinstance(data, list) else data.get('features', [])
remaining = sum(1 for f in features if not f.get('passes', False))
total = len(features)
passed = total - remaining
print(f'{remaining}|||{total}|||{passed}')
" 2>/dev/null || echo "0|||0|||0"
}

# Main loop
print_header

FORMAT=$(detect_format)
log_info "Project directory: $(pwd)"
log_info "feature_list.json format: $FORMAT"
log_info "Batch size: $([ "$BATCH_SIZE" -eq 0 ] && echo 'unlimited' || echo "$BATCH_SIZE")"
log_info "Delay between sessions: ${DELAY_SECONDS}s"
log_info "Max retries per feature: ${MAX_RETRIES}"
echo ""

count=0
consecutive_failures=0

while true; do
    # Check remaining features
    IFS='|||' read -r remaining total passed <<< "$(count_remaining)"

    if [ "$remaining" -eq 0 ]; then
        echo ""
        echo "=========================================="
        echo " ALL FEATURES COMPLETED"
        echo "=========================================="
        echo "Total features: $total"
        echo "Sessions run: $count"
        echo ""
        log_success "Project is complete!"
        exit 0
    fi

    # Batch limit check
    if [ "$BATCH_SIZE" -gt 0 ] && [ "$count" -ge "$BATCH_SIZE" ]; then
        log_warning "Batch limit reached ($BATCH_SIZE). Pausing."
        echo ""
        echo "To continue, run:"
        echo "  ~/.claude/scripts/long-runner-dispatch.sh $(pwd) $BATCH_SIZE"
        exit 0
    fi

    # Get next feature
    result=$(get_next_feature 2>/dev/null || echo "")

    if [ -z "$result" ]; then
        log_warning "No features with satisfied dependencies found."
        log_info "Remaining $remaining features may have unmet dependencies."
        echo ""
        # Show blocked features
        python3 -c "
import json
with open('feature_list.json') as f:
    data = json.load(f)
features = data if isinstance(data, list) else data.get('features', [])
print('Blocked features:')
for f in features:
    if not f.get('passes', False):
        deps = f.get('depends_on', [])
        if deps:
            print(f\"  - {f['id']}: needs {deps}\")
        else:
            print(f\"  - {f['id']}: {f.get('description', '')[:50]}\")
" 2>/dev/null
        exit 1
    fi

    # Parse result
    feature_id="${result%%|||*}"
    feature_desc="${result#*|||}"

    echo ""
    echo "=========================================="
    echo " SESSION $((count + 1))"
    echo "=========================================="
    log_info "Feature: $feature_id"
    log_info "Description: $feature_desc"
    log_info "Progress: $passed/$total completed, $remaining remaining"
    echo ""

    # Build the detailed Coding Agent prompt
    PROMPT="You are a CODING AGENT continuing work on a long-running autonomous development task.
This is a FRESH context window - you have no memory of previous sessions.

## YOUR TASK: Implement feature $feature_id

## STEP 1: GET YOUR BEARINGS (MANDATORY)
Start by orienting yourself:
\`\`\`bash
pwd
ls -la
cat app_spec.txt
cat feature_list.json | head -50
cat claude-progress.txt
git log --oneline -20
cat feature_list.json | grep '\"passes\": false' | wc -l
\`\`\`
Understanding app_spec.txt is critical - it contains the full requirements.

## STEP 2: START SERVERS
If init.sh exists, run it:
\`\`\`bash
chmod +x init.sh
./init.sh
\`\`\`

## STEP 3: VERIFICATION TEST (CRITICAL!)
MANDATORY BEFORE NEW WORK: The previous session may have introduced bugs.
Run 1-2 feature tests marked as passes=true using Playwright MCP browser automation.
If you find ANY issues (functional or visual):
- Mark that feature as passes=false immediately
- Fix all issues BEFORE moving to new features
- Check for: white-on-white text, random characters, incorrect timestamps,
  layout overflow, buttons too close, missing hover states, console errors

## STEP 4: IMPLEMENT FEATURE $feature_id
Read the feature requirements from feature_list.json.
Implement the feature (frontend and/or backend as needed).
Focus on completing this ONE feature perfectly.

## STEP 5: BROWSER UI VERIFICATION (MANDATORY!)
You MUST verify through the actual browser UI using Playwright MCP tools:
- mcp__playwright__browser_navigate - Navigate to app URL
- mcp__playwright__browser_snapshot - Get accessibility snapshot (prefer over screenshot for decisions)
- mcp__playwright__browser_click - Click elements
- mcp__playwright__browser_type - Type text
- mcp__playwright__browser_fill_form - Fill forms
- mcp__playwright__browser_press_key - Press keys
- mcp__playwright__browser_hover - Hover elements
- mcp__playwright__browser_wait_for - Wait for conditions
- mcp__playwright__browser_take_screenshot - Save screenshots to evidence/
- mcp__playwright__browser_console_messages - Check for JS errors

DO: Test through real browser UI like a human user. Take screenshots. Check console errors.
DON'T: Only test with curl. Use JS evaluate to bypass UI. Skip visual verification.

## STEP 6: UPDATE feature_list.json
ONLY change the passes field after browser verification with screenshots:
\"passes\": false  -->  \"passes\": true
NEVER remove tests, edit descriptions, or modify steps.

## STEP 7: GIT COMMIT
\`\`\`bash
git add .
git commit -m \"feat: implement $feature_id - verified end-to-end\"
\`\`\`

## STEP 8: UPDATE PROGRESS
Update claude-progress.txt with what you accomplished, tests passing count, and next priority.

## STEP 9: CLEAN EXIT
Ensure: all code committed, progress updated, app in working state.
If code is broken and unfixable, use: git revert HEAD --no-edit

Report your results when complete."

    # Run the session
    log_file="$LOG_DIR/${feature_id}_$(date +%Y%m%d_%H%M%S).log"

    if claude --print \
        --settings .claude_settings.json \
        -p "$PROMPT" 2>&1 | tee "$log_file"; then
        log_success "Session completed successfully for $feature_id"
        consecutive_failures=0
    else
        session_status=$?
        log_warning "Session exited with status: $session_status"
        consecutive_failures=$((consecutive_failures + 1))

        if [ "$consecutive_failures" -ge "$MAX_RETRIES" ]; then
            log_error "Failed $MAX_RETRIES consecutive times. Skipping $feature_id."
            # Record failure in feature notes
            python3 -c "
import json
with open('feature_list.json') as f:
    data = json.load(f)
features = data if isinstance(data, list) else data.get('features', [])
for f in features:
    if f['id'] == '$feature_id':
        f['notes'] = f.get('notes', '') + ' [SKIPPED: $MAX_RETRIES consecutive failures]'
        break
with open('feature_list.json', 'w') as f:
    if isinstance(data, list):
        json.dump(data, f, indent=2, ensure_ascii=False)
    else:
        json.dump(data, f, indent=2, ensure_ascii=False)
" 2>/dev/null
            consecutive_failures=0
        fi
    fi

    count=$((count + 1))

    # Delay before next session
    if [ "$remaining" -gt 1 ]; then
        log_info "Waiting ${DELAY_SECONDS}s before next session..."
        sleep "$DELAY_SECONDS"
    fi
done
