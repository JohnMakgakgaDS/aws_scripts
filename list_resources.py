import boto3

s3 = boto3.client("s3")
lambda_client = boto3.client("lambda")

print("S3 Buckets:")
for bucket in s3.list_buckets()["Buckets"]:
    print(" -", bucket["Name"])

print("\nLambda Functions:")
for fn in lambda_client.list_functions()["Functions"]:
    print(" -", fn["FunctionName"])

