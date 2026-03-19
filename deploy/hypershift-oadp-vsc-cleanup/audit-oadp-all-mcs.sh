#!/usr/bin/env bash
#
# Unified OADP audit across Management Clusters (READ-ONLY).
#
# Single entry point for auditing all OADP-related resources. Select a case:
#   --case hourly  (default)  Hourly-full-backup resources + VSC EBS status
#   --case retain             Retain VSC cleanup analysis (CronJob Part A)
#   --case all                Combined overview (both cases in one pass)
#
# Options:
#   --case <hourly|retain|all>  Audit case (default: hourly)
#   --mc <name>       Audit only this MC (repeatable). Skips OCM discovery.
#   --check-aws       Enable AWS EBS snapshot counting (needs creds, slower).
#   --detail          Per-VSC detail table (hourly/all cases only).
#   -n <namespace>    Namespace for DBR/Backup (default: openshift-adp).
#   -o <file>         Write TSV summary to file (for before/after diff).
#   -h, --help        Show this help.
#
# Cases explained:
#   hourly — Matches CronJob Part B deletion targets:
#     HOURLY_DBR (B1), HOURLY_BKP (B2), HOURLY_VS (B3b/B3c/B4b), HOURLY_VSC (B3a/B3b/B4)
#     Plus VSC EBS status (READY/EBS_GONE/NO_HDL/NOT_READY) and stuck DBR detection.
#     With --check-aws: adds EBS_SNAPS (total AWS EBS snapshots per MC).
#
#   retain — Matches CronJob Part A:
#     TOTAL_VSC, VELERO_VSC, VELERO_VS, RETAIN_VSC, RETAIN_VS
#     With --check-aws: adds EBS_SNAPS (total AWS EBS snapshots per MC).
#
#   all — Both cases in one pass, combined table with key columns from each.
#     With --check-aws: adds EBS_SNAPS column.
#
# PREREQUISITES:
#   1. OCM login:
#      ocm login --token=... --url=integration   # integration
#      ocm login --token=... --url=staging        # stage
#      ocm login --token=... --url=production     # production
#
#   2. For --check-aws (Kerberos + SAML):
#      kinit $USER@IPA.REDHAT.COM
#
#      # Integration:
#      rh-aws-saml-login osd-staging-1
#
#      # Stage:
#      rh-aws-saml-login osd-staging-1
#
#      # Production:
#      rh-aws-saml-login rh-control
#
#      # Or per-MC (single MC flow — sets creds for a specific MC's AWS account):
#      AWS_ACCOUNT_ID=$(ocm get cluster $(ocm describe cluster hs-mc-xxx --json | jq -r .id) \
#          | jq -r '.aws.sts.role_arn' | sed -n 's/.*\([0-9]\{12\}\).*/\1/p')
#      export $(osdctl -S account cli -i $AWS_ACCOUNT_ID -o env)
#      ./audit-oadp-all-mcs.sh --check-aws --mc hs-mc-xxx
#
# Examples:
#   # Hourly audit (default), all MCs:
#   ./audit-oadp-all-mcs.sh
#
#   # Retain audit with AWS EBS count:
#   ./audit-oadp-all-mcs.sh --case retain --check-aws
#
#   # Combined overview, single MC:
#   ./audit-oadp-all-mcs.sh --case all --mc hs-mc-xxx
#
#   # Hourly with per-VSC detail + AWS cross-check:
#   ./audit-oadp-all-mcs.sh --case hourly --detail --check-aws --mc hs-mc-xxx
#
#   # Before/after diff:
#   ./audit-oadp-all-mcs.sh -o before.tsv
#   # ... run cronjob / cleanup ...
#   ./audit-oadp-all-mcs.sh -o after.tsv
#   diff before.tsv after.tsv
#

set -euo pipefail

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
NC=$'\033[0m'

# --- Defaults ---
CASE="hourly"
NAMESPACE="openshift-adp"
MANUAL_MC_LIST=""
CHECK_AWS=false
SHOW_DETAIL=false
OUTPUT_TSV=""
STUCK_DBR_THRESHOLD_SEC=7200

# --- Arg parsing ---
while [[ $# -gt 0 ]]; do
    case $1 in
        --case)
            CASE="$2"
            shift 2
            ;;
        --mc)
            if [ -n "$MANUAL_MC_LIST" ]; then
                MANUAL_MC_LIST="${MANUAL_MC_LIST}"$'\n'"$2"
            else
                MANUAL_MC_LIST="$2"
            fi
            shift 2
            ;;
        --check-aws)
            CHECK_AWS=true
            shift
            ;;
        --skip-aws)
            CHECK_AWS=false
            shift
            ;;
        --detail)
            SHOW_DETAIL=true
            shift
            ;;
        -n)
            NAMESPACE="$2"
            shift 2
            ;;
        -o)
            OUTPUT_TSV="$2"
            shift 2
            ;;
        -h|--help)
            head -74 "$0" | tail -71
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown argument: $1${NC}"
            exit 1
            ;;
    esac
done

if [[ "$CASE" != "hourly" && "$CASE" != "retain" && "$CASE" != "all" ]]; then
    echo -e "${RED}ERROR: Invalid --case '$CASE'. Use: hourly, retain, all${NC}"
    exit 1
fi

# --- Temp dir ---
TMPDIR="/tmp/audit-oadp-$$"
mkdir -p "$TMPDIR"
cleanup() { [ -n "$TMPDIR" ] && [ -d "$TMPDIR" ] && rm -rf "$TMPDIR"; }
trap cleanup EXIT

format_elapsed() {
    local s=$1
    if [ "$s" -ge 60 ]; then echo "$((s/60))m $((s%60))s"
    else echo "${s}s"; fi
}

# --- Prereqs: OCM ---
ocm whoami > "${TMPDIR}/ocm" 2>/dev/null || true
if ! [ -s "${TMPDIR}/ocm" ]; then
    echo -e "${RED}ERROR: Not logged into OCM. Run: ocm login --token=...${NC}"
    exit 1
fi

# --- Prereqs: AWS (if --check-aws) ---
CURRENT_AWS_ACCOUNT=""
if [ "$CHECK_AWS" = true ]; then
    aws sts get-caller-identity > "${TMPDIR}/aws_id" 2>/dev/null || true
    if ! [ -s "${TMPDIR}/aws_id" ]; then
        echo -e "${RED}ERROR: AWS credentials not set. Run: kinit + rh-aws-saml-login ... or remove --check-aws${NC}"
        exit 1
    fi
    CURRENT_AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
fi

# --- MC metadata (region/sector) from OCM ---
ocm get /api/osd_fleet_mgmt/v1/management_clusters 2>/dev/null > "${TMPDIR}/ocm_mc.json" || true

