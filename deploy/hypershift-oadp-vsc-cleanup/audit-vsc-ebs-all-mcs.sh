#!/usr/bin/env bash
#
# Quick OADP VSC + EBS audit across all Management Clusters (READ-ONLY).
#
# Uses the same K8s logic as the cleanup CronJob: counts VSC, Velero VSC,
# Retain VSC, VS. Then gets AWS EBS snapshot count for the MC's account/region.
# Output is one short table per MC so you can run before/after cleanup and
# compare (e.g. pre-cleanup Retain + EBS count vs post-cleanup).
#
# PREREQUISITES (run BEFORE this script):
#   1. ocm login --token=...
#   2. kinit $USER@IPA.REDHAT.COM
#   3. rh-aws-saml-login osd-staging-1   (stage) or rh-aws-saml-login rh-control (prod)
#
# EBS count: For a single MC, use the same flow as oadp-vsc-cleanup.sh so EBS is non-zero:
#   export $(osdctl -S account cli -i $AWS_ACCOUNT_ID -o env)
#   ./audit-vsc-ebs-all-mcs.sh --mc <that_mc>
#   (Script uses current shell AWS when caller identity matches the MC's account.)
#   For multiple MCs, script uses osdctl per MC in a subshell (may show 0 in integration).
#
# Usage:
#   ./audit-vsc-ebs-all-mcs.sh [OPTIONS]
#
# Options:
#   --mc <name>    Audit only this MC (can be repeated). Skips discovery.
#   --skip-aws     Skip AWS snapshot count (faster; only K8s counts).
#   -o <file>      Write TSV to file (for before/after diff).
#   -h, --help     Show help.
#
# Examples:
#   # All MCs (stage)
#   rh-aws-saml-login osd-staging-1
#   ./audit-vsc-ebs-all-mcs.sh
#
#   # Single MC (with EBS count: set MC's AWS creds first, like oadp-vsc-cleanup.sh)
#   AWS_ACCOUNT_ID=$(ocm get cluster $(ocm describe cluster hs-mc-xxx --json | jq -r .id) | jq -r '.aws.sts.role_arn' | sed -n 's/.*\([0-9]\{12\}\).*/\1/p')
#   export $(osdctl -S account cli -i $AWS_ACCOUNT_ID -o env)
#   ./audit-vsc-ebs-all-mcs.sh --mc hs-mc-xxx
#
#   # Multiple MCs (no discovery; useful when AWS creds are time-limited)
#   ./audit-vsc-ebs-all-mcs.sh --mc hs-mc-aaa --mc hs-mc-bbb --mc hs-mc-ccc
#
#   # Skip AWS (K8s counts only; faster, no osdctl/aws needed)
#   ./audit-vsc-ebs-all-mcs.sh --skip-aws
#   ./audit-vsc-ebs-all-mcs.sh --skip-aws --mc hs-mc-aaa --mc hs-mc-bbb
#
#   # Before cleanup → run cleanup → after cleanup; then diff the two TSVs
#   ./audit-vsc-ebs-all-mcs.sh -o audit_before.tsv
#   # ... run cleanup (CronJob or manual) ...
#   ./audit-vsc-ebs-all-mcs.sh -o audit_after.tsv
#   diff audit_before.tsv audit_after.tsv
#

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MANUAL_MC_LIST=""
SKIP_AWS=false
OUTPUT_TSV=""

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
        --skip-aws)
            SKIP_AWS=true
            shift
            ;;
        -o)
            OUTPUT_TSV="$2"
            shift 2
            ;;
        -h|--help)
            head -45 "$0" | tail -42
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown argument: $1${NC}"
            exit 1
            ;;
    esac
done

# --- Prereqs ---
if ! ocm whoami &>/dev/null; then
    echo -e "${RED}ERROR: Not logged into OCM. Run: ocm login --token=...${NC}"
    exit 1
fi

if [ "$SKIP_AWS" = false ] && ! aws sts get-caller-identity &>/dev/null; then
    echo -e "${RED}ERROR: AWS credentials not set. Run: kinit + rh-aws-saml-login ...${NC}"
    echo "Or use --skip-aws to skip EBS count."
    exit 1
fi

