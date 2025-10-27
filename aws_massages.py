# SNS or SQS Trigger — Message Queue Processor

# Use case: React to messages from an SNS topic or SQS queue.

# Example Event:

# An order message is pushed to an SQS queue from another service.

# Example Lambda (Python)

import json

def lambda_handler(event, context):
    for record in event['Records']:
        message = record['body']
        print(f"📦 Processing message: {message}")

    return {"statusCode": 200, "body": "Messages processed"}
    

# Real use:

# Asynchronous background jobs

# Notification fan-out systems

# Event-driven microservices