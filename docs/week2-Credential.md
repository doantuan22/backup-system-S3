## 1. Nguyên tắc

1. Credential Learner Lab (access key, secret key, session token) là bí mật. Chỉ nằm ở **một nơi duy nhất** trên máy cá nhân, **ngoài thư mục repo**.
2. **Không bao giờ** đưa credential vào: Git (file, commit, lịch sử), ảnh chụp màn hình, tài liệu báo cáo, chat, email, ghi chú, README.
3. Credential **tạm thời**: hết hạn sau khoảng 4 giờ hoặc khi lab dừng. Mỗi lần Start Lab lại có khối mới, khối cũ vô hiệu.
4. Mỗi người dùng credential của tài khoản mình. **Không gửi credential cho nhau.**
5. Công cụ (rclone, AWS CLI) **đọc credential từ file chung**, không ghi khóa vào cấu hình công cụ hay script.
6. Tham số riêng của từng tài khoản (tên bucket, ARN key) nằm trong file cấu hình **không chứa credential**.

## 2. Credential nằm ở đâu

| Nơi | Vị trí | Ghi chú |
|---|---|---|
| Máy cá nhân (Windows) | `C:\Users\<tên>\.aws\credentials` | file **không đuôi**, mục `[labrole]` |
| Máy cá nhân (macOS/Linux) | `~/.aws/credentials` | mục `[labrole]` |
| AWS CloudShell | tự có sẵn của phiên đăng nhập | không cần cập nhật; hết hạn thì mở lại CloudShell |
| Trong repo | **không có** | `.gitignore` chặn |

Nội dung file có dạng (giá trị thật lấy từ Learner Lab, không ghi vào tài liệu này):

```
[labrole]
aws_access_key_id=<khóa truy cập>
aws_secret_access_key=<khóa bí mật>
aws_session_token=<session token, rất dài>
```

Rclone đọc file này nhờ cấu hình remote `env_auth=true` và `profile=labrole`:

```
rclone config create s3lab s3 provider=AWS env_auth=true profile=labrole region=us-east-1 no_check_bucket=true
```

Cấu hình remote **không chứa khóa bí mật**, nhưng vẫn không commit `rclone.conf`.

## 3. Lấy và cập nhật credential (làm mỗi lần lab hết hạn)

1. Vào Learner Lab, bấm **Start Lab**, chờ chấm xanh.
2. Bấm **AWS Details**, rồi **Show** ở mục *AWS CLI*. Copy **cả khối** 3 dòng.
3. Mở file credentials bằng Notepad (PowerShell):
   ```
   notepad (Resolve-Path ~\.aws\credentials)
   ```
4. **Xóa hết** nội dung cũ, dán khối mới, sửa dòng đầu `[default]` thành `[labrole]`, lưu (Ctrl+S).
5. Kiểm tra kết nối:
   ```
   rclone lsf s3lab:pcbackup-771764220929-us-east-1 --max-depth 1
   ```
   Chạy không báo lỗi credential là cập nhật thành công.
6. Đóng Notepad. Không để khối credential trong clipboard history, chat hay file nào khác.

Lưu ý:
- Luôn dán **đè cả khối**, không sửa từng dòng (dễ lẫn khóa cũ với token mới).
- File phải tên đúng `credentials`. Windows hay thêm `.txt`: khi lưu bằng Notepad chọn *Save as type: All files* và gõ `credentials`. Bật *View → File name extensions* để kiểm tra.
- Mở PowerShell thường, không chạy bằng quyền Administrator, để `~` trỏ đúng thư mục người dùng.
- Tên mục `[labrole]` phải trùng `profile=labrole` trong remote rclone. Nếu để `[default]`, rclone báo `failed to get shared config profile, labrole`.

## 4. Nhận biết lỗi credential và cách xử lý

| Thông báo | Nguyên nhân | Cách xử lý |
|---|---|---|
| `failed to get shared config profile, labrole` | file không có mục `[labrole]`, sai tên file hoặc sai thư mục | kiểm tra bằng các lệnh ở mục 5 |
| `ExpiredToken` / `The security token included in the request is expired` | credential hết hạn | làm lại mục 3 |
| `InvalidToken` / `InvalidAccessKeyId` / `SignatureDoesNotMatch` | dán thiếu, dán lẫn khóa cũ và mới, hoặc sai ký tự | xóa sạch file, dán lại cả khối |
| `AccessDenied` | credential còn hạn nhưng LabRole không có quyền thao tác đó | không phải lỗi credential; báo người hỗ trợ kèm nguyên văn lỗi |

## 5. Kiểm tra file credentials (không lộ khóa)

```
dir ~\.aws
Select-String -Path ~\.aws\credentials -Pattern "^\["
```

- Lệnh 1: phải thấy một file tên `credentials` (không `.txt`).
- Lệnh 2: chỉ in các dòng bắt đầu bằng `[`, phải có `[labrole]`. Lệnh này không in ra khóa hay token.

**Không** dùng `type`, `cat` hay `Get-Content` trên file này khi đang chụp màn hình hoặc chia sẻ màn hình.

## 6. Kiểm thử quy trình: tạo lỗi có chủ đích rồi phục hồi

Làm một lần để có bằng chứng và quen với lỗi.

1. Sao lưu file:
   ```
   Copy-Item ~\.aws\credentials ~\.aws\credentials.bak
   ```
2. Mở file, đổi vài ký tự ở giữa dòng token, lưu.
3. Chạy thử, phải thấy lỗi như bảng ở mục 4:
   ```
   rclone lsf s3lab:pcbackup-771764220929-us-east-1 --max-depth 1
   ```
4. Khôi phục và chạy lại, phải thành công:
   ```
   Copy-Item ~\.aws\credentials.bak ~\.aws\credentials -Force
   rclone lsf s3lab:pcbackup-771764220929-us-east-1 --max-depth 1
   ```
5. Xóa bản sao (nó chứa credential):
   ```
   Remove-Item ~\.aws\credentials.bak
   ```

