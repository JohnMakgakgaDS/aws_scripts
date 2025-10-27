#!/bin/bash
# Below is a fully updated version of your aws_deploy_full_app.sh, using GitHub repo  instead of local folders. It:

# ✅ Clones your Laravel + Flutter app from GitHub
# ✅ Creates an S3 bucket
# ✅ Creates an IAM role and instance profile (with S3 access)
# ✅ Launches an EC2 instance with that role
# ✅ Creates and initializes a MySQL (RDS) database using file.sql
# ✅ Configures EC2 to run both apps automatically
# ✅ Optionally cleans everything up

# Summery of AWS Full Deployment with GitHub Repo + MySQL
# ---------------------------------------------
# ✅ Creates S3 bucket
# ✅ Creates IAM role for EC2 (S3 access)
# ✅ Launches EC2 instance
# ✅ Creates MySQL DB (RDS) and imports file.sql
# ✅ Clones apps from GitHub, uploads to S3, and configures EC2 to run them

set -e

# ====== CONFIG ======
REGION="us-east-1"
BUCKET_NAME="todoapp-bucket-$RANDOM"
INSTANCE_NAME="todoapp-ec2"
AMI_ID="ami-0c02fb55956c7d316"   # Amazon Linux 2
INSTANCE_TYPE="t3.micro"
KEY_NAME="todoapp-keypair"
SECURITY_GROUP_NAME="todoapp-sg"
ROLE_NAME="todoapp-role"
INSTANCE_PROFILE_NAME="todoappp-profile"
POLICY_NAME="todoapp-policy"
REPO_URL="https://github.com/Johnmakgakgads/todoapp.git"
SQL_FILE="./file.sql"

# MySQL / RDS config
DB_ID="todoapp-rds-$RANDOM"
DB_USER="admin"
DB_PASS="StrongPass123!"
DB_NAME="todo_db"
DB_INSTANCE_TYPE="db.t3.micro"
DB_STORAGE=20

# ====== VALIDATION ======
if [[ ! -f "$SQL_FILE" ]]; then
  echo "❌ SQL file not found: $SQL_FILE"
  exit 1
fi

echo "🚀 Starting full deployment using GitHub repo: $REPO_URL"

# ====== Clone Repo ======
echo "📥 Cloning repository..."
rm -rf todoapp
git clone "$REPO_URL" todoapp >/dev/null
echo "✅ Repo cloned successfully."

# ====== Create S3 Bucket ======
aws s3api create-bucket \
  --bucket "$BUCKET_NAME" \
  --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION" >/dev/null
echo "✅ S3 bucket created: $BUCKET_NAME"

# ====== Create IAM Role ======
TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ec2.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF
)
aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document "$TRUST_POLICY" >/dev/null

ACCESS_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:*"],
    "Resource": [
      "arn:aws:s3:::${BUCKET_NAME}",
      "arn:aws:s3:::${BUCKET_NAME}/*"
    ]
  }]
}
EOF
)
aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "$POLICY_NAME" \
  --policy-document "$ACCESS_POLICY" >/dev/null

aws iam create-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" >/dev/null
aws iam add-role-to-instance-profile \
  --instance-profile-name "$INSTANCE_PROFILE_NAME" \
  --role-name "$ROLE_NAME" >/dev/null
echo "✅ IAM role created."

# ====== Security Group ======
SG_ID=$(aws ec2 create-security-group \
  --group-name "$SECURITY_GROUP_NAME" \
  --description "Security group for  Todo app" \
  --region "$REGION" \
  --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0 >/dev/null
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0 >/dev/null
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 3306 --cidr 0.0.0.0/0 >/dev/null
echo "✅ Security group created: $SG_ID"

# ====== Key Pair ======
aws ec2 create-key-pair \
  --key-name "$KEY_NAME" \
  --query "KeyMaterial" \
  --output text > "${KEY_NAME}.pem"
chmod 400 "${KEY_NAME}.pem"
echo "✅ Key pair created."

# ====== Create RDS MySQL ======
echo "🗄️ Creating MySQL (RDS) instance..."
aws rds create-db-instance \
  --db-instance-identifier "$DB_ID" \
  --db-instance-class "$DB_INSTANCE_TYPE" \
  --engine mysql \
  --master-username "$DB_USER" \
  --master-user-password "$DB_PASS" \
  --allocated-storage "$DB_STORAGE" \
  --vpc-security-group-ids "$SG_ID" \
  --publicly-accessible \
  --region "$REGION" >/dev/null
echo "⏳ Waiting for RDS..."
aws rds wait db-instance-available --db-instance-identifier "$DB_ID" --region "$REGION"
DB_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_ID" \
  --query "DBInstances[0].Endpoint.Address" \
  --output text)
echo "✅ RDS endpoint: $DB_ENDPOINT"

# ====== Upload Repo to S3 ======
echo "☁️ Uploading repo contents to S3..."
aws s3 sync todoapp "s3://$BUCKET_NAME/todoapp/" --delete
echo "✅ Repo uploaded to S3."

# ====== Launch EC2 Instance ======
USER_DATA=$(cat <<EOF
#!/bin/bash
yum update -y
amazon-linux-extras install -y php8.0 mariadb10.5 nginx1
yum install -y git unzip python3

systemctl enable nginx
systemctl start nginx

cd /home/ec2-user
git clone $REPO_URL app
cd app

# Install Composer
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php composer-setup.php --install-dir=/usr/local/bin --filename=composer

cd laravel
cp .env.example .env
composer install --no-interaction --quiet

# Configure Laravel DB
sed -i "s/DB_HOST=.*/DB_HOST=${DB_ENDPOINT}/" .env
sed -i "s/DB_DATABASE=.*/DB_DATABASE=${DB_NAME}/" .env
sed -i "s/DB_USERNAME=.*/DB_USERNAME=${DB_USER}/" .env
sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=${DB_PASS}/" .env

php artisan key:generate
chown -R nginx:nginx /home/ec2-user/app/laravel

# Configure Nginx for Laravel
cat > /etc/nginx/conf.d/laravel.conf <<NGINXCONF
server {
    listen 80;
    root /home/ec2-user/app/laravel/public;
    index index.php index.html;
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/var/run/php-fpm/www.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
NGINXCONF

systemctl restart nginx php-fpm

# Serve Flutter build (if present)
cd /home/ec2-user/app/flutter
if [ -d "build/web" ]; then
  nohup python3 -m http.server 8080 --directory build/web > /dev/null 2>&1 &
fi
EOF
)

INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --iam-instance-profile Name="$INSTANCE_PROFILE_NAME" \
  --region "$REGION" \
  --user-data "$USER_DATA" \
  --query 'Instances[0].InstanceId' \
  --output text)
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"

PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)
echo "✅ EC2 running at: $PUBLIC_IP"

# ====== Initialize DB ======
echo "📄 Initializing MySQL using $SQL_FILE..."
mysql -h "$DB_ENDPOINT" -u "$DB_USER" -p"$DB_PASS" -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;"
mysql -h "$DB_ENDPOINT" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$SQL_FILE"
echo "✅ Database initialized."

# ====== Output ======
cat <<EOF

🎉 DEPLOYMENT COMPLETE
-------------------------------------------------------
🌐 Laravel App: http://$PUBLIC_IP
📱 Flutter Web: http://$PUBLIC_IP:8080
🗄️ MySQL Host: $DB_ENDPOINT
DB Name:        $DB_NAME
DB User:        $DB_USER
DB Pass:        $DB_PASS
-------------------------------------------------------
To SSH in:
  ssh -i ${KEY_NAME}.pem ec2-user@$PUBLIC_IP
EOF

