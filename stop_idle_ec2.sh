#!/bin/bash
# ─────────────────────────────────────────────────────────────────
# stop_idle_ec2.sh
# -----------------------------------------------------------------
# Lists all running EC2 instances and stops ones that have had
# low CPU usage (idle) for the past 24 hours.
#
# How it works:
#   1. Uses AWS CLI to find all running EC2 instances
#   2. Queries CloudWatch for average CPU over the last 24 hours
#   3. If average CPU < threshold, the instance is considered idle
#   4. Stops idle instances (or just reports them in DRY_RUN mode)
#
# Requirements:
#   - AWS CLI installed and configured (aws configure)
#   - jq installed (sudo apt install jq)
#
# Usage:
#   chmod +x stop_idle_ec2.sh
#   ./stop_idle_ec2.sh
# ─────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────
# CONFIGURATION — change these as needed
# ─────────────────────────────────────────

AWS_REGION="eu-west-2"        # London region
CPU_IDLE_THRESHOLD=5          # Stop instance if avg CPU % is below this
LOOKBACK_HOURS=24             # How many hours back to check
DRY_RUN=true                  # true = only report, don't actually stop

# ─────────────────────────────────────────
# COLOURS FOR OUTPUT
# ─────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Colour

# ─────────────────────────────────────────
# HELPER: Check required tools are installed
# ─────────────────────────────────────────

check_dependencies() {
    for tool in aws jq; do
        if ! command -v "$tool" &>/dev/null; then
            echo -e "${RED}Error: '$tool' is not installed.${NC}"
            echo "Install it with: sudo apt install $tool"
            exit 1
        fi
    done
}

# ─────────────────────────────────────────
# HELPER: Get average CPU for an instance
# Returns the average as a whole number (integer)
# ─────────────────────────────────────────

get_average_cpu() {
    local instance_id=$1

    # Calculate time window
    local end_time
    end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local start_time
    start_time=$(date -u -d "$LOOKBACK_HOURS hours ago" +"%Y-%m-%dT%H:%M:%SZ")

    # Query CloudWatch for CPU metrics
    local result
    result=$(aws cloudwatch get-metric-statistics \
        --region "$AWS_REGION" \
        --namespace "AWS/EC2" \
        --metric-name "CPUUtilization" \
        --dimensions "Name=InstanceId,Value=$instance_id" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --period 3600 \
        --statistics Average \
        --output json 2>/dev/null)

    # Count datapoints returned
    local datapoint_count
    datapoint_count=$(echo "$result" | jq '.Datapoints | length')

    if [[ "$datapoint_count" -eq 0 ]]; then
        echo "NO_DATA"
        return
    fi

    # Calculate average CPU across all hourly datapoints
    local avg_cpu
    avg_cpu=$(echo "$result" | jq '[.Datapoints[].Average] | add / length | floor')

    echo "$avg_cpu"
}

# ─────────────────────────────────────────
# HELPER: Stop an instance (or dry run)
# ─────────────────────────────────────────

stop_instance() {
    local instance_id=$1

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "    ${YELLOW}[DRY RUN] Would stop: $instance_id${NC}"
    else
        aws ec2 stop-instances \
            --region "$AWS_REGION" \
            --instance-ids "$instance_id" \
            --output json > /dev/null
        echo -e "    ${GREEN}✅ Stopped: $instance_id${NC}"
    fi
}

# ─────────────────────────────────────────
# MAIN LOGIC
# ─────────────────────────────────────────

main() {
    check_dependencies

    echo "============================================================"
    echo "  EC2 Idle Instance Checker (Bash)"
    echo "  Region    : $AWS_REGION"
    echo "  Threshold : CPU < ${CPU_IDLE_THRESHOLD}% over ${LOOKBACK_HOURS} hours"
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  Mode      : ${YELLOW}DRY RUN (no instances will be stopped)${NC}"
    else
        echo -e "  Mode      : ${RED}⚠️  LIVE — idle instances WILL be stopped${NC}"
    fi
    echo "============================================================"

    # Step 1: Get all running instance IDs and their Name tags
    echo -e "\n${CYAN}Fetching running instances...${NC}\n"

    local instance_data
    instance_data=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --filters "Name=instance-state-name,Values=running" \
        --query "Reservations[*].Instances[*].{ID:InstanceId,Name:Tags[?Key=='Name']|[0].Value,Type:InstanceType}" \
        --output json 2>/dev/null | jq -c '.[][] ')

    if [[ -z "$instance_data" ]]; then
        echo "No running EC2 instances found."
        exit 0
    fi

    # Counters for summary
    local total=0
    local active=0
    local idle=0
    local no_data=0
    local idle_ids=()

    # Step 2: Loop through each instance and check CPU
    while IFS= read -r instance; do
        local instance_id
        instance_id=$(echo "$instance" | jq -r '.ID')
        local name
        name=$(echo "$instance" | jq -r '.Name // "Unnamed"')
        local itype
        itype=$(echo "$instance" | jq -r '.Type')

        ((total++))

        local avg_cpu
        avg_cpu=$(get_average_cpu "$instance_id")

        if [[ "$avg_cpu" == "NO_DATA" ]]; then
            echo -e "  $instance_id  |  $(printf '%-20s' "$name")  |  $(printf '%-12s' "$itype")  |  ⚪ NO DATA"
            ((no_data++))
        elif [[ "$avg_cpu" -lt "$CPU_IDLE_THRESHOLD" ]]; then
            echo -e "  $instance_id  |  $(printf '%-20s' "$name")  |  $(printf '%-12s' "$itype")  |  ${RED}🔴 IDLE    (avg CPU: ${avg_cpu}%)${NC}"
            ((idle++))
            idle_ids+=("$instance_id")
        else
            echo -e "  $instance_id  |  $(printf '%-20s' "$name")  |  $(printf '%-12s' "$itype")  |  ${GREEN}🟢 ACTIVE  (avg CPU: ${avg_cpu}%)${NC}"
            ((active++))
        fi

    done <<< "$instance_data"

    # Step 3: Stop idle instances
    echo ""
    echo "------------------------------------------------------------"

    if [[ ${#idle_ids[@]} -gt 0 ]]; then
        echo -e "\n${YELLOW}⚠️  ${idle} idle instance(s) found. Stopping them now...${NC}\n"
        for iid in "${idle_ids[@]}"; do
            stop_instance "$iid"
        done
    else
        echo -e "\n${GREEN}✅ No idle instances found. Nothing to stop.${NC}"
    fi

    # Step 4: Summary
    echo ""
    echo "============================================================"
    echo "  SUMMARY"
    echo "============================================================"
    echo "  Total running  : $total"
    echo -e "  Active         : ${GREEN}$active${NC}"
    echo -e "  Idle (stopped) : ${RED}$idle${NC}"
    echo "  No data        : $no_data"
    echo "============================================================"

    if [[ "$DRY_RUN" == true && "$idle" -gt 0 ]]; then
        echo ""
        echo -e "  ${CYAN}💡 To actually stop instances, set DRY_RUN=false at the top of the script.${NC}"
    fi
}

main
