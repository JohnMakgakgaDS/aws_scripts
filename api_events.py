# API Gateway Trigger — Serverless REST API

# Use case: Run backend logic for a web or mobile app with no servers.

# Example Event:

# A POST request hits /api/contact.

# Example Lambda (Python)

import json

def lambda_handler(event, context):
    body = json.loads(event.get('body', '{}'))
    name = body.get('name')
    email = body.get('email')

    print(f"📨 Contact form submission from {name} ({email})")

    return {
        "statusCode": 200,
        "body": json.dumps({"message": "Contact form received!"})
    }

# Real use:

# Contact forms

# Login/registration endpoints

# Payment processing logic