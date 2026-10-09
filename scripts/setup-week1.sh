#!/usr/bin/env bash
set -euo pipefail

export AWS_DEFAULT_REGION=us-east-1
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
BUCKET=pcbackup-$ACCOUNT-us-east-1
OWNER=24110368
echo $BUCKET


# KMS key
KEY_ID=$(aws kms create-key --description "PC backup" \
  --tags TagKey=Project,TagValue=PC-Backup-S3 TagKey=Owner,TagValue=$OWNER \
  --query KeyMetadata.KeyId --output text)
aws kms create-alias --alias-name alias/pc-backup --target-key-id $KEY_ID
aws kms describe-key --key-id alias/pc-backup


# Bucket
aws s3api create-bucket --bucket $BUCKET

aws s3api put-bucket-versioning --bucket $BUCKET \
  --versioning-configuration Status=Enabled

aws s3api put-public-access-block --bucket $BUCKET \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws s3api put-bucket-ownership-controls --bucket $BUCKET \
  --ownership-controls 'Rules=[{ObjectOwnership=BucketOwnerEnforced}]'

aws s3api put-bucket-encryption --bucket $BUCKET \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"aws:kms","KMSMasterKeyID":"alias/pc-backup"},"BucketKeyEnabled":true}]}'

aws s3api put-bucket-tagging --bucket $BUCKET \
  --tagging "TagSet=[{Key=Project,Value=PC-Backup-S3},{Key=Owner,Value=$OWNER}]"


# Policy chặn truy cập không dùng TLS
cat > policy.json <<EOF
{"Version":"2012-10-17","Statement":[{"Sid":"DenyNonTLS","Effect":"Deny","Principal":"*",
 "Action":"s3:*","Resource":["arn:aws:s3:::$BUCKET","arn:aws:s3:::$BUCKET/*"],
 "Condition":{"Bool":{"aws:SecureTransport":"false"}}}]}
EOF
aws s3api put-bucket-policy --bucket $BUCKET --policy file://policy.json

# Kiểm chứng
aws s3api get-bucket-versioning --bucket $BUCKET
aws s3api get-bucket-encryption --bucket $BUCKET
aws s3api get-public-access-block --bucket $BUCKET
aws s3api get-bucket-tagging --bucket $BUCKET

# Upload để chứng minh mã hóa và versioning
dd if=/dev/urandom of=test.bin bs=1M count=2
aws s3 cp test.bin s3://$BUCKET/backup/test/test.bin
aws s3api head-object --bucket $BUCKET --key backup/test/test.bin
dd if=/dev/urandom of=test.bin bs=1M count=2
aws s3 cp test.bin s3://$BUCKET/backup/test/test.bin
aws s3api list-object-versions --bucket $BUCKET --prefix backup/test/