declare -A MC_REGIONS
declare -A MC_SECTORS
if [ -s "${TMPDIR}/ocm_mc.json" ]; then
    while IFS=$'\t' read -r _mc_name _mc_region _mc_sector; do
        [ -z "$_mc_name" ] && continue
        MC_REGIONS["$_mc_name"]="$_mc_region"
        MC_SECTORS["$_mc_name"]="$_mc_sector"
    done < <(jq -r '.items[] | [.name, (.region // "-"), (.sector // "-")] | @tsv' "${TMPDIR}/ocm_mc.json")
fi

mc_region() { echo "${MC_REGIONS[$1]:--}"; }
mc_sector() { echo "${MC_SECTORS[$1]:--}"; }

# --- Build MC list ---
MC_LIST_FILE="${TMPDIR}/mc_list"
: > "$MC_LIST_FILE"

if [ -n "$MANUAL_MC_LIST" ]; then
    while read -r m; do
        [ -z "$m" ] && continue
        echo "$m" >> "$MC_LIST_FILE"
    done <<< "$MANUAL_MC_LIST"
else
    if [ -s "${TMPDIR}/ocm_mc.json" ]; then
        jq -r '.items[] | select(.status=="ready" or .status=="maintenance") | .name' "${TMPDIR}/ocm_mc.json" 2>/dev/null >> "$MC_LIST_FILE" || true
    fi
    if ! [ -s "$MC_LIST_FILE" ]; then
        echo -e "${RED}ERROR: Could not fetch MC list from OCM. Use --mc <name>.${NC}"
        exit 1
    fi
fi

MC_COUNT=0
while read -r _; do MC_COUNT=$((MC_COUNT + 1)); done < "$MC_LIST_FILE"

# =============================================================================
# Banner
# =============================================================================
START_TIME=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
echo "=============================================="
echo "  OADP Audit — case: $CASE"
echo "  Started: $START_TIME"
echo "  MCs: $MC_COUNT  |  Namespace: $NAMESPACE"
[ "$CHECK_AWS" = true ] && echo "  AWS cross-check: enabled"
[ "$SHOW_DETAIL" = true ] && echo "  Detail: enabled"
echo "=============================================="
echo ""
echo "MC list (this run):"
while read -r m; do
    [ -z "$m" ] && continue
    echo "  - $m  ($(mc_region "$m") / $(mc_sector "$m"))"
done < "$MC_LIST_FILE"
echo ""

# =============================================================================
# Table headers (case-dependent)
# =============================================================================

case "$CASE" in
    retain)
        if [ "$CHECK_AWS" = true ]; then
            FMT="%-5s %-20s %-16s %-26s %9s %10s %9s %10s %9s %11s %5s %-10s\n"
            printf "$FMT" "#/Tot" "MC_NAME" "REGION" "SECTOR" "TOTAL_VSC" "VELERO_VSC" "VELERO_VS" "RETAIN_VSC" "RETAIN_VS" "EBS_SNAPS" "TIME" "STATUS"
            printf "$FMT" "-----" "--------------------" "----------------" "--------------------------" "---------" "----------" "---------" "----------" "---------" "-----------" "-----" "----------"
            TSV_HEADER="MC_NAME\tREGION\tSECTOR\tTOTAL_VSC\tVELERO_VSC\tVELERO_VS\tRETAIN_VSC\tRETAIN_VS\tEBS_SNAPS\tTIME\tSTATUS"
        else
            FMT="%-5s %-20s %-16s %-26s %9s %10s %9s %10s %9s %5s %-10s\n"
            printf "$FMT" "#/Tot" "MC_NAME" "REGION" "SECTOR" "TOTAL_VSC" "VELERO_VSC" "VELERO_VS" "RETAIN_VSC" "RETAIN_VS" "TIME" "STATUS"
            printf "$FMT" "-----" "--------------------" "----------------" "--------------------------" "---------" "----------" "---------" "----------" "---------" "-----" "----------"
            TSV_HEADER="MC_NAME\tREGION\tSECTOR\tTOTAL_VSC\tVELERO_VSC\tVELERO_VS\tRETAIN_VSC\tRETAIN_VS\tTIME\tSTATUS"
        fi
        ;;
    hourly)
        if [ "$CHECK_AWS" = true ]; then
            FMT_H="%-5s %-20s %-16s %-26s %10s %10s %9s %10s %9s %12s %10s %13s %5s %-6s %13s %11s %9s %5s %s\n"
            printf "$FMT_H" "#/Tot" "MC_NAME" "REGION" "SECTOR" "HOURLY_DBR" "HOURLY_BKP" "HOURLY_VS" "HOURLY_VSC" "VSC_READY" "VSC_EBS_GONE" "VSC_NO_HDL" "VSC_NOT_READY" "STUCK" "STATUS" "TOTAL_VSC_DEL" "HOURLY_VSC%" "EBS_SNAPS" "TIME" "STUCK_DETAIL"
            printf "$FMT_H" "-----" "--------------------" "----------------" "--------------------------" "----------" "----------" "---------" "----------" "---------" "------------" "----------" "-------------" "-----" "------" "-------------" "-----------" "---------" "-----" "----------------------------"
            TSV_HEADER="MC_NAME\tREGION\tSECTOR\tHOURLY_DBR\tHOURLY_BKP\tHOURLY_VS\tHOURLY_VSC\tVSC_READY\tVSC_EBS_GONE\tVSC_NO_HDL\tVSC_NOT_READY\tSTUCK\tSTATUS\tTOTAL_VSC_DEL\tHOURLY_VSC_PCT\tEBS_SNAPS\tTIME\tSTUCK_DETAIL"
        else
            FMT_H="%-5s %-20s %-16s %-26s %10s %10s %9s %10s %9s %12s %10s %13s %5s %-6s %13s %11s %5s %s\n"
            printf "$FMT_H" "#/Tot" "MC_NAME" "REGION" "SECTOR" "HOURLY_DBR" "HOURLY_BKP" "HOURLY_VS" "HOURLY_VSC" "VSC_READY" "VSC_EBS_GONE" "VSC_NO_HDL" "VSC_NOT_READY" "STUCK" "STATUS" "TOTAL_VSC_DEL" "HOURLY_VSC%" "TIME" "STUCK_DETAIL"
            printf "$FMT_H" "-----" "--------------------" "----------------" "--------------------------" "----------" "----------" "---------" "----------" "---------" "------------" "----------" "-------------" "-----" "------" "-------------" "-----------" "-----" "----------------------------"
            TSV_HEADER="MC_NAME\tREGION\tSECTOR\tHOURLY_DBR\tHOURLY_BKP\tHOURLY_VS\tHOURLY_VSC\tVSC_READY\tVSC_EBS_GONE\tVSC_NO_HDL\tVSC_NOT_READY\tSTUCK\tSTATUS\tTOTAL_VSC_DEL\tHOURLY_VSC_PCT\tTIME\tSTUCK_DETAIL"
        fi
        ;;
    all)
        if [ "$CHECK_AWS" = true ]; then
            FMT_A="%-5s %-20s %-16s %-26s %9s %10s %10s %10s %9s %10s %9s %12s %5s %11s %5s %-6s\n"
            printf "$FMT_A" "#/Tot" "MC_NAME" "REGION" "SECTOR" "TOTAL_VSC" "RETAIN_VSC" "HOURLY_DBR" "HOURLY_BKP" "HOURLY_VS" "HOURLY_VSC" "VSC_READY" "VSC_EBS_GONE" "STUCK" "EBS_SNAPS" "TIME" "STATUS"
            printf "$FMT_A" "-----" "--------------------" "----------------" "--------------------------" "---------" "----------" "----------" "----------" "---------" "----------" "---------" "------------" "-----" "-----------" "-----" "------"
            TSV_HEADER="MC_NAME\tREGION\tSECTOR\tTOTAL_VSC\tRETAIN_VSC\tHOURLY_DBR\tHOURLY_BKP\tHOURLY_VS\tHOURLY_VSC\tVSC_READY\tVSC_EBS_GONE\tSTUCK\tEBS_SNAPS\tTIME\tSTATUS"
        else
            FMT_A="%-5s %-20s %-16s %-26s %9s %10s %10s %10s %9s %10s %9s %12s %5s %5s %-6s\n"
            printf "$FMT_A" "#/Tot" "MC_NAME" "REGION" "SECTOR" "TOTAL_VSC" "RETAIN_VSC" "HOURLY_DBR" "HOURLY_BKP" "HOURLY_VS" "HOURLY_VSC" "VSC_READY" "VSC_EBS_GONE" "STUCK" "TIME" "STATUS"
            printf "$FMT_A" "-----" "--------------------" "----------------" "--------------------------" "---------" "----------" "----------" "----------" "---------" "----------" "---------" "------------" "-----" "-----" "------"
            TSV_HEADER="MC_NAME\tREGION\tSECTOR\tTOTAL_VSC\tRETAIN_VSC\tHOURLY_DBR\tHOURLY_BKP\tHOURLY_VS\tHOURLY_VSC\tVSC_READY\tVSC_EBS_GONE\tSTUCK\tTIME\tSTATUS"
        fi
        ;;
