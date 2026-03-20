# 🛑 EC2 Idle Instance Checker

Automatically detects and stops idle AWS EC2 instances to reduce cloud costs.

Available in both **Python** (`boto3`) and **Bash** (`AWS CLI`) — same logic, two languages.

---

## 💡 What It Does

1. Connects to your AWS account
2. Finds all EC2 instances currently in **running** state
3. Checks **CloudWatch CPU metrics** for each instance over the last 24 hours
4. If average CPU usage is **below 5%**, the instance is considered idle
5. **Stops idle instances** — or just reports them in safe Dry Run mode

---

## 📁 Project Structure

```
ec2-idle-checker/
│
├── stop_idle_ec2.py       # Python version (uses boto3)
├── stop_idle_ec2.sh       # Bash version (uses AWS CLI + jq)
└── README.md
```

---

## ⚙️ Configuration

Both scripts have a configuration block at the top. Edit these before running:

| Variable             | Default      | Description                                      |
|----------------------|--------------|--------------------------------------------------|
| `AWS_REGION`         | `eu-west-2`  | AWS region to check (eu-west-2 = London)        |
| `CPU_IDLE_THRESHOLD` | `5`          | Stop instance if avg CPU is below this %        |
| `LOOKBACK_HOURS`     | `24`         | How many hours of CPU history to check          |
| `DRY_RUN`            | `True`       | If True, only reports — does NOT stop instances |

> ⚠️ Always test with `DRY_RUN = True` first before running in a live environment.

---

## 🐍 Python Version

### Requirements

```bash
pip install boto3
```

### Setup AWS credentials

```bash
aws configure
# Enter your AWS Access Key, Secret Key, and region when prompted
```

### Run

```bash
python stop_idle_ec2.py
```

---

## 🖥️ Bash Version

### Requirements

```bash
# AWS CLI
sudo apt install awscli

# jq (JSON parser for Bash)
sudo apt install jq
```

### Setup AWS credentials

```bash
aws configure
```

### Run

```bash
# Make the script executable (one-time)
chmod +x stop_idle_ec2.sh

# Run it
./stop_idle_ec2.sh
```

---

## 📊 Example Output

```
============================================================
  EC2 Idle Instance Checker
  Region    : eu-west-2
  Threshold : CPU < 5% over 24 hours
  Mode      : DRY RUN (no instances will be stopped)
============================================================

Fetching running instances...

  i-0abc123def  |  web-server-prod      |  t3.medium    |  🟢 ACTIVE  (avg CPU: 34%)
  i-0def456ghi  |  staging-server       |  t2.micro     |  🔴 IDLE    (avg CPU: 0%)
  i-0ghi789jkl  |  test-env             |  t2.micro     |  🔴 IDLE    (avg CPU: 1%)

------------------------------------------------------------

⚠️  2 idle instance(s) found. Stopping them now...

  [DRY RUN] Would stop: i-0def456ghi
  [DRY RUN] Would stop: i-0ghi789jkl

============================================================
  SUMMARY
============================================================
  Total running  : 3
  Active         : 1
  Idle (stopped) : 2
  No data        : 0
============================================================

  💡 To actually stop instances, set DRY_RUN=false at the top of the script.
```

---

## 🔐 Required AWS IAM Permissions

Your AWS user or role needs these permissions to run this script:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:StopInstances",
        "cloudwatch:GetMetricStatistics"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## 🔄 Automate It (Optional)

You can schedule this script to run automatically every day using a **cron job** on Linux:

```bash
# Open crontab editor
crontab -e

# Add this line to run the script every day at 2:00 AM
0 2 * * * /usr/bin/python3 /home/ubuntu/ec2-idle-checker/stop_idle_ec2.py >> /var/log/ec2_checker.log 2>&1
```

Or deploy it as an **AWS Lambda function** triggered by EventBridge (CloudWatch Events) for a fully serverless solution.

---

## 🧠 Skills Demonstrated

- Python scripting with `boto3` (AWS SDK)
- Bash scripting with AWS CLI
- AWS EC2 and CloudWatch integration
- Infrastructure cost optimisation
- Safe deployment practices (Dry Run mode)
- IAM permissions and least-privilege principle

---

## 👤 Author

**Summeet Pokhrel**  
MSc Software Engineering | Junior Cloud Engineer  
[GitHub: @summeet95](https://github.com/summeet95)

---

## 📄 Licence

MIT — free to use and modify.