# Current shell's AWS account (for single-MC flow: user runs export $(osdctl ...) first, like oadp-vsc-cleanup.sh)
CURRENT_AWS_ACCOUNT=""
if [ "$SKIP_AWS" = false ]; then
    CURRENT_AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
fi

# --- Discover MCs ---
if [ -n "$MANUAL_MC_LIST" ]; then
    MC_LIST="$MANUAL_MC_LIST"
    MC_COUNT=$(echo "$MC_LIST" | wc -l | tr -d ' ')
else
    MC_LIST=$(ocm get /api/osd_fleet_mgmt/v1/management_clusters 2>/dev/null | \
        jq -r '.items[] | select(.status=="ready" or .status=="maintenance") | .name')
    if [ -z "$MC_LIST" ]; then
        echo -e "${RED}ERROR: Could not fetch MC list from OCM${NC}"
        exit 1
    fi
    MC_COUNT=$(echo "$MC_LIST" | wc -l | tr -d ' ')
fi

START_TIME=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
START_EPOCH=$(date +%s)

echo "=============================================="
echo "  Quick VSC + EBS audit (read-only)"
echo "  Started: $START_TIME"
echo "  MCs: $MC_COUNT  |  Skip AWS: $SKIP_AWS"
echo "=============================================="
echo ""
echo "MC list (this run):"
echo "$MC_LIST" | while read -r m; do [ -n "$m" ] && echo "  - $m"; done
echo ""

# Helper: format seconds as "Xs" or "Xm Ys"
format_elapsed() {
    local s=$1
    if [ "$s" -ge 60 ]; then
        echo "$((s/60))m $((s%60))s"
    else
        echo "${s}s"
    fi
}

# Header: TOTAL_VSC, then Velero pair (VELERO_VSC, VELERO_VS), then Retain pair (RETAIN, RETAIN_VS), then EBS/TIME/STATUS
HEADER="MC_NAME\tTOTAL_VSC\tVELERO_VSC\tVELERO_VS\tRETAIN_VSC\tRETAIN_VS\tEBS_SNAPSHOTS\tTIME\tSTATUS"
# Column widths: 22, 9, 10, 10, 8, 9, 12, 8, 10
FMT="%-22s %9s %10s %10s %8s %9s %12s %8s %-10s\n"
printf "$FMT" "MC_NAME" "TOTAL_VSC" "VELERO_VSC" "VELERO_VS" "RETAIN" "RETAIN_VS" "EBS_SNAPS" "TIME" "STATUS"
printf "$FMT" "----------------------" "---------" "----------" "----------" "--------" "---------" "------------" "--------" "----------"

[ -n "$OUTPUT_TSV" ] && echo -e "$HEADER" > "$OUTPUT_TSV"

