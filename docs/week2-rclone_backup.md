Backup bằng rclone lên S3 (SSE-KMS + Versioning)

## 1. Mục tiêu

Chứng minh chức năng lõi chạy thật trên AWS Learner Lab:

1. Backup dữ liệu từ máy cá nhân lên S3 bằng rclone.
2. Dữ liệu được mã hóa SSE-KMS bằng khóa `pc-backup`.
3. Lần chạy không có thay đổi thì không upload lại (backup tăng dần).
4. File bị sửa thì S3 sinh version mới (versioning).
5. File tạm (`*.tmp`) bị loại khỏi backup.
6. File lớn upload bằng multipart.
7. Dữ liệu trên S3 trùng khớp từng byte với dữ liệu gốc.

## 2. Điều kiện trước khi chạy

- Gói 1 đã xong (lifecycle, tag bucket và khóa KMS).
- Credential Learner Lab nằm trong `C:\Users\<tên>\.aws\credentials`, mục `[labrole]`. File này **không** nằm trong repo và không bao giờ commit. Hết hạn (khoảng 4 giờ) thì lấy khối mới ở *AWS Details → Show AWS CLI* và dán đè.
- rclone đã cài trên máy; `rclone version` chạy được.

## 3. Thiết lập remote `s3lab`

Chạy trong PowerShell trên máy cá nhân.

```
rclone config create s3lab s3 provider=AWS env_auth=true profile=labrole region=us-east-1 no_check_bucket=true
rclone config update s3lab server_side_encryption=aws:kms sse_kms_key_id=arn:aws:kms:us-east-1:771764220929:key/0914c6c4-d20e-48b5-8773-f6427087acc2
rclone listremotes
rclone lsf s3lab:pcbackup-771764220929-us-east-1 --max-depth 1
```

Giải thích:

- `env_auth=true` + `profile=labrole`: rclone đọc credential từ `~/.aws/credentials`, không lưu khóa vào cấu hình rclone.
- `server_side_encryption=aws:kms` + `sse_kms_key_id`: chỉ rõ mã hóa SSE-KMS bằng đúng khóa `pc-backup`, đồng thời để rclone biết ETag của S3 không còn là MD5 (xem mục 8).
- `no_check_bucket=true`: rclone không cố tạo bucket (LabRole chỉ làm việc với bucket đã có).
- Cấu hình remote không chứa khóa bí mật; vẫn **không** commit `rclone.conf`.

Kiểm tra mã hóa mặc định của bucket (CloudShell):

```
aws s3api get-bucket-encryption --bucket pcbackup-771764220929-us-east-1
```

## 4. Chuẩn bị dữ liệu thử

```
mkdir D:\backup-system-S3\testdata\docs
mkdir D:\backup-system-S3\testdata\photos
mkdir D:\backup-system-S3\logs
"bao cao tuan 1" | Set-Content D:\backup-system-S3\testdata\docs\baocao.txt
"ghi chu" | Set-Content D:\backup-system-S3\testdata\docs\ghichu.txt
"file tam" | Set-Content D:\backup-system-S3\testdata\docs\rac.tmp
[System.IO.File]::WriteAllBytes("D:\backup-system-S3\testdata\photos\lon.bin", (New-Object byte[] 20971520))
dir D:\backup-system-S3\testdata -Recurse
```

| File | Mục đích |
|---|---|
| `docs\baocao.txt` | file nhỏ, sẽ bị sửa để sinh version mới |
| `docs\ghichu.txt` | file nhỏ không đổi |
| `docs\rac.tmp` | thử loại trừ file tạm |
| `photos\lon.bin` (20 MB) | thử upload multipart |

## 5. Ba lần chạy backup

Mỗi lệnh `rclone copy` là một dòng. Dùng `copy`, không dùng `sync`, để không xóa dữ liệu trên S3 khi file bị xóa ở máy (giữ nguyên mục đích versioning).

Ý nghĩa tham số:

| Tham số | Ý nghĩa |
|---|---|
| `--exclude "*.tmp"` | bỏ qua file tạm |
| `--s3-upload-cutoff 8M --s3-chunk-size 8M` | file lớn hơn 8 MB được cắt khúc 8 MB và upload multipart |
| `-v` | ghi chi tiết từng file |
| `--log-file ...` | ghi log làm bằng chứng |

### Lần 1 – backup đầu tiên

```
rclone copy D:\backup-system-S3\testdata s3lab:pcbackup-771764220929-us-east-1/pc-tuan-w2 --exclude "*.tmp" --s3-upload-cutoff 8M --s3-chunk-size 8M -v --log-file D:\backup-system-S3\logs\backup1.log
Get-Content D:\backup-system-S3\logs\backup1.log
```

Kết quả mong đợi: `Copied (new)` cho `baocao.txt`, `ghichu.txt`, `lon.bin`; không có `rac.tmp`.

Kết quả thực tế: *(dán trích đoạn `evidence/week2/logs/backup1.txt`)*

### Lần 2 – không thay đổi gì

```
rclone copy D:\backup-system-S3\testdata s3lab:pcbackup-771764220929-us-east-1/pc-tuan-w2 --exclude "*.tmp" --s3-upload-cutoff 8M --s3-chunk-size 8M -v --log-file D:\backup-system-S3\logs\backup2.log
Get-Content D:\backup-system-S3\logs\backup2.log
```

