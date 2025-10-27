#!/bin/bash
# Create S3 bucket and upload file
#Make the shell script executable:

#chmod +x setup.sh


#Run it:

#./Create_S3_bucket.sh

BUCKET_NAME="my-example-bucket-$RANDOM"
REGION="us-east-1"
FILE_PATH="file.sql"

# Create a new bucket
aws s3api create-bucket --bucket $BUCKET_NAME --region $REGION --create-bucket-configuration LocationConstraint=$REGION

# Upload a file
aws s3 cp $FILE_PATH s3://$BUCKET_NAME/

echo "File uploaded to s3://$BUCKET_NAME/$FILE_PATH"

