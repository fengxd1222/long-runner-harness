#!/bin/bash
# long-runner-dispatch.sh v5.2 - 统一调度器脚本（架构简化版）
# 基于 Anthropic autonomous-coding 模式
# https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents
# Fixes v5.1: C1 PIPESTATUS, C2 skip loop, C3 false-positive completion,
#        C4 session_status leak, I1 IFS parsing, I2 trace field name,
#        I3 curl whitelist, I4 max-turns, M1 shell injection, M2 echo\n, M3 error logging
# v5.2: Simplify trace store → .lr-bootstrap only; add smoke-test gate (STEP 2.5);
#       add external validation (passes_before/after check)

set -e

# Configuration
PROJECT_DIR="${1:-.}"
BATCH_SIZE="${2:-0}"  # 0 = unlimited
DELAY_SECONDS="${DELAY_SECONDS:-3}"
MAX_RETRIES="${MAX_RETRIES:-3}"
MAX_TURNS="${MAX_TURNS:-50}"
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
    echo " Long-Runner Dispatcher v5.2"
    echo " Browser-First Testing + Session Isolation"
    echo " + Smoke-Test Gate + External Validation"
    echo "=========================================="
    echo ""
}

# --- Bootstrap Snapshot Functions ---

generate_bootstrap() {
    local snapshot_file=".lr-bootstrap/env-snapshot.json"
    mkdir -p ".lr-bootstrap"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local project_type="unknown"
    local tech_stack="[]"
    local key_files="[]"
    local key_directories="[]"
    local service_urls="[]"
    local init_command=""
    local git_branch=""
    local recent_commits="[]"
    local file_count=0

    # Detect project type & tech stack
    if [ -f "package.json" ]; then
        project_type="node"
        tech_stack=$(python3 -c "
import json
with open('package.json') as f: d = json.load(f)
deps = list(d.get('dependencies',{}).keys()) + list(d.get('devDependencies',{}).keys())
print(json.dumps(deps[:20]))
" 2>/dev/null || echo '[]')
    elif [ -f "requirements.txt" ] || [ -f "pyproject.toml" ]; then
        project_type="python"
        tech_stack=$(python3 -c "
import json
lines = []
for f in ['requirements.txt']:
    try:
        with open(f) as fh: lines += [l.strip().split('==')[0] for l in fh if l.strip() and not l.startswith('#')]
    except FileNotFoundError: pass
print(json.dumps(lines[:20]))
" 2>/dev/null || echo '[]')
    elif [ -f "Cargo.toml" ]; then
        project_type="rust"
    fi

    # Key files that exist
    key_files=$(python3 -c "
import json, os
candidates = ['app_spec.txt','feature_list.json','package.json','requirements.txt','init.sh','Makefile','README.md','.env.example']
print(json.dumps([f for f in candidates if os.path.exists(f)]))
" 2>/dev/null || echo '[]')

    # Key directories
    key_directories=$(python3 -c "
import json, os
candidates = ['src','lib','app','tests','public','static','templates','migrations','docs']
print(json.dumps([d for d in candidates if os.path.isdir(d)]))
" 2>/dev/null || echo '[]')

    # Init command
    if [ -f "init.sh" ]; then init_command="./init.sh"; fi

    # Git info
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        recent_commits=$(git log --oneline -10 2>/dev/null \
            | python3 -c "import json,sys; print(json.dumps([l.strip() for l in sys.stdin]))" \
            2>/dev/null || echo '[]')
    fi

    # File count
    file_count=$(find . -type f -not -path './.git/*' -not -path './node_modules/*' \
        -not -path './.lr-bootstrap/*' -not -path './logs/*' 2>/dev/null | wc -l | tr -d ' ')

    cat > "$snapshot_file" << BOOTSTRAP
{"generated_at":"$now","project_type":"$project_type","key_directories":$key_directories,"service_urls":$service_urls,"init_command":"$init_command","key_files":$key_files,"tech_stack":$tech_stack,"git_branch":"$git_branch","recent_commits":$recent_commits,"file_count":$file_count}
BOOTSTRAP
    log_success "Bootstrap snapshot written"
}


refresh_bootstrap() {
    local snapshot_file=".lr-bootstrap/env-snapshot.json"
    if [ ! -f "$snapshot_file" ]; then
        generate_bootstrap
        return
    fi
    local age
    age=$(python3 -c "
import json
from datetime import datetime, timezone
with open('$snapshot_file') as f: d = json.load(f)
gen = datetime.fromisoformat(d['generated_at'].replace('Z','+00:00'))
now = datetime.now(timezone.utc)
print(int((now - gen).total_seconds()))
" 2>/dev/null || echo "99999")
    if [ "$age" -gt 3600 ]; then
        log_info "Bootstrap snapshot is ${age}s old, refreshing..."
        generate_bootstrap
    fi
}

# --- End Bootstrap Functions ---

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
      "Bash(./smoke-test.sh)",
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
      "Bash(curl:*)",
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

# Get next feature (supports both formats, skips skipped features)
get_next_feature() {
    python3 -c "
import json, sys

with open('feature_list.json') as f:
    data = json.load(f)

# Support both flat array and {features: [...]} formats
features = data if isinstance(data, list) else data.get('features', [])

for feature in features:
    if feature.get('passes', False): continue
    if feature.get('skipped', False): continue
    deps = feature.get('depends_on', [])
    all_deps_met = all(
        any(f.get('id') == dep and f.get('passes', False) for f in features)
        for dep in deps
    )
    if all_deps_met:
        desc = feature.get('description', 'No description')[:60]
        print(f\"{feature['id']}|||{desc}\")
        sys.exit(0)

# No eligible feature found
sys.exit(1)
" 2>> "$LOG_DIR/dispatch_errors.log"
}

# Count remaining features — hard fail on parse error to prevent false "all done"
count_remaining() {
    local output
    output=$(python3 -c "
import json, sys
with open('feature_list.json') as f:
    data = json.load(f)
features = data if isinstance(data, list) else data.get('features', [])
remaining = sum(1 for f in features if not f.get('passes', False) and not f.get('skipped', False))
total     = len(features)
passed    = sum(1 for f in features if f.get('passes', False))
skipped   = sum(1 for f in features if f.get('skipped', False))
print(f'{remaining}:{total}:{passed}:{skipped}')
" 2>&1)
    if [ $? -ne 0 ]; then
        log_error "Failed to parse feature_list.json: $output"
        exit 1
    fi
    echo "$output"
}

# Main loop
print_header

FORMAT=$(detect_format)
log_info "Project directory: $(pwd)"
log_info "feature_list.json format: $FORMAT"
log_info "Batch size: $([ "$BATCH_SIZE" -eq 0 ] && echo 'unlimited' || echo "$BATCH_SIZE")"
log_info "Delay between sessions: ${DELAY_SECONDS}s"
log_info "Max retries per feature: ${MAX_RETRIES}"

# Initialize bootstrap snapshot
generate_bootstrap
echo ""

count=0
consecutive_failures=0

while true; do
    # Check remaining features — IFS=':' avoids the character-set trap of IFS='|||'
    IFS=':' read -r remaining total passed skipped <<< "$(count_remaining)"

    if [ "$remaining" -eq 0 ]; then
        echo ""
        echo "=========================================="
        echo " ALL FEATURES COMPLETED"
        echo "=========================================="
        echo "Total features:   $total"
        echo "Passed:           $passed"
        echo "Skipped:          ${skipped:-0}"
        echo "Sessions run:     $count"
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
    if not f.get('passes', False) and not f.get('skipped', False):
        deps = f.get('depends_on', [])
        if deps:
            print(f\"  - {f['id']}: needs {deps}\")
        else:
            print(f\"  - {f['id']}: {f.get('description', '')[:50]}\")
" 2>> "$LOG_DIR/dispatch_errors.log"
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
    log_info "Progress: $passed/$total completed, $remaining remaining, ${skipped:-0} skipped"
    echo ""

    # Build the detailed Coding Agent prompt
    PROMPT="You are a CODING AGENT continuing work on a long-running autonomous development task.
This is a FRESH context window - you have no memory of previous sessions.

## YOUR TASK: Implement feature $feature_id

## STEP 1: GET YOUR BEARINGS (MANDATORY)
If .lr-bootstrap/env-snapshot.json exists:
  cat .lr-bootstrap/env-snapshot.json
  This file contains everything you need about the project.
Else fall back to the original exploration commands:
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

## STEP 2.5: SMOKE TEST (MANDATORY GATE)
Run the smoke test to verify the app is in a working state BEFORE doing any new work:
\`\`\`bash
if [ -f smoke-test.sh ]; then
  chmod +x smoke-test.sh
  ./smoke-test.sh
  if [ \$? -ne 0 ]; then
    echo \"SMOKE TEST FAILED: App is broken. Fix before implementing new features.\"
    # Find what broke it using git log and fix it
  fi
fi
\`\`\`
If the smoke test fails, you MUST fix the breakage before implementing feature $feature_id.
Use git log to find recent commits that may have caused the regression.

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
Append a rich entry to claude-progress.txt:
\`\`\`
## Session {N} — {ISO-8601} — Feature $feature_id
- Status: completed | failed | partial
- Changes: {comma-separated list of modified files}
- Regression: {feature_id} ✅/❌, ...
- Smoke-test: ✅/❌
- Issues: {issues found, or "none"}
- Hypothesis: {causal analysis if debugging, or "none"}
- Metrics: {passed}/{total} features
- Next: {next_feature_id} — {brief description}
\`\`\`

## STEP 9: CLEAN EXIT
Ensure: all code committed, progress updated, app in working state.
If code is broken and unfixable, use: git revert HEAD --no-edit

Report your results when complete."

    # Record passes count before session (for external validation)
    IFS=':' read -r _rem _tot passes_before _skip <<< "$(count_remaining)"

    # Run the session
    log_file="$LOG_DIR/${feature_id}_$(date +%Y%m%d_%H%M%S).log"
    session_status="success"  # Reset each iteration (Fix C4: prevent stale status leaking)

    # Fix C1: capture claude's exit code via PIPESTATUS, not tee's
    set +e
    claude --print \
        --max-turns "$MAX_TURNS" \
        --settings .claude_settings.json \
        -p "$PROMPT" 2>&1 | tee "$log_file"
    session_exit_code=${PIPESTATUS[0]}
    set -e

    if [ "$session_exit_code" -eq 0 ]; then
        # External validation: verify passes count actually increased
        IFS=':' read -r _rem2 _tot2 passes_after _skip2 <<< "$(count_remaining)"
        if [ "${passes_after:-0}" -le "${passes_before:-0}" ]; then
            log_warning "External validation FAIL: exit 0 but passes unchanged (${passes_before} -> ${passes_after}). Treating as false success."
            session_status="false_success"
            consecutive_failures=$((consecutive_failures + 1))
        else
            log_success "Session completed for $feature_id (exit: 0, passes: ${passes_before} -> ${passes_after})"
            session_status="success"
            consecutive_failures=0
        fi
    else
        session_status="failed"
        log_warning "Session failed for $feature_id (exit: $session_exit_code)"
        consecutive_failures=$((consecutive_failures + 1))

        if [ "$consecutive_failures" -ge "$MAX_RETRIES" ]; then
            log_error "Failed $MAX_RETRIES consecutive times. Skipping $feature_id."
            # Fix C2: set skipped=true so get_next_feature won't re-select this feature
            SKIP_FEATURE="$feature_id" \
            SKIP_RETRIES="$MAX_RETRIES" \
            python3 -c "
import json, os
fid     = os.environ['SKIP_FEATURE']
retries = os.environ['SKIP_RETRIES']
with open('feature_list.json') as f:
    data = json.load(f)
features = data if isinstance(data, list) else data.get('features', [])
for feat in features:
    if feat['id'] == fid:
        feat['skipped'] = True
        feat['notes'] = feat.get('notes', '') + f' [SKIPPED: {retries} consecutive failures]'
        break
with open('feature_list.json', 'w') as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
" 2>> "$LOG_DIR/dispatch_errors.log" || log_warning "Failed to mark feature as skipped"
            consecutive_failures=0
        fi
    fi

    # Post-session: refresh bootstrap snapshot
    refresh_bootstrap

    count=$((count + 1))

    # Delay before next session
    if [ "$remaining" -gt 1 ]; then
        log_info "Waiting ${DELAY_SECONDS}s before next session..."
        sleep "$DELAY_SECONDS"
    fi
done
