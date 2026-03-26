
 Jenkins Master - Configuration Management (Ansible)

## 1. Mục đích (Purpose)
Repository này chứa các Ansible Playbooks và Roles để tự động hóa quá trình cấu hình (Configuration Management) cho máy chủ Jenkins Master (Controller) trên hạ tầng AWS EC2. Việc cấu hình tuân thủ nguyên tắc **Idempotency** và **Infrastructure as Code (IaC)**.

## 2. Giả định & Yêu cầu đầu vào (Assumptions & Prerequisites)
Để thực thi playbook này thành công, môi trường local (WSL) và remote (AWS) phải thỏa mãn các điều kiện sau:
* **Hạ tầng cơ sở:** EC2 instance (Ubuntu) đã được khởi tạo thành công bằng Terraform.
* **Xác thực SSH:** File Private Key (`.pem`) do Terraform sinh ra đã được sao chép vào máy WSL local và thiết lập quyền truy cập nghiêm ngặt (`chmod 400 <file.pem>`).
* **Network Security:** Truy cập SSH được thực hiện thông qua AWS Systems Manager (SSM) Session Manager kết hợp với `ProxyCommand`, không mở trực tiếp port 22 ra Internet (`0.0.0.0/0`).
* **Inventory:** File `inventories/dev/hosts.ini` đã được cập nhật chính xác `instance_id` của EC2 target.

## 3. Kiến trúc luồng thực thi (Architecture & System Breakdown)
Playbook được thiết kế theo cấu trúc Modular bằng Ansible Roles (`site.yaml` đóng vai trò Orchestrator). Luồng thực thi bao gồm:
1.  **`common`:** Cập nhật APT cache và cài đặt các package cơ bản.
2.  **`java`:** Cài đặt OpenJDK 17 (Yêu cầu bắt buộc của Jenkins Controller).
3.  **`docker`:** Cài đặt Docker Engine và phân quyền group cho user `ubuntu` và `jenkins`.
4.  **`jenkins`:** * Dọn dẹp các GPG keys và repository files cũ (Scorched earth cleanup).
    * Tải GPG key chuẩn (bản cập nhật 2026: `jenkins.io-2026.key`) để vượt qua cơ chế xác thực SecureApt.
    * Cài đặt package Jenkins và khởi động service.
    * *Bảo mật (Zero-Log Output):* Tải trực tiếp file `initialAdminPassword` từ server về WSL local thông qua module `fetch`, tuyệt đối không in secret ra `stdout` để phòng chống lưu vết clear-text trên logs (CWE-312).

## 4. Hướng dẫn thực thi (Execution Guide)

**Bước 1: Kiểm tra kết nối SSM Tunnel**
Đảm bảo luồng SSM đang hoạt động ngầm để forward port và cho phép kết nối SSH.

**Bước 2: Chạy Playbook**
Đứng tại thư mục gốc của phần Ansible (`04-ansible-config`), thực thi lệnh sau để chèn file cấu hình cục bộ và áp dụng playbook:
```bash
ANSIBLE_CONFIG=./ansible.cfg ansible-playbook -i inventories/dev/hosts.ini site.yaml
```

**Bước 3: Hậu kiểm và Unlock Jenkins (Post-Execution)**
1.  Ansible sẽ tải file chứa mật khẩu khởi tạo về thư mục hiện tại với tên `jenkins_initial_admin_password.txt`.
2.  **[CRITICAL]** Thêm ngay tên file này vào `.gitignore` để tránh rủi ro Secret Leakage lên hệ thống quản lý source code (Git).
3.  Đọc nội dung file bằng lệnh `cat jenkins_initial_admin_password.txt`.
4.  Mở trình duyệt truy cập `http://localhost:8080` (qua tunnel) và nhập mật khẩu để hoàn tất khởi tạo Jenkins UI.

## 5. Trade-offs đã đánh giá
* **Module `fetch` vs `slurp` + `debug`:** Chọn `fetch` để kéo thẳng file secret về máy, đánh đổi sự tiện lợi (không copy được ngay trên terminal) để đổi lấy mức độ bảo mật cao nhất (không dump biến nhạy cảm ra log CI/CD).
* **APT native vs Shell raw:** Loại bỏ hoàn toàn các lệnh bash `rm` hoặc `curl` để dùng các module `apt_repository`, `get_url`, `file (state: absent)`. Đánh đổi việc viết file YAML dài hơn để đạt được 100% tính luỹ đẳng (Idempotency) và Declarative của Ansible.

---

