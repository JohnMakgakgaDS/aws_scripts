import json
import os
import boto3
import pymysql
import psycopg2

# --- Environment Variables ---
MYSQL_HOST = os.environ['MYSQL_HOST']
MYSQL_USER = os.environ['MYSQL_USER']
MYSQL_PASS = os.environ['MYSQL_PASS']
MYSQL_DB   = os.environ['MYSQL_DB']

PG_HOST = os.environ['PG_HOST']
PG_USER = os.environ['PG_USER']
PG_PASS = os.environ['PG_PASS']
PG_DB   = os.environ['PG_DB']

def get_mysql_connection():
    return pymysql.connect(
        host=MYSQL_HOST,
        user=MYSQL_USER,
        password=MYSQL_PASS,
        database=MYSQL_DB
    )

def get_pg_connection():
    return psycopg2.connect(
        host=PG_HOST,
        user=PG_USER,
        password=PG_PASS,
        dbname=PG_DB
    )

def lambda_handler(event, context):
    for record in event['Records']:
        event_name = record['eventName']  # INSERT, MODIFY, REMOVE
        new_image = record['dynamodb'].get('NewImage', {})
        old_image = record['dynamodb'].get('OldImage', {})

        print(f"🔔 DynamoDB {event_name} event detected.")
        print(json.dumps(new_image))

        # Convert DynamoDB JSON to plain Python dict
        item = {k: list(v.values())[0] for k, v in new_image.items()} if new_image else {}

        try:
            mysql_conn = get_mysql_connection()
            pg_conn = get_pg_connection()
            mysql_cursor = mysql_conn.cursor()
            pg_cursor = pg_conn.cursor()

            if event_name == 'INSERT':
                print("🧾 Inserting record into MySQL and PostgreSQL...")
                sql = "INSERT INTO orders (order_id, customer_name, amount) VALUES (%s, %s, %s)"
                data = (item.get('order_id'), item.get('customer_name'), item.get('amount'))
                mysql_cursor.execute(sql, data)
                pg_cursor.execute(sql, data)

            elif event_name == 'MODIFY':
                print("✏️ Updating record in MySQL and PostgreSQL...")
                sql = "UPDATE orders SET customer_name=%s, amount=%s WHERE order_id=%s"
                data = (item.get('customer_name'), item.get('amount'), item.get('order_id'))
                mysql_cursor.execute(sql, data)
                pg_cursor.execute(sql, data)

            elif event_name == 'REMOVE':
                print("🗑️ Deleting record from MySQL and PostgreSQL...")
                old_item = {k: list(v.values())[0] for k, v in old_image.items()} if old_image else {}
                sql = "DELETE FROM orders WHERE order_id=%s"
                data = (old_item.get('order_id'),)
                mysql_cursor.execute(sql, data)
                pg_cursor.execute(sql, data)

            mysql_conn.commit()
            pg_conn.commit()

        except Exception as e:
            print(f"❌ Error processing record: {str(e)}")

        finally:
            if mysql_cursor: mysql_cursor.close()
            if pg_cursor: pg_cursor.close()
            if mysql_conn: mysql_conn.close()
            if pg_conn: pg_conn.close()

    return {
        "statusCode": 200,
        "body": json.dumps("Processed DynamoDB Stream")
    }

# Environment Variables (in Lambda Configuration)

# Set these in your Lambda environment variables (or via Terraform/CloudFormation):

# Variable	Example
# MYSQL_HOST	my-mysql-db.c12345.us-east-1.rds.amazonaws.com
# MYSQL_USER	admin
# MYSQL_PASS	password123
# MYSQL_DB	orders_db
# PG_HOST	my-postgres-db.c6789.us-east-1.rds.amazonaws.com
# PG_USER	postgres
# PG_PASS	securepass
# PG_DB	orders_pg
# MySQL and PostgreSQL Table Setup

# Make sure both databases have an orders table:

# For MySQL

# CREATE TABLE orders (
#   order_id VARCHAR(255) PRIMARY KEY,
#   customer_name VARCHAR(255),
#   amount DECIMAL(10,2)
# );


# For PostgreSQL

# CREATE TABLE orders (
#   order_id VARCHAR(255) PRIMARY KEY,
#   customer_name VARCHAR(255),
#   amount DECIMAL(10,2)
# );

# 🧪 Testing Locally

# You can simulate a DynamoDB event with AWS SAM or a test JSON file:

# sam local invoke "DynamoDBSyncFunction" -e event.json


# Example event.json:

# {
#   "Records": [
#     {
#       "eventName": "INSERT",
#       "dynamodb": {
#         "NewImage": {
#           "order_id": {"S": "123"},
#           "customer_name": {"S": "Alice"},
#           "amount": {"N": "99.99"}
#         }
#       }
#     }
#   ]
# }

# 🚀 Real-World Use Cases

# Analytics replication: Keep MySQL and PostgreSQL in sync for BI dashboards.

# Multi-DB redundancy: Use both databases for reliability.

# Cross-service events: Sync order updates between different applications.

# Email notifications: Integrate with SES to send “Order Confirmation” emails on INSERT.