Kết quả mong đợi: không upload lại file nào.

Kết quả thực tế: `INFO : There was nothing to transfer` – `Transferred: 0 B / 0 B`, `Checks: 3 / 3`.

### Lần 3 – sửa một file

```
Add-Content D:\backup-system-S3\testdata\docs\baocao.txt "them dong moi lan 3"
rclone copy D:\backup-system-S3\testdata s3lab:pcbackup-771764220929-us-east-1/pc-tuan-w2 --exclude "*.tmp" --s3-upload-cutoff 8M --s3-chunk-size 8M -v --log-file D:\backup-system-S3\logs\backup3.log
Get-Content D:\backup-system-S3\logs\backup3.log
```

Kết quả mong đợi: chỉ `docs/baocao.txt` được `Copied (replaced existing)`.

Kết quả thực tế: *(dán trích đoạn `evidence/week2/logs/backup3.txt`)*

## 6. Kiểm thử phía AWS

Các lệnh `aws s3api` chạy trong CloudShell (us-east-1). Trước đó chạy `aws sts get-caller-identity` để ảnh bằng chứng thấy Account ID.

### 6a. Versioning – file đã sửa có 2 version

```
aws s3api list-object-versions --bucket pcbackup-771764220929-us-east-1 --prefix pc-tuan-w2/docs/baocao.txt --query "Versions[].[Key,VersionId,IsLatest,LastModified]" --output table
```

Kết quả: 2 version – bản 2026-10-14T15:31:03Z là `IsLatest = True` (lần 3), bản 2026-10-14T15:29:41Z là bản cũ (lần 1). Đạt.

### 6b. Mã hóa SSE-KMS

```
aws s3api head-object --bucket pcbackup-771764220929-us-east-1 --key pc-tuan-w2/docs/baocao.txt
```

Kết quả: `ServerSideEncryption: aws:kms`, `SSEKMSKeyId: arn:aws:kms:us-east-1:771764220929:key/0914c6c4-d20e-48b5-8773-f6427087acc2`, `ContentLength: 37`. Đạt.

### 6c. File lớn upload multipart

```
aws s3api head-object --bucket pcbackup-771764220929-us-east-1 --key pc-tuan-w2/photos/lon.bin --query ETag
```

Kết quả: ETag `748e53b8b6ec29471b961d596464086d-3` – đuôi `-3` cho biết 3 phần (multipart). Với SSE-KMS, ETag không phải MD5 nên phần trước dấu `-` không dùng để so sánh nội dung. Đạt.

### 6d. File `.tmp` không lên bucket

```
rclone lsf s3lab:pcbackup-771764220929-us-east-1/pc-tuan-w2 --recursive
```

Kết quả: chỉ có `docs/baocao.txt`, `docs/ghichu.txt`, `photos/lon.bin` (cùng hai thư mục `docs/`, `photos/`); không có `rac.tmp`. Đạt.

### 6e. Toàn vẹn từng byte

Chạy trong PowerShell trên máy cá nhân (cần truy cập ổ D):

```
rclone check D:\backup-system-S3\testdata s3lab:pcbackup-771764220929-us-east-1/pc-tuan-w2 --exclude "*.tmp" --one-way --download
```



## 7. Tổng hợp kết quả

| Yêu cầu | Cách kiểm | Kết quả |
|---|---|---|
| Backup lên S3 chạy thật | log lần 1, `rclone lsf` | Đạt |
| Backup tăng dần | log lần 2 (`nothing to transfer`) | Đạt |
| Versioning | 6a: 2 version, 1 bản `IsLatest` | Đạt |
| Mã hóa SSE-KMS đúng khóa | 6b | Đạt |
| Multipart | 6c: ETag `-3` | Đạt |
| Loại trừ `.tmp` | 6d | Đạt |
| Toàn vẹn dữ liệu | 6e `rclone check --download` | *(điền sau khi chạy)* |

## 8. Lỗi gặp phải và cách khắc phục

**Hiện tượng:** lần chạy đầu rclone báo `corrupted on transfer: md5 hashes differ` cho file nhỏ, và `multipart upload corrupted: Etag differ` cho `lon.bin`; rclone tự xóa bản vừa upload. Log: `evidence/week2/logs/backup1-failed.txt`.

**Nguyên nhân:** bucket mã hóa SSE-KMS nên ETag mà S3 trả về không còn là MD5 của nội dung. Sau mỗi lần upload rclone so MD5 của file gốc với ETag, thấy khác nhau nên báo lỗi dù dữ liệu không hỏng.

**Cách khắc phục:**

1. Khai báo `server_side_encryption=aws:kms` và `sse_kms_key_id` trong remote để rclone biết ETag không phải MD5 (mục 3).
2. Xác nhận toàn vẹn bằng phương pháp độc lập: `rclone check --one-way --download` tải dữ liệu từ S3 về so từng byte (mục 6e).
3. Dọn dữ liệu thử của lần lỗi (xóa mọi version và delete marker dưới tiền tố `pc-tuan`) rồi chạy lại từ lần 1 để bằng chứng versioning sạch.

Lần chạy lỗi cũng để lại version và delete marker thừa trong bucket vì rclone upload rồi xóa; đó là lý do phải dọn trước khi đo số version.

