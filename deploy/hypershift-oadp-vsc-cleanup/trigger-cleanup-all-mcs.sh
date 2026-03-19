#!/usr/bin/env bash
#
# Trigger / check / tail the oadp-vsc-cleanup CronJob on each MC.
#
# Modes:
#   --check      Check if CronJob oadp-vsc-cleanup exists on each MC (useful for phased rollouts).
#   --trigger    Create a manual Job on each MC, wait, show first N log lines. (default)
#   --status     Check status of all manual-cleanup-* jobs on each MC (name, status, duration).
#   --tail       Show last N lines of logs for each manual-cleanup-* job on each MC.
#
# PREREQUISITES:
#   1. ocm login --token=...
#   2. CronJob oadp-vsc-cleanup must exist in openshift-adp on each MC (for trigger mode)
#
# Usage:
#   ./trigger-cleanup-all-mcs.sh [OPTIONS]
#
# Options:
#   --mc <name>        Target only this MC (can be repeated). Skips discovery.
#   --check            Check if CronJob exists on each MC and show its suspended state.
#   --trigger          Create a manual Job on each MC (default if no mode specified).
#   --status           Check status of manual-cleanup-* jobs on each MC (no job creation).
#   --tail             Show last N lines of logs for each manual-cleanup-* job on each MC.
#   --lines <N>        Number of log lines to show (default: 50). Used in --trigger and --tail.
#   --wait <seconds>   Seconds to wait for pod logs after creation (default: 30). --trigger only.
#   --dry-run          Only show what would be done; do not create jobs. --trigger only.
#   -h, --help         Show help.
#
# Examples:
#   # Trigger on specific MCs
#   ./trigger-cleanup-all-mcs.sh --trigger --mc hs-mc-aaa --mc hs-mc-bbb
#
#   # Trigger on all MCs, more wait and log lines
#   ./trigger-cleanup-all-mcs.sh --trigger --lines 100 --wait 60
#
#   # Check which MCs have the CronJob deployed
#   ./trigger-cleanup-all-mcs.sh --check
#   ./trigger-cleanup-all-mcs.sh --check --mc hs-mc-aaa
#
#   # Check job status across all MCs
#   ./trigger-cleanup-all-mcs.sh --status
#   ./trigger-cleanup-all-mcs.sh --status --mc hs-mc-aaa
#
#   # Show last 50 lines of each job's logs
#   ./trigger-cleanup-all-mcs.sh --tail
#   ./trigger-cleanup-all-mcs.sh --tail --lines 100 --mc hs-mc-aaa
#
#   # Dry run (no jobs created)
#   ./trigger-cleanup-all-mcs.sh --trigger --dry-run
#

set -o pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MANUAL_MC_LIST=""
LOG_LINES=50
WAIT_SECS=30
DRY_RUN=false
MODE="trigger"

while [[ $# -gt 0 ]]; do
    case $1 in
        --mc)
            if [ -n "$MANUAL_MC_LIST" ]; then
                MANUAL_MC_LIST="${MANUAL_MC_LIST}"$'\n'"$2"
            else
                MANUAL_MC_LIST="$2"
            fi
            shift 2
            ;;
        --lines)
            LOG_LINES="$2"
            shift 2
            ;;
        --wait)
            WAIT_SECS="$2"
            shift 2
            ;;
        --check)
            MODE="check"
            shift
            ;;
        --trigger)
            MODE="trigger"
            shift
            ;;
        --status)
            MODE="status"
            shift
            ;;
        --tail)
            MODE="tail"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            head -50 "$0" | tail -47
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown argument: $1${NC}"
            exit 1
            ;;
    esac
done

if ! ocm whoami &>/dev/null; then
    echo -e "${RED}ERROR: Not logged into OCM. Run: ocm login --token=...${NC}"
    exit 1
fi

MC_API_JSON=$(ocm get /api/osd_fleet_mgmt/v1/management_clusters 2>/dev/null || echo '{"items":[]}')

declare -A MC_REGIONS
declare -A MC_SECTORS
while IFS=$'\t' read -r _mc_name _mc_region _mc_sector; do
    [ -z "$_mc_name" ] && continue
    MC_REGIONS["$_mc_name"]="$_mc_region"
    MC_SECTORS["$_mc_name"]="$_mc_sector"
done < <(echo "$MC_API_JSON" | jq -r '.items[] | [.name, (.region // "-"), (.sector // "-")] | @tsv')

if [ -n "$MANUAL_MC_LIST" ]; then
    MC_LIST="$MANUAL_MC_LIST"
    MC_COUNT=$(echo "$MC_LIST" | wc -l | tr -d ' ')
