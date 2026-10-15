#!/usr/bin/env bash
set -euo pipefail

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
BUCKET=${1:-pcbackup-$ACCOUNT-us-east-1}
CONFIG_FILE=${2:-config/lifecycle.json}

echo "=== Ap dung Lifecycle cho bucket: $BUCKET ==="
aws s3api put-bucket-lifecycle-configuration \
  --bucket "$BUCKET" \
  --lifecycle-configuration "file://$CONFIG_FILE"

echo "=== Doc lai cau hinh Lifecycle ==="
aws s3api get-bucket-lifecycle-configuration --bucket "$BUCKET"

echo "=== Doi chieu danh sach Rule ID ==="
echo -n "Tren S3 : "
aws s3api get-bucket-lifecycle-configuration --bucket "$BUCKET" --query "Rules[].ID" --output text
echo "Trong file:"
grep '"ID"' "$CONFIG_FILE"