esac

[ -n "$OUTPUT_TSV" ] && echo -e "$TSV_HEADER" > "$OUTPUT_TSV"

: > "${TMPDIR}/stuck_dbr_report"
MC_INDEX=0

# =============================================================================
# MC loop
# =============================================================================
while read -r MC_NAME; do
    [ -z "$MC_NAME" ] && continue
    MC_INDEX=$((MC_INDEX + 1))
    N_TOT="${MC_INDEX}/${MC_COUNT}"
    MC_START=$(date +%s)

    REGION=$(mc_region "$MC_NAME")
    SECTOR=$(mc_sector "$MC_NAME")
    STATUS="ok"

    # --- Retain variables ---
    TOTAL_VSC=0; VELERO_VSC=0; VELERO_VS=0; RETAIN_VSC=0; RETAIN_VS=0; EBS_SNAPS=0
    # --- Hourly variables ---
    HOURLY_DBR=0; HOURLY_BKP=0; HOURLY_VS=0; HOURLY_VSC=0; HOURLY_PCT="0"
    TOTAL_VSC_DEL=0; STUCK_DBR_COUNT=0
    K8S_READY=0; K8S_EBS_GONE=0; K8S_NO_HANDLE=0; K8S_NOT_READY=0
    STUCK_DETAIL="-"

    # -------------------------------------------------------------------------
    # Login to MC
    # -------------------------------------------------------------------------
    ocm backplane login "$MC_NAME" > "${TMPDIR}/login" 2>&1 || true
    oc get namespace "$NAMESPACE" -o name > "${TMPDIR}/ns" 2>/dev/null || true
    if ! [ -s "${TMPDIR}/ns" ]; then
        STATUS="login_fail"
        MC_ELAPSED=$(( $(date +%s) - MC_START ))
        case "$CASE" in
            retain)
                if [ "$CHECK_AWS" = true ]; then
                    printf "$FMT" "$N_TOT" "$MC_NAME" "$REGION" "$SECTOR" "-" "-" "-" "-" "-" "-" "$(format_elapsed $MC_ELAPSED)" "${RED}${STATUS}${NC}"
                else
                    printf "$FMT" "$N_TOT" "$MC_NAME" "$REGION" "$SECTOR" "-" "-" "-" "-" "-" "$(format_elapsed $MC_ELAPSED)" "${RED}${STATUS}${NC}"
                fi
                ;;
            hourly)
                printf "$FMT_H" "$N_TOT" "$MC_NAME" "$REGION" "$SECTOR" "-" "-" "-" "-" "-" "-" "-" "-" "-" "${RED}${STATUS}${NC}" "-" "-" "$(format_elapsed $MC_ELAPSED)" "-"
                ;;
            all)
                if [ "$CHECK_AWS" = true ]; then
                    printf "$FMT_A" "$N_TOT" "$MC_NAME" "$REGION" "$SECTOR" "-" "-" "-" "-" "-" "-" "-" "-" "-" "-" "$(format_elapsed $MC_ELAPSED)" "${RED}${STATUS}${NC}"
                else
                    printf "$FMT_A" "$N_TOT" "$MC_NAME" "$REGION" "$SECTOR" "-" "-" "-" "-" "-" "-" "-" "-" "-" "$(format_elapsed $MC_ELAPSED)" "${RED}${STATUS}${NC}"
                fi
                ;;
        esac
        continue
    fi

    NOW_EPOCH=$(date +%s)

    # -------------------------------------------------------------------------
    # Common K8s data: Velero-labeled VSCs + all VS
    # -------------------------------------------------------------------------
    oc get volumesnapshotcontents -l velero.io/backup-name -o json 2>/dev/null > "${TMPDIR}/vsc.json" || echo '{"items":[]}' > "${TMPDIR}/vsc.json"
    oc get volumesnapshots -A -o json 2>/dev/null > "${TMPDIR}/vs_all.json" || echo '{"items":[]}' > "${TMPDIR}/vs_all.json"

    # -------------------------------------------------------------------------
    # RETAIN data (cases: retain, all)
    # -------------------------------------------------------------------------
    if [[ "$CASE" == "retain" || "$CASE" == "all" ]]; then
        TOTAL_VSC=$(oc get volumesnapshotcontents --no-headers 2>/dev/null | wc -l | tr -d ' ')
        [ -z "$TOTAL_VSC" ] && TOTAL_VSC=0

        VELERO_VSC=$(jq '.items | length' "${TMPDIR}/vsc.json" 2>/dev/null || echo "0")
        [ -z "$VELERO_VSC" ] && VELERO_VSC=0

        RETAIN_VSC=$(jq '[.items[] | select(.spec.deletionPolicy == "Retain")] | length' "${TMPDIR}/vsc.json" 2>/dev/null || echo "0")
        [ -z "$RETAIN_VSC" ] && RETAIN_VSC=0

        # VELERO_VS: VSC refs that actually exist in the cluster (set intersection)
        jq -r '.items[] | "\(.spec.volumeSnapshotRef.namespace // "none")/\(.spec.volumeSnapshotRef.name // "none")"' \
            "${TMPDIR}/vsc.json" 2>/dev/null | sort -u | grep -v '^none/' | grep -v '/none$' > "${TMPDIR}/velero_refs.lst" 2>/dev/null || true
        jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name)"' \
            "${TMPDIR}/vs_all.json" 2>/dev/null | sort -u > "${TMPDIR}/all_vs.lst" 2>/dev/null || true

        VELERO_VS=0
        if [ -s "${TMPDIR}/velero_refs.lst" ] && [ -s "${TMPDIR}/all_vs.lst" ]; then
            VELERO_VS=$(comm -12 "${TMPDIR}/velero_refs.lst" "${TMPDIR}/all_vs.lst" 2>/dev/null | wc -l | tr -d ' ')
        fi
        [ -z "$VELERO_VS" ] && VELERO_VS=0

        # RETAIN_VS: Retain VSC refs that exist
        jq -r '.items[] | select(.spec.deletionPolicy == "Retain") | "\(.spec.volumeSnapshotRef.namespace // "none")/\(.spec.volumeSnapshotRef.name // "none")"' \
            "${TMPDIR}/vsc.json" 2>/dev/null | sort -u | grep -v '^none/' | grep -v '/none$' > "${TMPDIR}/retain_refs.lst" 2>/dev/null || true

        RETAIN_VS=0
        if [ -s "${TMPDIR}/retain_refs.lst" ] && [ -s "${TMPDIR}/all_vs.lst" ]; then
            RETAIN_VS=$(comm -12 "${TMPDIR}/retain_refs.lst" "${TMPDIR}/all_vs.lst" 2>/dev/null | wc -l | tr -d ' ')
        fi
        [ -z "$RETAIN_VS" ] && RETAIN_VS=0
    fi

    # -------------------------------------------------------------------------
    # HOURLY data (cases: hourly, all)
    # -------------------------------------------------------------------------
    if [[ "$CASE" == "hourly" || "$CASE" == "all" ]]; then
        # TOTAL_VSC_DEL: all Velero VSC with Delete policy
        TOTAL_VSC_DEL=$(jq '[.items[] | select(.spec.deletionPolicy == "Delete")] | length' "${TMPDIR}/vsc.json" 2>/dev/null || echo "0")
        [ -z "$TOTAL_VSC_DEL" ] && TOTAL_VSC_DEL=0

        # HOURLY_VSC: per-VSC details for K8s status classification
        : > "${TMPDIR}/hourly_vsc.tsv"
        jq -r --arg p "hourly-full-backup" \
            '.items[] | select(.metadata.labels["velero.io/backup-name"] | startswith($p)) | select(.spec.deletionPolicy == "Delete") |
            [
                .metadata.name,
                .metadata.labels["velero.io/backup-name"],
                (.status.snapshotHandle // .spec.source.snapshotHandle // "none"),
                ((.status.readyToUse // false) | tostring),
                (.status.error.message // "")
            ] | @tsv' \
            "${TMPDIR}/vsc.json" 2>/dev/null > "${TMPDIR}/hourly_vsc.tsv" || true
        HOURLY_VSC=0
        [ -s "${TMPDIR}/hourly_vsc.tsv" ] && HOURLY_VSC=$(wc -l < "${TMPDIR}/hourly_vsc.tsv" | tr -d ' ')

        # K8s status classification
        : > "${TMPDIR}/detail.tsv"
        if [ -s "${TMPDIR}/hourly_vsc.tsv" ]; then
            while IFS=$'\t' read -r _vsc_name _backup_name snap_handle ready error_msg; do
                [ -z "$_vsc_name" ] && continue
                k8s_status=""
                if [ "$snap_handle" = "none" ]; then
                    k8s_status="NO_HANDLE"; K8S_NO_HANDLE=$((K8S_NO_HANDLE + 1))
                elif echo "$error_msg" | grep -qi "not found\|does not exist\|NoSuchSnapshot\|InvalidSnapshot" 2>/dev/null; then
                    k8s_status="EBS_GONE"; K8S_EBS_GONE=$((K8S_EBS_GONE + 1))
                elif [ "$ready" = "true" ]; then
                    k8s_status="READY"; K8S_READY=$((K8S_READY + 1))
                else
                    k8s_status="NOT_READY"; K8S_NOT_READY=$((K8S_NOT_READY + 1))
                fi
                echo -e "${MC_NAME}\t${_vsc_name}\t${_backup_name}\t${snap_handle}\t${ready}\t${error_msg}\t${k8s_status}" >> "${TMPDIR}/detail.tsv"
            done < "${TMPDIR}/hourly_vsc.tsv"
        fi

        # HOURLY_PCT
        if [ "$TOTAL_VSC_DEL" -gt 0 ]; then
            HOURLY_PCT=$((HOURLY_VSC * 100 / TOTAL_VSC_DEL))
        fi

        # HOURLY_VS: by velero label (matches cronjob B3b cascade + B3c orphaned + B4b safeguard)
        HOURLY_VS=$(jq '[.items[] | select((.metadata.labels["velero.io/backup-name"] // "") | startswith("hourly-full-backup"))] | length' \
            "${TMPDIR}/vs_all.json" 2>/dev/null || echo "0")
        [ -z "$HOURLY_VS" ] && HOURLY_VS=0

        # HOURLY_DBR (matches cronjob B1)
        oc get deletebackuprequests -n "$NAMESPACE" -o json 2>/dev/null > "${TMPDIR}/dbr.json" || echo '{"items":[]}' > "${TMPDIR}/dbr.json"
        : > "${TMPDIR}/dbr_hourly.tsv"
        jq -r '.items[] | select(.spec.backupName | startswith("hourly-full-backup")) | "\(.metadata.name)\t\(.spec.backupName)\t\(.status.phase // "")\t\(.metadata.creationTimestamp // "")"' \
            "${TMPDIR}/dbr.json" 2>/dev/null > "${TMPDIR}/dbr_hourly.tsv" || true
        HOURLY_DBR=0
        [ -s "${TMPDIR}/dbr_hourly.tsv" ] && HOURLY_DBR=$(wc -l < "${TMPDIR}/dbr_hourly.tsv" | tr -d ' ')

        # Stuck DBRs (InProgress >= threshold)
        : > "${TMPDIR}/dbr_stuck.lst"
        if [ -s "${TMPDIR}/dbr_hourly.tsv" ] && [ "$NOW_EPOCH" -gt 0 ]; then
            while IFS=$'\t' read -r dbr_name backup_name phase creation_ts; do
                [ "$phase" != "InProgress" ] && [ -n "$phase" ] && continue
                [ -z "$creation_ts" ] && continue
                echo "$creation_ts" > "${TMPDIR}/dbr_ts"
                date -f "${TMPDIR}/dbr_ts" +%s 2>/dev/null > "${TMPDIR}/dbr_ts_epoch" || true
                [ -s "${TMPDIR}/dbr_ts_epoch" ] || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$creation_ts" +%s 2>/dev/null > "${TMPDIR}/dbr_ts_epoch" || true
                if [ -s "${TMPDIR}/dbr_ts_epoch" ]; then
                    read created_epoch < "${TMPDIR}/dbr_ts_epoch" || true
                    if [ -n "$created_epoch" ] && [ "$created_epoch" -gt 0 ]; then
                        age_sec=$((NOW_EPOCH - created_epoch))
                        if [ "$age_sec" -ge "$STUCK_DBR_THRESHOLD_SEC" ]; then
                            printf "%s\t%s\t%s\n" "$dbr_name" "$backup_name" "$age_sec" >> "${TMPDIR}/dbr_stuck.lst"
                            echo -e "${MC_NAME}\t${dbr_name}\t${backup_name}\t${age_sec}" >> "${TMPDIR}/stuck_dbr_report"
                        fi
                    fi
                fi
            done < "${TMPDIR}/dbr_hourly.tsv"
        fi
        [ -s "${TMPDIR}/dbr_stuck.lst" ] && STUCK_DBR_COUNT=$(wc -l < "${TMPDIR}/dbr_stuck.lst" | tr -d ' ')

        # HOURLY_BKP (matches cronjob B2)
        oc get backups -n "$NAMESPACE" -o json 2>/dev/null > "${TMPDIR}/backups.json" || echo '{"items":[]}' > "${TMPDIR}/backups.json"
        HOURLY_BKP=$(jq '[.items[] | select(.metadata.name | startswith("hourly-full-backup"))] | length' "${TMPDIR}/backups.json" 2>/dev/null || echo "0")
        [ -z "$HOURLY_BKP" ] && HOURLY_BKP=0

        # Stuck detail string
        if [ "$STUCK_DBR_COUNT" -gt 0 ] && [ -s "${TMPDIR}/dbr_stuck.lst" ]; then
            : > "${TMPDIR}/stuck_parts.lst"
            while IFS=$'\t' read -r dbr_name _ age_sec; do
                [ -z "$dbr_name" ] && continue
                if [ -n "$age_sec" ] && [ "$age_sec" -ge 86400 ]; then
                    age_str="$((age_sec / 86400))d"
                elif [ -n "$age_sec" ] && [ "$age_sec" -ge 3600 ]; then
                    age_str="$((age_sec / 3600))h"
                elif [ -n "$age_sec" ]; then
                    age_str="$((age_sec / 60))m"
                else
                    age_str="?"
                fi
                echo "${dbr_name} (${age_str})" >> "${TMPDIR}/stuck_parts.lst"
            done < "${TMPDIR}/dbr_stuck.lst"
            STUCK_DETAIL=$(paste -sd ', ' "${TMPDIR}/stuck_parts.lst")
        fi
    fi

    # -------------------------------------------------------------------------
    # AWS EBS check (all cases with --check-aws)
    # -------------------------------------------------------------------------
    if [ "$CHECK_AWS" = true ]; then
        AWS_REGION=""
        AWS_ACCOUNT="unknown"
        CLUSTER_INFO=$(ocm describe cluster "$MC_NAME" --json 2>/dev/null || echo "")
        if [ -n "$CLUSTER_INFO" ] && [ "$CLUSTER_INFO" != "null" ]; then
            AWS_REGION=$(echo "$CLUSTER_INFO" | jq -r '.region.id')
            CLUSTER_ID=$(echo "$CLUSTER_INFO" | jq -r '.id')
            AWS_ACCOUNT=$(ocm get cluster "$CLUSTER_ID" 2>/dev/null | jq -r '.aws.sts.role_arn' | sed -n 's/.*\([0-9]\{12\}\).*/\1/p')
            [ -z "$AWS_ACCOUNT" ] && AWS_ACCOUNT="unknown"
        fi

        if [ "$AWS_ACCOUNT" != "unknown" ]; then
            EBS_TMP=$(mktemp)
            echo "0" > "$EBS_TMP"
            if [ "$AWS_ACCOUNT" = "$CURRENT_AWS_ACCOUNT" ]; then
                EBS_JSON=$(mktemp)
                aws ec2 describe-snapshots --owner-ids self --region "$AWS_REGION" \
                    --query 'Snapshots[].SnapshotId' \
                    --output json --page-size 500 2>/dev/null > "$EBS_JSON" && \
                    jq 'length' "$EBS_JSON" 2>/dev/null > "$EBS_TMP" || echo "0" > "$EBS_TMP"
                rm -f "$EBS_JSON"
            else
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
                        --query 'Snapshots[].SnapshotId' \
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
            [ -z "$EBS_SNAPS" ] && EBS_SNAPS=0

            # Per-VSC AWS cross-check (hourly/all detail)
            if [[ "$CASE" == "hourly" || "$CASE" == "all" ]] && [ "$SHOW_DETAIL" = true ] && [ "$HOURLY_VSC" -gt 0 ]; then
                : > "${TMPDIR}/handles.lst"
                awk -F'\t' '$3 != "none" {print $3}' "${TMPDIR}/hourly_vsc.tsv" | sort -u > "${TMPDIR}/handles.lst" 2>/dev/null || true

                if [ -s "${TMPDIR}/handles.lst" ]; then
                    : > "${TMPDIR}/aws_snaps.lst"
                    if [ "$AWS_ACCOUNT" = "$CURRENT_AWS_ACCOUNT" ]; then
                        aws ec2 describe-snapshots --owner-ids self --region "$AWS_REGION" \
                            --query 'Snapshots[].SnapshotId' --output text 2>/dev/null \
                            | tr '\t' '\n' | sort -u > "${TMPDIR}/aws_snaps.lst" || true
                    else
                        LOCAL_AWS_REGION="$AWS_REGION"
                        LOCAL_AWS_ACCOUNT="$AWS_ACCOUNT"
                        LOCAL_SNAPS_FILE="${TMPDIR}/aws_snaps.lst"
                        (
                            AWS_CREDS_OUTPUT=$(osdctl -S account cli -i "$LOCAL_AWS_ACCOUNT" -o env 2>&1)
                            if echo "$AWS_CREDS_OUTPUT" | grep -qi "error"; then exit 0; fi
                            eval "export $AWS_CREDS_OUTPUT"
                            aws ec2 describe-snapshots --owner-ids self --region "$LOCAL_AWS_REGION" \
                                --query 'Snapshots[].SnapshotId' --output text 2>/dev/null \
                                | tr '\t' '\n' | sort -u > "$LOCAL_SNAPS_FILE" || true
                        )
                    fi

                    declare -A AWS_SNAP_EXISTS
                    if [ -s "${TMPDIR}/aws_snaps.lst" ]; then
                        while read -r sid; do
                            [ -n "$sid" ] && AWS_SNAP_EXISTS["$sid"]=1
                        done < "${TMPDIR}/aws_snaps.lst"
                    fi

                    : > "${TMPDIR}/detail_aws.tsv"
                    while IFS=$'\t' read -r mc vsc_name backup_name snap_handle ready error_msg k8s_status; do
                        aws_status="-"
                        if [ "$snap_handle" != "none" ]; then
                            if [ "${AWS_SNAP_EXISTS[$snap_handle]+_}" ]; then
                                aws_status="AWS_FOUND"
                            else
                                aws_status="AWS_MISSING"
                            fi
                        else
                            aws_status="no_handle"
                        fi
                        echo -e "${mc}\t${vsc_name}\t${backup_name}\t${snap_handle}\t${ready}\t${error_msg}\t${k8s_status}\t${aws_status}" >> "${TMPDIR}/detail_aws.tsv"
                    done < "${TMPDIR}/detail.tsv"
                    mv "${TMPDIR}/detail_aws.tsv" "${TMPDIR}/detail.tsv"
                    unset AWS_SNAP_EXISTS
                fi
            fi
        fi
    fi

    MC_ELAPSED=$(( $(date +%s) - MC_START ))

    # -------------------------------------------------------------------------
    # Print row (case-dependent)
    # -------------------------------------------------------------------------
    case "$CASE" in
        retain)
            TOTAL_VSC=$((TOTAL_VSC + 0)); VELERO_VSC=$((VELERO_VSC + 0)); VELERO_VS=$((VELERO_VS + 0))
            RETAIN_VSC=$((RETAIN_VSC + 0)); RETAIN_VS=$((RETAIN_VS + 0)); EBS_SNAPS=$((EBS_SNAPS + 0))
            if [ "$CHECK_AWS" = true ]; then
                printf "$FMT" "$N_TOT" "$MC_NAME" "$REGION" "$SECTOR" "$TOTAL_VSC" "$VELERO_VSC" "$VELERO_VS" "$RETAIN_VSC" "$RETAIN_VS" "$EBS_SNAPS" "$(format_elapsed $MC_ELAPSED)" "$STATUS"
                [ -n "$OUTPUT_TSV" ] && echo -e "${MC_NAME}\t${REGION}\t${SECTOR}\t${TOTAL_VSC}\t${VELERO_VSC}\t${VELERO_VS}\t${RETAIN_VSC}\t${RETAIN_VS}\t${EBS_SNAPS}\t$(format_elapsed $MC_ELAPSED)\t${STATUS}" >> "$OUTPUT_TSV"
            else
                printf "$FMT" "$N_TOT" "$MC_NAME" "$REGION" "$SECTOR" "$TOTAL_VSC" "$VELERO_VSC" "$VELERO_VS" "$RETAIN_VSC" "$RETAIN_VS" "$(format_elapsed $MC_ELAPSED)" "$STATUS"
                [ -n "$OUTPUT_TSV" ] && echo -e "${MC_NAME}\t${REGION}\t${SECTOR}\t${TOTAL_VSC}\t${VELERO_VSC}\t${VELERO_VS}\t${RETAIN_VSC}\t${RETAIN_VS}\t$(format_elapsed $MC_ELAPSED)\t${STATUS}" >> "$OUTPUT_TSV"
            fi
            ;;
        hourly)
            READY_C=""; [ "$K8S_READY" -gt 0 ] && READY_C="$YELLOW"
            GONE_C=""; [ "$K8S_EBS_GONE" -gt 0 ] && GONE_C="$GREEN"
            NOHDL_C=""; [ "$K8S_NO_HANDLE" -gt 0 ] && NOHDL_C="$GREEN"
            NOTRD_C=""; [ "$K8S_NOT_READY" -gt 0 ] && NOTRD_C="$RED"

            printf "%-5s %-20s %-16s %-26s %10s %10s %9s %10s " "$N_TOT" "$MC_NAME" "$REGION" "$SECTOR" "$HOURLY_DBR" "$HOURLY_BKP" "$HOURLY_VS" "$HOURLY_VSC"
            printf "%s%9s%s %s%12s%s %s%10s%s %s%13s%s " \
                "$READY_C" "$K8S_READY" "${READY_C:+$NC}" \
                "$GONE_C" "$K8S_EBS_GONE" "${GONE_C:+$NC}" \
                "$NOHDL_C" "$K8S_NO_HANDLE" "${NOHDL_C:+$NC}" \
                "$NOTRD_C" "$K8S_NOT_READY" "${NOTRD_C:+$NC}"
            if [ "$CHECK_AWS" = true ]; then
                printf "%5s %-6s %13s %11s %9s %5s %s\n" "$STUCK_DBR_COUNT" "$STATUS" "$TOTAL_VSC_DEL" "${HOURLY_PCT}%" "$EBS_SNAPS" "$(format_elapsed $MC_ELAPSED)" "$STUCK_DETAIL"
                [ -n "$OUTPUT_TSV" ] && echo -e "${MC_NAME}\t${REGION}\t${SECTOR}\t${HOURLY_DBR}\t${HOURLY_BKP}\t${HOURLY_VS}\t${HOURLY_VSC}\t${K8S_READY}\t${K8S_EBS_GONE}\t${K8S_NO_HANDLE}\t${K8S_NOT_READY}\t${STUCK_DBR_COUNT}\t${STATUS}\t${TOTAL_VSC_DEL}\t${HOURLY_PCT}%\t${EBS_SNAPS}\t$(format_elapsed $MC_ELAPSED)\t${STUCK_DETAIL}" >> "$OUTPUT_TSV"
            else
                printf "%5s %-6s %13s %11s %5s %s\n" "$STUCK_DBR_COUNT" "$STATUS" "$TOTAL_VSC_DEL" "${HOURLY_PCT}%" "$(format_elapsed $MC_ELAPSED)" "$STUCK_DETAIL"
                [ -n "$OUTPUT_TSV" ] && echo -e "${MC_NAME}\t${REGION}\t${SECTOR}\t${HOURLY_DBR}\t${HOURLY_BKP}\t${HOURLY_VS}\t${HOURLY_VSC}\t${K8S_READY}\t${K8S_EBS_GONE}\t${K8S_NO_HANDLE}\t${K8S_NOT_READY}\t${STUCK_DBR_COUNT}\t${STATUS}\t${TOTAL_VSC_DEL}\t${HOURLY_PCT}%\t$(format_elapsed $MC_ELAPSED)\t${STUCK_DETAIL}" >> "$OUTPUT_TSV"
            fi
            ;;
        all)
            READY_C=""; [ "$K8S_READY" -gt 0 ] && READY_C="$YELLOW"
            GONE_C=""; [ "$K8S_EBS_GONE" -gt 0 ] && GONE_C="$GREEN"

            printf "%-5s %-20s %-16s %-26s %9s %10s %10s %10s %9s %10s " \
                "$N_TOT" "$MC_NAME" "$REGION" "$SECTOR" "$TOTAL_VSC" "$RETAIN_VSC" "$HOURLY_DBR" "$HOURLY_BKP" "$HOURLY_VS" "$HOURLY_VSC"
            printf "%s%9s%s %s%12s%s " \
                "$READY_C" "$K8S_READY" "${READY_C:+$NC}" \
                "$GONE_C" "$K8S_EBS_GONE" "${GONE_C:+$NC}"
            if [ "$CHECK_AWS" = true ]; then
                printf "%5s %11s %5s %-6s\n" "$STUCK_DBR_COUNT" "$EBS_SNAPS" "$(format_elapsed $MC_ELAPSED)" "$STATUS"
                [ -n "$OUTPUT_TSV" ] && echo -e "${MC_NAME}\t${REGION}\t${SECTOR}\t${TOTAL_VSC}\t${RETAIN_VSC}\t${HOURLY_DBR}\t${HOURLY_BKP}\t${HOURLY_VS}\t${HOURLY_VSC}\t${K8S_READY}\t${K8S_EBS_GONE}\t${STUCK_DBR_COUNT}\t${EBS_SNAPS}\t$(format_elapsed $MC_ELAPSED)\t${STATUS}" >> "$OUTPUT_TSV"
            else
                printf "%5s %5s %-6s\n" "$STUCK_DBR_COUNT" "$(format_elapsed $MC_ELAPSED)" "$STATUS"
                [ -n "$OUTPUT_TSV" ] && echo -e "${MC_NAME}\t${REGION}\t${SECTOR}\t${TOTAL_VSC}\t${RETAIN_VSC}\t${HOURLY_DBR}\t${HOURLY_BKP}\t${HOURLY_VS}\t${HOURLY_VSC}\t${K8S_READY}\t${K8S_EBS_GONE}\t${STUCK_DBR_COUNT}\t$(format_elapsed $MC_ELAPSED)\t${STATUS}" >> "$OUTPUT_TSV"
            fi
            ;;
    esac

    # -------------------------------------------------------------------------
    # Detail (hourly/all cases, --detail flag)
    # -------------------------------------------------------------------------
    if [[ "$CASE" == "hourly" || "$CASE" == "all" ]] && [ "$SHOW_DETAIL" = true ] && [ -s "${TMPDIR}/detail.tsv" ]; then
        echo ""
        echo -e "  ${CYAN}--- Detail: $MC_NAME ($HOURLY_VSC VSCs) ---${NC}"
        HAS_AWS_COL=false
        [ "$CHECK_AWS" = true ] && head -1 "${TMPDIR}/detail.tsv" 2>/dev/null | grep -q $'\t.*\t.*\t.*\t.*\t.*\t.*\t' && HAS_AWS_COL=true

        if [ "$HAS_AWS_COL" = true ]; then
            printf "  %-55s %-45s %-24s %-6s %-10s %s\n" "VSC_NAME" "BACKUP_NAME" "SNAPSHOT_HANDLE" "READY" "K8S_STATUS" "AWS"
            printf "  %-55s %-45s %-24s %-6s %-10s %s\n" "-------------------------------------------------------" "---------------------------------------------" "------------------------" "------" "----------" "----------"
            while IFS=$'\t' read -r _ vsc_name backup_name snap_handle ready error_msg k8s_status aws_status; do
                k8s_d="$k8s_status"
                [ "$k8s_status" = "READY" ] && k8s_d="${YELLOW}READY${NC}"
                [ "$k8s_status" = "EBS_GONE" ] && k8s_d="${GREEN}EBS_GONE${NC}"
                [ "$k8s_status" = "NO_HANDLE" ] && k8s_d="${GREEN}NO_HANDLE${NC}"
                [ "$k8s_status" = "NOT_READY" ] && k8s_d="${RED}NOT_READY${NC}"
                aws_d="$aws_status"
                [ "$aws_status" = "AWS_FOUND" ] && aws_d="${YELLOW}AWS_FOUND${NC}"
                [ "$aws_status" = "AWS_MISSING" ] && aws_d="${GREEN}AWS_MISSING${NC}"
                printf "  %-55s %-45s %-24s %-6s " "$vsc_name" "$backup_name" "$snap_handle" "$ready"
                echo -en "$k8s_d"
                if [ -n "$aws_d" ] && [ "$aws_d" != "-" ]; then
                    printf "  "; echo -e "$aws_d"
                else
                    echo ""
                fi
            done < "${TMPDIR}/detail.tsv"
        else
            printf "  %-55s %-45s %-24s %-6s %-10s\n" "VSC_NAME" "BACKUP_NAME" "SNAPSHOT_HANDLE" "READY" "K8S_STATUS"
            printf "  %-55s %-45s %-24s %-6s %-10s\n" "-------------------------------------------------------" "---------------------------------------------" "------------------------" "------" "----------"
            while IFS=$'\t' read -r _ vsc_name backup_name snap_handle ready error_msg k8s_status; do
                k8s_d="$k8s_status"
                [ "$k8s_status" = "READY" ] && k8s_d="${YELLOW}READY${NC}"
                [ "$k8s_status" = "EBS_GONE" ] && k8s_d="${GREEN}EBS_GONE${NC}"
                [ "$k8s_status" = "NO_HANDLE" ] && k8s_d="${GREEN}NO_HANDLE${NC}"
                [ "$k8s_status" = "NOT_READY" ] && k8s_d="${RED}NOT_READY${NC}"
                printf "  %-55s %-45s %-24s %-6s " "$vsc_name" "$backup_name" "$snap_handle" "$ready"
                echo -e "$k8s_d"
            done < "${TMPDIR}/detail.tsv"
        fi
        echo ""
    fi

done < "$MC_LIST_FILE"

# =============================================================================
# Table footer separator
# =============================================================================
case "$CASE" in
    retain)
        if [ "$CHECK_AWS" = true ]; then
            printf "$FMT" "-----" "--------------------" "----------------" "--------------------------" "---------" "----------" "---------" "----------" "---------" "-----------" "-----" "----------"
        else
            printf "$FMT" "-----" "--------------------" "----------------" "--------------------------" "---------" "----------" "---------" "----------" "---------" "-----" "----------"
        fi
        ;;
    hourly)
        if [ "$CHECK_AWS" = true ]; then
            printf "$FMT_H" "-----" "--------------------" "----------------" "--------------------------" "----------" "----------" "---------" "----------" "---------" "------------" "----------" "-------------" "-----" "------" "-------------" "-----------" "---------" "-----" "----------------------------"
        else
            printf "$FMT_H" "-----" "--------------------" "----------------" "--------------------------" "----------" "----------" "---------" "----------" "---------" "------------" "----------" "-------------" "-----" "------" "-------------" "-----------" "-----" "----------------------------"
        fi
        ;;
    all)
        if [ "$CHECK_AWS" = true ]; then
            printf "$FMT_A" "-----" "--------------------" "----------------" "--------------------------" "---------" "----------" "----------" "----------" "---------" "----------" "---------" "------------" "-----" "-----------" "-----" "------"
        else
            printf "$FMT_A" "-----" "--------------------" "----------------" "--------------------------" "---------" "----------" "----------" "----------" "---------" "----------" "---------" "------------" "-----" "-----" "------"
        fi
        ;;