MC_INDEX=0
while read -r MC_NAME; do
    [ -z "$MC_NAME" ] && continue
    MC_INDEX=$((MC_INDEX + 1))
    MC_START=$(date +%s)

    TOTAL_VSC=0
    VELERO_VSC=0
    VELERO_VS=0
    RETAIN_VSC=0
    RETAIN_VS=0
    EBS_SNAPS=0
    STATUS="ok"

    # Cluster info (region + account)
    CLUSTER_INFO=$(ocm describe cluster "$MC_NAME" --json 2>/dev/null)
    if [ -z "$CLUSTER_INFO" ] || [ "$CLUSTER_INFO" = "null" ]; then
        STATUS="no_ocm"
        MC_ELAPSED=$(format_elapsed $(($(date +%s) - MC_START)))
        printf "$FMT" "$MC_NAME" "-" "-" "-" "-" "-" "-" "$MC_ELAPSED" "${RED}${STATUS}${NC}"
        [ -n "$OUTPUT_TSV" ] && echo -e "${MC_NAME}\t-\t-\t-\t-\t-\t-\t${MC_ELAPSED}\t${STATUS}" >> "$OUTPUT_TSV"
        continue
    fi

    AWS_REGION=$(echo "$CLUSTER_INFO" | jq -r '.region.id')
    CLUSTER_ID=$(echo "$CLUSTER_INFO" | jq -r '.id')
    AWS_ACCOUNT=$(ocm get cluster "$CLUSTER_ID" 2>/dev/null | jq -r '.aws.sts.role_arn' | sed -n 's/.*\([0-9]\{12\}\).*/\1/p')
    [ -z "$AWS_ACCOUNT" ] && AWS_ACCOUNT="unknown"

    # Login to MC
    if ! ocm backplane login "$MC_NAME" &>/dev/null; then
        STATUS="login_fail"
        MC_ELAPSED=$(format_elapsed $(($(date +%s) - MC_START)))
        printf "$FMT" "$MC_NAME" "-" "-" "-" "-" "-" "-" "$MC_ELAPSED" "${RED}${STATUS}${NC}"
        [ -n "$OUTPUT_TSV" ] && echo -e "${MC_NAME}\t-\t-\t-\t-\t-\t-\t${MC_ELAPSED}\t${STATUS}" >> "$OUTPUT_TSV"
        continue
    fi

    # K8s counts (same logic as cron)
    TOTAL_VSC=$(oc get volumesnapshotcontents --no-headers 2>/dev/null | wc -l | tr -d ' \n\r')
    VELERO_VSC=$(oc get volumesnapshotcontents -l velero.io/backup-name --no-headers 2>/dev/null | wc -l | tr -d ' \n\r')
    VSC_JSON=$(oc get volumesnapshotcontents -l velero.io/backup-name -o json 2>/dev/null || echo '{"items":[]}')
    RETAIN_VSC=$(echo "$VSC_JSON" | jq -r '[.items[] | select(.spec.deletionPolicy == "Retain")] | length' 2>/dev/null | tr -d '\n\r' || echo "0")
    ALL_VS=$(oc get volumesnapshots -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
    ALL_VS_SORTED=$(echo "$ALL_VS" | grep -v '^$' | sort -u)
    # VELERO_VS = count of refs (from Velero VSCs) that exist in cluster; use set intersection (no per-ref oc/grep)
    VELERO_REFS=$(echo "$VSC_JSON" | jq -r '.items[] | "\(.spec.volumeSnapshotRef.namespace // "none")/\(.spec.volumeSnapshotRef.name // "none")"' 2>/dev/null | sort -u | grep -v '^none/none$' | grep -v '^none/' | grep -v '/none$')
    VELERO_VS=0
    [ -n "$VELERO_REFS" ] && [ -n "$ALL_VS_SORTED" ] && VELERO_VS=$(comm -12 <(echo "$VELERO_REFS") <(echo "$ALL_VS_SORTED") 2>/dev/null | wc -l | tr -d ' \n\r')
    # RETAIN_VS = count of refs (from Retain VSCs) that exist in cluster
    RETAIN_REFS=$(echo "$VSC_JSON" | jq -r '.items[] | select(.spec.deletionPolicy == "Retain") | "\(.spec.volumeSnapshotRef.namespace // "none")/\(.spec.volumeSnapshotRef.name // "none")"' 2>/dev/null | sort -u | grep -v '^none/none$' | grep -v '^none/' | grep -v '/none$')
    RETAIN_VS=0
    [ -n "$RETAIN_REFS" ] && [ -n "$ALL_VS_SORTED" ] && RETAIN_VS=$(comm -12 <(echo "$RETAIN_REFS") <(echo "$ALL_VS_SORTED") 2>/dev/null | wc -l | tr -d ' \n\r')

    # AWS EBS snapshot count (subshell logic matches oadp-vsc-audit.sh; prefer current shell when account matches)
    if [ "$SKIP_AWS" = false ] && [ -n "$AWS_ACCOUNT" ] && [ "$AWS_ACCOUNT" != "unknown" ]; then
        EBS_TMP=$(mktemp)
        if [ "$AWS_ACCOUNT" = "$CURRENT_AWS_ACCOUNT" ]; then
            # User already ran: export $(osdctl -S account cli -i $AWS_ACCOUNT -o env) — use current env (no subshell)
            EBS_JSON=$(mktemp)
            aws ec2 describe-snapshots --owner-ids self --region "$AWS_REGION" \
                --query 'Snapshots[].{ID:SnapshotId,Size:FullSnapshotSizeInBytes}' \
                --output json --page-size 500 2>/dev/null > "$EBS_JSON" && \
                jq 'length' "$EBS_JSON" 2>/dev/null > "$EBS_TMP" || echo "0" > "$EBS_TMP"
            rm -f "$EBS_JSON"
        else
            # Per-MC creds via subshell (same pattern as oadp-vsc-audit.sh: LOCAL_* vars, verify creds, then describe-snapshots to file)
            LOCAL_AWS_REGION="$AWS_REGION"
            LOCAL_AWS_ACCOUNT="$AWS_ACCOUNT"
            LOCAL_EBS_TMP="$EBS_TMP"
            (
                AWS_CREDS_OUTPUT=$(osdctl -S account cli -i "$LOCAL_AWS_ACCOUNT" -o env 2>&1)
                if echo "$AWS_CREDS_OUTPUT" | grep -qi "error"; then
                    echo "0" > "$LOCAL_EBS_TMP"
                    exit 0
                fi
                eval "export $AWS_CREDS_OUTPUT"
                if ! aws sts get-caller-identity --region "$LOCAL_AWS_REGION" --query 'Account' --output text &>/dev/null; then
                    echo "0" > "$LOCAL_EBS_TMP"
                    exit 0
                fi
                SNAP_JSON=$(mktemp)
                if aws ec2 describe-snapshots --owner-ids self --region "$LOCAL_AWS_REGION" \
                    --query 'Snapshots[].{ID:SnapshotId,Size:FullSnapshotSizeInBytes}' \
                    --output json --page-size 500 2>/dev/null > "$SNAP_JSON"; then
                    jq 'length' "$SNAP_JSON" 2>/dev/null > "$LOCAL_EBS_TMP" || echo "0" > "$LOCAL_EBS_TMP"
                else
                    echo "0" > "$LOCAL_EBS_TMP"
                fi
                rm -f "$SNAP_JSON"
            )
        fi
        EBS_SNAPS=$(cat "$EBS_TMP" 2>/dev/null | tr -d ' \n\r' || echo "0")
        rm -f "$EBS_TMP"
    fi

    MC_ELAPSED=$(format_elapsed $(($(date +%s) - MC_START)))
    # Normalize: force numeric so we never get "00" or broken rows
    TOTAL_VSC=$((TOTAL_VSC + 0))
    VELERO_VSC=$((VELERO_VSC + 0))
    VELERO_VS=$((VELERO_VS + 0))
    RETAIN_VSC=$((RETAIN_VSC + 0))
    RETAIN_VS=$((RETAIN_VS + 0))
    EBS_SNAPS=$((EBS_SNAPS + 0))
    MC_ELAPSED=$(echo "$MC_ELAPSED" | tr -d '\n\r')
    STATUS=$(echo "$STATUS" | tr -d '\n\r')
    printf "$FMT" "$MC_NAME" "$TOTAL_VSC" "$VELERO_VSC" "$VELERO_VS" "$RETAIN_VSC" "$RETAIN_VS" "$EBS_SNAPS" "$MC_ELAPSED" "$STATUS"
    [ -n "$OUTPUT_TSV" ] && echo -e "${MC_NAME}\t${TOTAL_VSC}\t${VELERO_VSC}\t${VELERO_VS}\t${RETAIN_VSC}\t${RETAIN_VS}\t${EBS_SNAPS}\t${MC_ELAPSED}\t${STATUS}" >> "$OUTPUT_TSV"
done <<< "$MC_LIST"

printf "$FMT" "----------------------" "---------" "----------" "----------" "--------" "---------" "------------" "--------" "----------"
echo ""
echo "VELERO_VSC/VELERO_VS = Velero VSCs and their referenced VS (existing). RETAIN/RETAIN_VS = Retain VSCs and their VS (cascade delete)."
echo "TIME: duration per MC. STATUS: ok = audit succeeded; no_ocm = cluster not in OCM; login_fail = backplane login failed."
echo ""

END_TIME=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
END_EPOCH=$(date +%s)
DURATION=$((END_EPOCH - START_EPOCH))
DURATION_M=$((DURATION / 60))
DURATION_S=$((DURATION % 60))
echo "=============================================="
echo "  Finished: $END_TIME  (duration: ${DURATION_M}m ${DURATION_S}s)"
echo "=============================================="
echo ""

if [ -n "$OUTPUT_TSV" ]; then
    echo -e "${GREEN}TSV written to: $OUTPUT_TSV${NC}"
    echo "  Use for before/after comparison: run once before cleanup, once after, then diff the files."
fi