else
    MC_LIST=$(echo "$MC_API_JSON" | jq -r '.items[] | select(.status=="ready" or .status=="maintenance") | .name')
    if [ -z "$MC_LIST" ]; then
        echo -e "${RED}ERROR: Could not fetch MC list from OCM${NC}"
        exit 1
    fi
    MC_COUNT=$(echo "$MC_LIST" | wc -l | tr -d ' ')
fi

mc_region() { echo "${MC_REGIONS[$1]:--}"; }
mc_sector() { echo "${MC_SECTORS[$1]:--}"; }

format_duration() {
    local s=$1
    if [ "$s" -ge 3600 ]; then
        echo "$((s/3600))h $((s%3600/60))m $((s%60))s"
    elif [ "$s" -ge 60 ]; then
        echo "$((s/60))m $((s%60))s"
    else
        echo "${s}s"
    fi
}

# ============================================
# MODE: check
# ============================================
mode_check() {
    START_TIME=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
    echo "=============================================="
    echo "  CronJob check: oadp-vsc-cleanup"
    echo "  Started: $START_TIME"
    echo "  MCs: $MC_COUNT"
    echo "=============================================="
    echo ""

    FMT="%-22s %-16s %-16s %-12s %-12s %-16s\n"
    printf "$FMT" "MC_NAME" "REGION" "SECTOR" "CRONJOB" "SUSPENDED" "SCHEDULE"
    printf "$FMT" "----------------------" "----------------" "----------------" "------------" "------------" "----------------"

    FOUND=0
    NOT_FOUND=0
    LOGIN_FAIL=0

    while read -r MC_NAME; do
        [ -z "$MC_NAME" ] && continue
        REGION=$(mc_region "$MC_NAME")
        SECTOR=$(mc_sector "$MC_NAME")

        if ! ocm backplane login "$MC_NAME" &>/dev/null; then
            printf "%-22s %-16s %-16s ${RED}%-12s${NC} %-12s %-16s\n" "$MC_NAME" "$REGION" "$SECTOR" "login_fail" "-" "-"
            LOGIN_FAIL=$((LOGIN_FAIL + 1))
            continue
        fi

        CJ_JSON=$(oc get cronjob oadp-vsc-cleanup -n openshift-adp -o json 2>/dev/null) || true

        if [ -z "$CJ_JSON" ] || [ "$CJ_JSON" = "" ]; then
            printf "%-22s %-16s %-16s ${RED}%-12s${NC} %-12s %-16s\n" "$MC_NAME" "$REGION" "$SECTOR" "Not found" "-" "-"
            NOT_FOUND=$((NOT_FOUND + 1))
        else
            SUSPENDED=$(echo "$CJ_JSON" | jq -r '.spec.suspend // false')
            SCHEDULE=$(echo "$CJ_JSON" | jq -r '.spec.schedule // "-"')
            if [ "$SUSPENDED" = "true" ]; then
                printf "%-22s %-16s %-16s ${GREEN}%-12s${NC} ${YELLOW}%-12s${NC} %-16s\n" "$MC_NAME" "$REGION" "$SECTOR" "Found" "true" "$SCHEDULE"
            else
                printf "%-22s %-16s %-16s ${GREEN}%-12s${NC} ${GREEN}%-12s${NC} %-16s\n" "$MC_NAME" "$REGION" "$SECTOR" "Found" "false" "$SCHEDULE"
            fi
            FOUND=$((FOUND + 1))
        fi
    done <<< "$MC_LIST"

    printf "$FMT" "----------------------" "----------------" "----------------" "------------" "------------" "----------------"
    echo ""
    echo "  Found: $FOUND  |  Not found: $NOT_FOUND  |  Login fail: $LOGIN_FAIL  |  Total: $MC_COUNT"
    echo ""
}

