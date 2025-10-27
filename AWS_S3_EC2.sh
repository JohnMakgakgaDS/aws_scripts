#!/bin/bash
# AWS Automation Script: S3 + EC2 + IAM Role
# ------------------------------------------
# Creates an S3 bucket, an IAM role with S3 access, and an EC2 instance
# that can access the bucket. Optionally cleans up all resources.

set -e  # Stop on error

# ====== Configuration ======
REGION="us-east-1"
BUCKET_NAME="demo-bucket-$RANDOM"
INSTANCE_NAME="demo-ec2-instance"
AMI_ID="ami-0c02fb55956c7d316" # Amazon Linux 2 (us-east-1)
INSTANCE_TYPE="t2.micro"
KEY_NAME="demo-keypair"
SECURITY_GROUP_NAME="demo-sg"
ROLE_NAME="demo-ec2-s3-role"
INSTANCE_PROFILE_NAME="demo-ec2-s3-profile"
POLICY_NAME="demo-ec2-s3-policy"
FILE_NAME="demo.txt"

echo "🔧 Region: $REGION"
echo "🪣 Bucket: $BUCKET_NAME"
echo "💻 Instance: $INSTANCE_NAME"
echo "🔐 Role: $ROLE_NAME"

# ====== Create S3 Bucket ======
echo "Creating S3 bucket..."
aws s3api create-bucket \
  --bucket "$BUCKET_NAME" \
  --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION" >/dev/null
echo "✅ Bucket created: $BUCKET_NAME"

# ====== Create IAM Role ======
echo "Creating IAM role for EC2..."
TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)

aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document "$TRUST_POLICY" >/dev/null

# Create inline policy to allow S3 access
ACCESS_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": [
        "arn:aws:s3:::${BUCKET_NAME}",
        "arn:aws:s3:::${BUCKET_NAME}/*"
      ]
    }
  ]
}
EOF
)

aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "$POLICY_NAME" \
  --policy-document "$ACCESS_POLICY" >/dev/null

echo "✅ IAM role created and policy attached."

# ====== Create Instance Profile ======
aws iam create-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" >/dev/null
aws iam add-role-to-instance-profile \
  --instance-profile-name "$INSTANCE_PROFILE_NAME" \
  --role-name "$ROLE_NAME" >/dev/null

echo "✅ Instance profile created: $INSTANCE_PROFILE_NAME"

# ====== Create Security Group ======
echo "Creating security group..."
SG_ID=$(aws ec2 create-security-group \
  --group-name "$SECURITY_GROUP_NAME" \
  --description "Demo security group for EC2" \
  --region "$REGION" \
  --query 'GroupId' \
  --output text)

# Allow SSH
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0 >/dev/null
echo "✅ Security group created: $SG_ID"

# ====== Create Key Pair ======
echo "Creating key pair..."
aws ec2 create-key-pair \
  --key-name "$KEY_NAME" \
  --query "KeyMaterial" \
  --output text > "${KEY_NAME}.pem"
chmod 400 "${KEY_NAME}.pem"
echo "✅ Key pair created: $KEY_NAME.pem"

# ====== Launch EC2 Instance ======
echo "Launching EC2 instance..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --iam-instance-profile Name="$INSTANCE_PROFILE_NAME" \
  --region "$REGION" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "✅ EC2 instance launched: $INSTANCE_ID"
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"

PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)

echo "🌐 EC2 instance public IP: $PUBLIC_IP"

# ====== Upload a test file to S3 ======
echo "Creating and uploading $FILE_NAME..."
echo "Hello from EC2-S3 integration demo!" > "$FILE_NAME"
aws s3 cp "$FILE_NAME" "s3://$BUCKET_NAME/" >/dev/null
echo "✅ File uploaded."

echo "💡 You can SSH into your instance with:"
echo "   ssh -i ${KEY_NAME}.pem ec2-user@${PUBLIC_IP}"
echo "   (Then run: aws s3 ls s3://${BUCKET_NAME}/ to verify access)"

# ====== Optional Cleanup ======
read -p "🧹 Do you want to delete all resources when done? (y/n): " CLEANUP
if [[ "$CLEANUP" == "y" ]]; then
  echo "Cleaning up..."

  echo "Terminating EC2 instance..."
  aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$REGION" >/dev/null
  aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" --region "$REGION"

  echo "Deleting S3 bucket..."
  aws s3 rm "s3://$BUCKET_NAME/" --recursive >/dev/null
  aws s3api delete-bucket --bucket "$BUCKET_NAME" --region "$REGION"

  echo "Deleting IAM resources..."
  aws iam remove-role-from-instance-profile \
    --instance-profile-name "$INSTANCE_PROFILE_NAME" \
    --role-name "$ROLE_NAME" >/dev/null
  aws iam delete-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" >/dev/null
  aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$POLICY_NAME" >/dev/null
  aws iam delete-role --role-name "$ROLE_NAME" >/dev/null

  echo "Deleting key pair and security group..."
  aws ec2 delete-key-pair --key-name "$KEY_NAME" --region "$REGION"
  aws ec2 delete-security-group --group-id "$SG_ID" --region "$REGION"
  rm -f "${KEY_NAME}.pem"

  echo "✅ All resources cleaned up!"
else
  echo "Resources retained:"
  echo " - EC2 instance: $INSTANCE_ID ($PUBLIC_IP)"
  echo " - IAM role: $ROLE_NAME"
  echo " - S3 bucket: $BUCKET_NAME"
fi
