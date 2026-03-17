<img width="1793" height="83" alt="Screenshot 2026-03-17 at 14 25 31" src="https://github.com/user-attachments/assets/c0d9aa3b-085a-4a6d-8831-ef6c440856ad" />

# Hướng Dẫn Cài Đặt Statusline

## Cách 1: Cài Đặt Trực Tiếp (Đơn Giản)

### Bước 1: Tải về
```bash
# Tải file statusline.sh từ GitHub repo của bạn
curl -o ~/.claude/statusline.sh https://raw.githubusercontent.com/huybq95/claude-statusline/main/statusline.sh

# Cho phép thực thi
chmod +x ~/.claude/statusline.sh
```

Xong! Claude Code sẽ tự động đọc file này.

---

## Cách 2: Clone Repo + Symlink (Đề Xuất)

### Bước 1: Clone repo
```bash
git clone https://github.com/huybq95/claude-statusline.git ~/claude-statusline
```

### Bước 2: Tạo symlink
```bash
ln -sf ~/claude-statusline/statusline-command.sh ~/.claude/~/.claude/statusline-command.sh
chmod +x ~/claude-statusline/statusline-command.sh
```

**Lợi ích:** Khi bạn cập nhật repo và chạy `git pull`, statusline sẽ tự động cập nhật.

---

## Cấu Trúc Thư Mục

```
~/.claude/
└── statusline-command.sh    # File statusline (hoặc symlink trỏ đến repo)
```

**Vị trí bắt buộc:** `~/.claude/statusline.sh`

---

## Kiểm Tra

```bash
# Kiểm tra file có tồn tại không
ls -la ~/.claude/statusline-command.sh

# Nếu dùng symlink, sẽ thấy:
# ~/.claude/statusline-command.sh -> /Users/<user>/claude-statusline/statusline-command.sh
```

---

## Cập Nhật

### Nếu dùng Cách 1 (tải trực tiếp):
```bash
curl -o ~/.claude/statusline-command.sh https://raw.githubusercontent.com/huybq95/claude-statusline/main/statusline-command.sh
```

### Nếu dùng Cách 2 (symlink):
```bash
cd ~/claude-statusline
git pull
```

---

## Sử Dụng Trên Máy Khác

Chỉ cần lặp lại Bước 1 và 2 của Cách 2 trên máy mới.

---

## Không Cần Cấu Hình Thêm

Claude Code tự động tìm và chạy file `~/.claude/statusline-command.sh`. Không cần config gì thêm.