# ============================================
# MODE: status
# ============================================
mode_status() {
    START_TIME=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
    echo "=============================================="
    echo "  Job status check: manual-cleanup-* jobs"
    echo "  Started: $START_TIME"
    echo "  MCs: $MC_COUNT"
    echo "=============================================="
    echo ""

    FMT="%-22s %-16s %-16s %-32s %-12s %-10s %-22s %-22s\n"
    printf "$FMT" "MC_NAME" "REGION" "SECTOR" "JOB_NAME" "STATUS" "DURATION" "CREATED" "COMPLETED"
    printf "$FMT" "----------------------" "----------------" "----------------" "--------------------------------" "------------" "----------" "----------------------" "----------------------"

    MC_INDEX=0
    while read -r MC_NAME; do
        [ -z "$MC_NAME" ] && continue
        MC_INDEX=$((MC_INDEX + 1))
        REGION=$(mc_region "$MC_NAME")
        SECTOR=$(mc_sector "$MC_NAME")

        if ! ocm backplane login "$MC_NAME" &>/dev/null; then
            printf "$FMT" "$MC_NAME" "$REGION" "$SECTOR" "-" "login_fail" "-" "-" "-"
            continue
        fi

        JOBS_JSON=$(oc get jobs -n openshift-adp -o json 2>/dev/null || echo '{"items":[]}')
        MANUAL_JOBS=$(echo "$JOBS_JSON" | jq -r '.items[] | select(.metadata.name | startswith("manual-cleanup-")) | .metadata.name' 2>/dev/null)

        if [ -z "$MANUAL_JOBS" ]; then
            printf "$FMT" "$MC_NAME" "$REGION" "$SECTOR" "(none)" "-" "-" "-" "-"
            continue
        fi

        FIRST=true
        while read -r JOB_NAME; do
            [ -z "$JOB_NAME" ] && continue

            JOB_DATA=$(echo "$JOBS_JSON" | jq --arg n "$JOB_NAME" '.items[] | select(.metadata.name == $n)' 2>/dev/null)

            SUCCEEDED=$(echo "$JOB_DATA" | jq -r '.status.succeeded // 0')
            FAILED_COUNT=$(echo "$JOB_DATA" | jq -r '.status.failed // 0')
            ACTIVE=$(echo "$JOB_DATA" | jq -r '.status.active // 0')
            CREATED=$(echo "$JOB_DATA" | jq -r '.metadata.creationTimestamp // "-"' | sed 's/T/ /;s/Z//')
            COMPLETED=$(echo "$JOB_DATA" | jq -r '.status.completionTime // "-"' | sed 's/T/ /;s/Z//')

            if [ "$ACTIVE" -gt 0 ]; then
                JOB_STATUS_PLAIN="Running"
                JOB_STATUS_COLOR="${YELLOW}"
            elif [ "$SUCCEEDED" -gt 0 ]; then
                JOB_STATUS_PLAIN="Complete"
                JOB_STATUS_COLOR="${GREEN}"
            elif [ "$FAILED_COUNT" -gt 0 ]; then
                JOB_STATUS_PLAIN="Failed"
                JOB_STATUS_COLOR="${RED}"
            else
                JOB_STATUS_PLAIN="Pending"
                JOB_STATUS_COLOR=""
            fi

            DURATION="-"
            START_TS=$(echo "$JOB_DATA" | jq -r '.status.startTime // ""')
            if [ -n "$START_TS" ] && [ "$START_TS" != "null" ]; then
                START_EPOCH=$(date -d "$START_TS" +%s 2>/dev/null || true)
                if [ -n "$START_EPOCH" ]; then
                    if [ "$COMPLETED" != "-" ]; then
                        END_EPOCH=$(date -d "$(echo "$JOB_DATA" | jq -r '.status.completionTime')" +%s 2>/dev/null || true)
                        [ -n "$END_EPOCH" ] && DURATION=$(format_duration $((END_EPOCH - START_EPOCH)))
                    elif [ "$ACTIVE" -gt 0 ]; then
                        NOW_EPOCH=$(date +%s)
                        DURATION="$(format_duration $((NOW_EPOCH - START_EPOCH)))"
                    fi
                fi
            fi

            MC_LABEL="$MC_NAME"
            REGION_LABEL="$REGION"
            SECTOR_LABEL="$SECTOR"
            if [ "$FIRST" != true ]; then
                MC_LABEL=""
                REGION_LABEL=""
                SECTOR_LABEL=""
            fi
            FIRST=false

            printf "%-22s %-16s %-16s %-32s ${JOB_STATUS_COLOR}%-12s${NC} %-10s %-22s %-22s\n" "$MC_LABEL" "$REGION_LABEL" "$SECTOR_LABEL" "$JOB_NAME" "$JOB_STATUS_PLAIN" "$DURATION" "$CREATED" "$COMPLETED"
        done <<< "$MANUAL_JOBS"
    done <<< "$MC_LIST"

    printf "$FMT" "----------------------" "----------------" "----------------" "--------------------------------" "------------" "----------" "----------------------" "----------------------"
    echo ""
}

