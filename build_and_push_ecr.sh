#!/bin/bash

# --- CONFIGURATION ---
REGION="us-east-1"
AWS_ACCOUNT_ID="YOUR_AWS_ACCOUNT_ID"
LARAVEL_REPO_NAME="laravel-app"
FLUTTER_REPO_NAME="flutter-app"

# --- LOGIN TO ECR ---
echo "🔐 Logging in to Amazon ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

# --- BUILD DOCKER IMAGES ---
echo "🐳 Building Docker images..."
docker build -t ${LARAVEL_REPO_NAME}:latest ./laravel
docker build -t ${FLUTTER_REPO_NAME}:latest ./flutter

# --- TAG IMAGES ---
echo "🏷️ Tagging Docker images for ECR..."
docker tag ${LARAVEL_REPO_NAME}:latest ${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${LARAVEL_REPO_NAME}:latest
docker tag ${FLUTTER_REPO_NAME}:latest ${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${FLUTTER_REPO_NAME}:latest

# --- CREATE ECR REPOSITORIES IF NOT EXIST ---
echo "🪣 Ensuring ECR repositories exist..."
aws ecr describe-repositories --repository-names ${LARAVEL_REPO_NAME} >/dev/null 2>&1 || \
aws ecr create-repository --repository-name ${LARAVEL_REPO_NAME} --region ${REGION}

aws ecr describe-repositories --repository-names ${FLUTTER_REPO_NAME} >/dev/null 2>&1 || \
aws ecr create-repository --repository-name ${FLUTTER_REPO_NAME} --region ${REGION}

# --- PUSH IMAGES TO ECR ---
echo "🚀 Pushing Docker images to ECR..."
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${LARAVEL_REPO_NAME}:latest
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${FLUTTER_REPO_NAME}:latest

echo "✅ Docker images successfully pushed to Amazon ECR!"

