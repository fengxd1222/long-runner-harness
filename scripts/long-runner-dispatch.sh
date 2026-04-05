#!/bin/bash
# long-runner-dispatch.sh v5.0 - 统一调度器脚本
# 基于 Anthropic autonomous-coding 模式
# https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents
# + Meta-Harness trace store (v2)

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
    echo " Long-Runner Dispatcher v5.0"
    echo " Browser-First Testing + Session Isolation"
    echo " + Meta-Harness Trace Store"
    echo "=========================================="
    echo ""
}

# --- Meta-Harness Trace Store Functions ---

init_trace_store() {
    local ts_dir=".long-runner"
    if [ ! -d "$ts_dir" ]; then
        log_info "Initializing trace store at $ts_dir/"
        mkdir -p "$ts_dir/bootstrap"
        mkdir -p "$ts_dir/traces"
        mkdir -p "$ts_dir/hypotheses"
        mkdir -p "$ts_dir/pareto"
        mkdir -p "$ts_dir/summaries"

        local now
        now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

        echo "{\"version\":2,\"created_at\":\"$now\",\"schema_version\":2}" \
            > "$ts_dir/meta.json"
        echo '[]' > "$ts_dir/traces/index.json"
        echo '# Open Hypotheses\n(No open hypotheses yet)' \
            > "$ts_dir/hypotheses/open.md"
        cat > "$ts_dir/pareto/metrics.json" << 'PARETO'
{
  "dimensions": ["functional", "visual_quality", "console_errors"],
  "current": {
    "functional": 0,
    "visual_quality": 0,
    "console_errors": 0
  },
  "history": []
}
PARETO
        echo '{"snapshots":[]}' > "$ts_dir/pareto/frontier.json"
        log_success "Trace store initialized"
    fi
}

generate_bootstrap() {
    local snapshot_file=".long-runner/bootstrap/env-snapshot.json"
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
        -not -path './.long-runner/*' -not -path './logs/*' 2>/dev/null | wc -l | tr -d ' ')

    cat > "$snapshot_file" << BOOTSTRAP
{"generated_at":"$now","project_type":"$project_type","key_directories":$key_directories,"service_urls":$service_urls,"init_command":"$init_command","key_files":$key_files,"tech_stack":$tech_stack,"git_branch":"$git_branch","recent_commits":$recent_commits,"file_count":$file_count}
BOOTSTRAP
    log_success "Bootstrap snapshot written"
}

update_trace_index() {
    local session_file="$1"
    local feature_id="$2"
    local status="$3"
    local trace_id
    trace_id=$(basename "$session_file" 2>/dev/null || echo "unknown")
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    python3 -c "
import json
idx_file = '.long-runner/traces/index.json'
try:
    with open(idx_file) as f: idx = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    idx = []
idx.append({
    'session_file': '$session_file',
    'feature_id': '$feature_id',
    'trace_id': '$trace_id',
    'status': '$status',
    'recorded_at': '$now'
})
with open(idx_file, 'w') as f: json.dump(idx, f, indent=2)
" 2>/dev/null
    log_info "Trace index updated: $feature_id -> $status"
}

refresh_bootstrap() {
    local snapshot_file=".long-runner/bootstrap/env-snapshot.json"
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

# --- End Trace Store Functions ---

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

# Initialize trace store and bootstrap snapshot
init_trace_store
generate_bootstrap
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
If .long-runner/bootstrap/env-snapshot.json exists:
  cat .long-runner/bootstrap/env-snapshot.json
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

## STEP 1.5: READ TRACE STORE FOR CONTEXT
Read last 3 session summaries for continuity:
\`\`\`bash
for f in \$(ls -t .long-runner/summaries/ 2>/dev/null | head -3); do cat .long-runner/summaries/\$f; done
\`\`\`
Read open hypotheses:
\`\`\`bash
cat .long-runner/hypotheses/open.md
\`\`\`
Read carry-forward lessons from recent hypothesis files:
\`\`\`bash
for f in \$(ls -t .long-runner/hypotheses/*.hypothesis.json 2>/dev/null | head -5); do
  python3 -c \"import json; d=json.load(open('\$f')); [print(l) for l in d.get('carry_forward',[])]\" 2>/dev/null
done
\`\`\`

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

## STEP 5.5: WRITE CAUSAL HYPOTHESES (when debugging)
When you encounter a failure and attempt a fix:
1. Write hypothesis to .long-runner/hypotheses/open.md:
   \`\`\`bash
   cat >> .long-runner/hypotheses/open.md << 'HYP'
   ## [ACTIVE] $feature_id - {short description}
   - Hypothesis: {what I think is wrong}
   - Action: {what I'm trying}
   - Expected: {what should happen}
   HYP
   \`\`\`
2. After resolution, update with outcome and write full JSON to .long-runner/hypotheses/{SESSION_ID}.hypothesis.json

## STEP 6: UPDATE feature_list.json
ONLY change the passes field after browser verification with screenshots:
\"passes\": false  -->  \"passes\": true
NEVER remove tests, edit descriptions, or modify steps.

## STEP 7: GIT COMMIT
\`\`\`bash
git add .
git commit -m \"feat: implement $feature_id - verified end-to-end\"
\`\`\`

## STEP 7.5: UPDATE PARETO METRICS
After completing a feature, update metrics:
\`\`\`bash
python3 -c \"
import json
with open('.long-runner/pareto/metrics.json') as f: m = json.load(f)
with open('feature_list.json') as f:
  features = json.load(f)
  if isinstance(features, dict): features = features.get('features', [])
  m['current']['functional'] = sum(1 for f in features if f.get('passes'))
with open('.long-runner/pareto/metrics.json', 'w') as f: json.dump(m, f, indent=2)
\"
\`\`\`

## STEP 8: UPDATE PROGRESS
Update claude-progress.txt with what you accomplished, tests passing count, and next priority.

## STEP 8.5: WRITE STRUCTURED SUMMARY
Write .long-runner/summaries/$feature_id.summary.md containing:
- Session ID, Feature ID, Status
- Changes made (files modified/created)
- Regression tests run and results
- Issues found and fixed
- Token usage if available
- Next priority

## STEP 9: CLEAN EXIT
Ensure: all code committed, progress updated, app in working state.
If code is broken and unfixable, use: git revert HEAD --no-edit

## STEP 10.5: WRITE SESSION TRACE
Write .long-runner/traces/$feature_id.trace.json containing:
{\"session_id\":\"$feature_id\",\"feature_id\":\"$feature_id\",\"started_at\":\"ISO-8601\",\"status\":\"completed\",\"files_modified\":[],\"files_created\":[],\"git_commit\":\"$(git rev-parse HEAD 2>/dev/null || echo unknown)\"}
Then update trace index:
\`\`\`bash
python3 -c \"import json; idx=json.load(open('.long-runner/traces/index.json')); idx.append({'session_id':'$feature_id','feature_id':'$feature_id','status':'completed'}); json.dump(idx, open('.long-runner/traces/index.json','w'), indent=2)\"
\`\`\`

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

    # Post-session trace store updates
    update_trace_index "$log_file" "$feature_id" "${session_status:-success}"
    refresh_bootstrap

    count=$((count + 1))

    # Delay before next session
    if [ "$remaining" -gt 1 ]; then
        log_info "Waiting ${DELAY_SECONDS}s before next session..."
        sleep "$DELAY_SECONDS"
    fi
done