# ============================================
# MODE: tail
# ============================================
mode_tail() {
    START_TIME=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
    echo "=============================================="
    echo "  Tail logs: manual-cleanup-* jobs"
    echo "  Started: $START_TIME"
    echo "  MCs: $MC_COUNT  |  Lines: $LOG_LINES (last)"
    echo "=============================================="
    echo ""

    MC_INDEX=0
    while read -r MC_NAME; do
        [ -z "$MC_NAME" ] && continue
        MC_INDEX=$((MC_INDEX + 1))
        REGION=$(mc_region "$MC_NAME")
        SECTOR=$(mc_sector "$MC_NAME")

        echo "----------------------------------------------"
        echo -e "  ${CYAN}[$MC_INDEX/$MC_COUNT] $MC_NAME  ($REGION / $SECTOR)${NC}"
        echo "----------------------------------------------"

        if ! ocm backplane login "$MC_NAME" &>/dev/null; then
            echo -e "  ${RED}FAIL: backplane login failed${NC}"
            echo ""
            continue
        fi

        MANUAL_JOBS=$(oc get jobs -n openshift-adp -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep '^manual-cleanup-' || true)

        if [ -z "$MANUAL_JOBS" ]; then
            echo -e "  ${YELLOW}No manual-cleanup-* jobs found${NC}"
            echo ""
            continue
        fi

        while read -r JOB_NAME; do
            [ -z "$JOB_NAME" ] && continue
            echo ""
            echo -e "  ${GREEN}--- $JOB_NAME (last $LOG_LINES lines) ---${NC}"
            oc logs "job.batch/$JOB_NAME" -n openshift-adp 2>/dev/null | tail -n "$LOG_LINES" || echo -e "  ${YELLOW}(no logs available)${NC}"
            echo -e "  ${GREEN}--- end $JOB_NAME ---${NC}"
        done <<< "$MANUAL_JOBS"
        echo ""
    done <<< "$MC_LIST"
}

# ============================================
# MODE: trigger (default)
# ============================================
mode_trigger() {
    START_TIME=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
    echo "=============================================="
    echo "  Trigger oadp-vsc-cleanup on MCs"
    echo "  Started: $START_TIME"
    echo "  MCs: $MC_COUNT  |  Dry-run: $DRY_RUN"
    echo "  Log lines: $LOG_LINES  |  Wait: ${WAIT_SECS}s"
    echo "=============================================="
    echo ""
    echo "MC list (this run):"
    echo "$MC_LIST" | while read -r m; do
        [ -n "$m" ] && echo "  - $m  ($(mc_region "$m") / $(mc_sector "$m"))"
    done
    echo ""

    MC_INDEX=0
    SUCCEEDED=0
    FAILED=0

    while read -r MC_NAME; do
        [ -z "$MC_NAME" ] && continue
        MC_INDEX=$((MC_INDEX + 1))
        REGION=$(mc_region "$MC_NAME")
        SECTOR=$(mc_sector "$MC_NAME")

        echo "----------------------------------------------"
        echo -e "  ${CYAN}[$MC_INDEX/$MC_COUNT] $MC_NAME  ($REGION / $SECTOR)${NC}"
        echo "----------------------------------------------"

        if ! ocm backplane login "$MC_NAME" &>/dev/null; then
            echo -e "  ${RED}FAIL: backplane login failed${NC}"
            FAILED=$((FAILED + 1))
            echo ""
            continue
        fi

        if ! oc get cronjob oadp-vsc-cleanup -n openshift-adp &>/dev/null; then
            echo -e "  ${YELLOW}SKIP: CronJob oadp-vsc-cleanup not found in openshift-adp${NC}"
            FAILED=$((FAILED + 1))
            echo ""
            continue
        fi

        JOB_NAME="manual-cleanup-$(date +%s)"

        if [ "$DRY_RUN" = true ]; then
            echo -e "  ${YELLOW}DRY-RUN: would create job $JOB_NAME${NC}"
            echo ""
            continue
        fi

        echo "  Creating job: $JOB_NAME"
        if ! ocm backplane elevate SLSRE-531 -- create job --from=cronjob/oadp-vsc-cleanup "$JOB_NAME" -n openshift-adp 2>&1; then
            echo -e "  ${RED}FAIL: job creation failed${NC}"
            FAILED=$((FAILED + 1))
            echo ""
            continue
        fi

        echo "  Waiting ${WAIT_SECS}s for pod to start..."
        sleep "$WAIT_SECS"

        echo ""
        echo "  --- First $LOG_LINES lines of logs ---"
        oc logs "job.batch/$JOB_NAME" -n openshift-adp 2>/dev/null | head -n "$LOG_LINES" || echo -e "  ${YELLOW}(no logs yet)${NC}"
        echo "  --- end of initial logs ---"
        echo ""

        SUCCEEDED=$((SUCCEEDED + 1))
        echo -e "  ${GREEN}OK: job $JOB_NAME created on $MC_NAME${NC}"
        echo ""

    done <<< "$MC_LIST"

    END_TIME=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
    echo "=============================================="
    echo "  Finished: $END_TIME"
    echo "  Succeeded: $SUCCEEDED  |  Failed: $FAILED  |  Total: $MC_COUNT"
    echo "=============================================="
}

# --- Dispatch ---
case "$MODE" in
    check)   mode_check ;;
    status)  mode_status ;;
    tail)    mode_tail ;;
    trigger) mode_trigger ;;
esac