esac
echo ""

# =============================================================================
# Stuck DBR report (hourly/all cases)
# =============================================================================
if [[ "$CASE" == "hourly" || "$CASE" == "all" ]] && [ -s "${TMPDIR}/stuck_dbr_report" ]; then
    echo -e "${YELLOW}Stuck hourly DBRs (InProgress >=2h, blocking queue):${NC}"
    while IFS=$'\t' read -r mc dbr_name backup_name age_sec; do
        if [ -n "$age_sec" ] && [ "$age_sec" -ge 86400 ]; then
            age_str="stuck $((age_sec / 86400))d"
        elif [ -n "$age_sec" ] && [ "$age_sec" -ge 3600 ]; then
            age_str="stuck $((age_sec / 3600))h"
        elif [ -n "$age_sec" ]; then
            age_str="stuck $((age_sec / 60))m"
        else
            age_str="stuck ?"
        fi
        echo -e "  ${mc}: ${dbr_name}  (backup: ${backup_name})  [${age_str}]"
    done < "${TMPDIR}/stuck_dbr_report"
    echo ""
fi

# =============================================================================
# Column legend (case-dependent)
# =============================================================================
echo "Column legend:"
case "$CASE" in
    retain)
        echo "  TOTAL_VSC    = all VolumeSnapshotContents (including non-Velero)"
        echo "  VELERO_VSC   = VSCs with velero.io/backup-name label"
        echo "  VELERO_VS    = VolumeSnapshots referenced by Velero VSCs (still exist in cluster)"
        echo "  RETAIN_VSC   = Velero VSCs with deletionPolicy=Retain (CronJob Part A cleans these)"
        echo "  RETAIN_VS    = VolumeSnapshots referenced by Retain VSCs (A2b cascade + A3 safeguard)"
        if [ "$CHECK_AWS" = true ]; then
            echo "  EBS_SNAPS    = total AWS EBS snapshots in the MC's account/region"
        fi
        echo "  STATUS: ok = success; login_fail = backplane login failed"
        ;;
    hourly)
        echo "  Cronjob Part B deletion targets (in execution order):"
        echo "    HOURLY_DBR     = hourly DeleteBackupRequests  (cronjob B1 deletes these)"
        echo "    HOURLY_BKP     = hourly Backup CRs            (cronjob B2 deletes these)"
        echo "    HOURLY_VS      = hourly VolumeSnapshots        (cronjob B3b cascade + B3c orphaned + B4b safeguard)"
        echo "    HOURLY_VSC     = hourly VSC, Delete policy     (cronjob B3a direct + B3b cascade + B4 safeguard)"
        echo "  VSC EBS status (snapshotHandle: .status then .spec.source):"
        echo "    VSC_READY      = readyToUse=true + has handle  (EBS likely exists, CSI confirmed)"
        echo "    VSC_EBS_GONE   = error: snapshot not found     (EBS deleted, safe to force-delete)"
        echo "    VSC_NO_HDL     = no snapshotHandle             (never provisioned, safe to force-delete)"
        echo "    VSC_NOT_READY  = readyToUse=false, no error    (ambiguous, use --check-aws --detail)"
        echo "  Diagnostic:"
        echo "    STUCK          = hourly DBRs InProgress >=2h (blocking queue, not deleted by cronjob)"
        echo "    STUCK_DETAIL   = stuck DBR names and age (last column, for quick identification)"
        echo "  Context:"
        echo "    TOTAL_VSC_DEL  = all Velero VSC with Delete policy (denominator for HOURLY_VSC%)"
        echo "    HOURLY_VSC%    = HOURLY_VSC / TOTAL_VSC_DEL"
        if [ "$CHECK_AWS" = true ]; then
            echo "  AWS:"
            echo "    EBS_SNAPS      = total AWS EBS snapshots in the MC's account/region"
        fi
        echo "    STATUS: ok = success; login_fail = no access to $NAMESPACE"
        echo ""
        echo "Force-delete safety (VSC):"
        echo "  EBS_GONE + NO_HANDLE = safe to patch finalizers and force-delete (no AWS orphan risk)"
        echo "  READY                = EBS exists, prefer normal CSI deletion flow"
        echo "  NOT_READY            = unknown, verify with --check-aws --detail"
        ;;
    all)
        echo "  Retain (CronJob Part A):"
        echo "    TOTAL_VSC    = all VolumeSnapshotContents (including non-Velero)"
        echo "    RETAIN_VSC   = Velero VSCs with deletionPolicy=Retain"
        echo "  Hourly (CronJob Part B):"
        echo "    HOURLY_DBR   = hourly DeleteBackupRequests  (B1)"
        echo "    HOURLY_BKP   = hourly Backup CRs            (B2)"
        echo "    HOURLY_VS    = hourly VolumeSnapshots        (B3b cascade + B3c orphaned + B4b safeguard)"
        echo "    HOURLY_VSC   = hourly VSC, Delete policy     (B3a/B3b/B4)"
        echo "  VSC EBS status:"
        echo "    VSC_READY    = readyToUse=true + has handle  (EBS likely exists)"
        echo "    VSC_EBS_GONE = error: snapshot not found     (EBS deleted)"
        echo "  Diagnostic:"
        echo "    STUCK        = hourly DBRs InProgress >=2h"
        if [ "$CHECK_AWS" = true ]; then
            echo "  AWS:"
            echo "    EBS_SNAPS    = total AWS EBS snapshots in the MC's account/region"
        fi
        echo "  STATUS: ok = success; login_fail = login failed"
        echo ""
        echo "  Use --case hourly for full VSC breakdown (NO_HDL, NOT_READY, STUCK_DETAIL, HOURLY_VSC%)"
        echo "  Use --case retain for full retain detail (VELERO_VSC, VELERO_VS, RETAIN_VS)"
        ;;
esac
echo ""

END_TIME=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
echo "=============================================="
echo "  Finished: $END_TIME"
echo "=============================================="

if [ -n "$OUTPUT_TSV" ]; then
    echo ""
    echo -e "${GREEN}TSV written to: $OUTPUT_TSV${NC}"
fi
