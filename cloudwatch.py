# CloudWatch Scheduled Event — Cron Job

# Use case: Run recurring tasks (e.g., daily reports, cleanup jobs).

# Example Event:

# Trigger Lambda every night at midnight using a CloudWatch Event Rule (cron expression).

# Example Lambda (Python)

import datetime

def lambda_handler(event, context):
    now = datetime.datetime.utcnow()
    print(f"🕛 Running scheduled cleanup job at {now}")

    # Example: Delete old files, refresh data, etc.
    return {"statusCode": 200, "body": "Cleanup completed"}

# Real use:

# Clear old S3 logs

# Send daily reports

# Rotate temporary keys