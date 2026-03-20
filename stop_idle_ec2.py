"""
stop_idle_ec2.py
-----------------
Lists all running EC2 instances and stops any that have had
low CPU usage (idle) for the past 24 hours.

How it works:
  1. Connects to AWS using boto3
  2. Finds all EC2 instances currently in "running" state
  3. Checks CloudWatch CPU metrics for each instance over the last 24 hours
  4. If average CPU < threshold (default 5%), the instance is considered idle
  5. Stops idle instances (or just reports them in DRY_RUN mode)

Requirements:
  pip install boto3

AWS Permissions needed:
  - ec2:DescribeInstances
  - ec2:StopInstances
  - cloudwatch:GetMetricStatistics
"""

import boto3
from datetime import datetime, timezone, timedelta

# ─────────────────────────────────────────
# CONFIGURATION — change these as needed
# ─────────────────────────────────────────

AWS_REGION = "eu-west-2"          # London region — change if needed
CPU_IDLE_THRESHOLD = 5.0          # Stop instance if avg CPU % is below this
LOOKBACK_HOURS = 24               # How many hours back to check CPU usage
DRY_RUN = True                    # True = only report, don't actually stop

# ─────────────────────────────────────────
# CONNECT TO AWS
# ─────────────────────────────────────────

ec2_client = boto3.client("ec2", region_name=AWS_REGION)
cloudwatch = boto3.client("cloudwatch", region_name=AWS_REGION)


def get_running_instances():
    """
    Returns a list of all EC2 instances currently in 'running' state.
    Each item includes the instance ID and its Name tag (if it has one).
    """
    response = ec2_client.describe_instances(
        Filters=[{"Name": "instance-state-name", "Values": ["running"]}]
    )

    instances = []
    for reservation in response["Reservations"]:
        for instance in reservation["Instances"]:
            instance_id = instance["InstanceId"]

            # Try to get the 'Name' tag — not all instances have one
            name = "Unnamed"
            for tag in instance.get("Tags", []):
                if tag["Key"] == "Name":
                    name = tag["Value"]
                    break

            instances.append({
                "id": instance_id,
                "name": name,
                "type": instance["InstanceType"],
                "launched": instance["LaunchTime"].strftime("%Y-%m-%d %H:%M UTC")
            })

    return instances


def get_average_cpu(instance_id):
    """
    Queries CloudWatch for the average CPU utilisation of an instance
    over the past LOOKBACK_HOURS hours.

    Returns the average CPU % as a float, or None if no data is available.
    """
    end_time = datetime.now(timezone.utc)
    start_time = end_time - timedelta(hours=LOOKBACK_HOURS)

    response = cloudwatch.get_metric_statistics(
        Namespace="AWS/EC2",
        MetricName="CPUUtilization",
        Dimensions=[{"Name": "InstanceId", "Value": instance_id}],
        StartTime=start_time,
        EndTime=end_time,
        Period=3600,        # 1-hour intervals
        Statistics=["Average"]
    )

    datapoints = response.get("Datapoints", [])

    if not datapoints:
        return None  # No data — instance may be too new or metrics not enabled

    # Calculate the overall average across all hourly datapoints
    avg_cpu = sum(d["Average"] for d in datapoints) / len(datapoints)
    return round(avg_cpu, 2)


def stop_instance(instance_id, dry_run=True):
    """
    Stops the given EC2 instance.
    If dry_run=True, it only simulates the stop (safe mode).
    """
    if dry_run:
        print(f"  [DRY RUN] Would stop instance: {instance_id}")
        return

    ec2_client.stop_instances(InstanceIds=[instance_id])
    print(f"  ✅ Stopped instance: {instance_id}")


# ─────────────────────────────────────────
# MAIN LOGIC
# ─────────────────────────────────────────

def main():
    print("=" * 60)
    print("  EC2 Idle Instance Checker")
    print(f"  Region     : {AWS_REGION}")
    print(f"  Threshold  : CPU < {CPU_IDLE_THRESHOLD}% over {LOOKBACK_HOURS} hours")
    print(f"  Mode       : {'DRY RUN (no instances will be stopped)' if DRY_RUN else '⚠️  LIVE — idle instances WILL be stopped'}")
    print("=" * 60)

    # Step 1: Get all running instances
    instances = get_running_instances()

    if not instances:
        print("\nNo running EC2 instances found.")
        return

    print(f"\nFound {len(instances)} running instance(s):\n")

    idle_instances = []
    active_instances = []
    no_data_instances = []

    # Step 2: Check CPU for each instance
    for inst in instances:
        iid = inst["id"]
        name = inst["name"]
        itype = inst["type"]

        avg_cpu = get_average_cpu(iid)

        if avg_cpu is None:
            status = "⚪ NO DATA"
            no_data_instances.append(inst)
        elif avg_cpu < CPU_IDLE_THRESHOLD:
            status = f"🔴 IDLE    (avg CPU: {avg_cpu}%)"
            idle_instances.append(inst)
        else:
            status = f"🟢 ACTIVE  (avg CPU: {avg_cpu}%)"
            active_instances.append(inst)

        print(f"  {iid}  |  {name:<20}  |  {itype:<12}  |  {status}")

    # Step 3: Stop idle instances
    print("\n" + "-" * 60)

    if idle_instances:
        print(f"\n⚠️  {len(idle_instances)} idle instance(s) found. Stopping them now...\n")
        for inst in idle_instances:
            print(f"  → {inst['name']} ({inst['id']})")
            stop_instance(inst["id"], dry_run=DRY_RUN)
    else:
        print("\n✅ No idle instances found. Nothing to stop.")

    # Step 4: Summary
    print("\n" + "=" * 60)
    print("  SUMMARY")
    print("=" * 60)
    print(f"  Total running  : {len(instances)}")
    print(f"  Active         : {len(active_instances)}")
    print(f"  Idle (stopped) : {len(idle_instances)}")
    print(f"  No data        : {len(no_data_instances)}")
    print("=" * 60)

    if DRY_RUN and idle_instances:
        print("\n  💡 To actually stop instances, set DRY_RUN = False at the top of the script.")


if __name__ == "__main__":
    main()
