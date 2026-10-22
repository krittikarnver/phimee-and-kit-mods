# ใช้ Claude Code ผ่าน tmux หรือ herdr + Remote Control

ให้ Claude Code ของแต่ละ repo รันค้างไว้ใน tmux หรือ herdr บน Mac แล้วคุยต่อได้จากทุกที่

- อยู่ห่างคอม: คุยผ่านแอป Claude บนมือถือ (Remote Control)
- กลับมาที่คอม: คุยต่อใน Claude desktop แท็บ Code
- ติดปัญหา: attach เข้า tmux session นั้นตรงๆ (ที่คอม หรือ ssh จากมือถือ)

คู่มือนี้บอกขั้นตอนอย่างเดียว ไม่มี script ติดตั้งให้ ทุกไฟล์ที่แก้เป็นของเครื่องคุณเอง อ่านก่อนวาง

ข้อ 2–4 เป็นของ tmux ถ้าใช้ herdr ให้ทำข้อ 7 แทน

## 1. Claude Code เปิด Remote Control เองทุก session

ใน `~/.claude/settings.json`

```json
{
  "remoteControlAtStartup": true
}
```

session ที่เปิดอยู่แล้วเปิดได้ด้วย `/rc`

## 2. `~/.tmux.conf`

```tmux
# Claude Code tracks focus through these (reattach after changing)
set -g focus-events on
# let Claude Code's notifications reach the outer terminal
set -g allow-passthrough on
# more scrollback to read back over ssh
set -g history-limit 50000
```

โหลดเข้า tmux ที่รันอยู่: `tmux source-file ~/.tmux.conf` (`focus-events` มีผลตอน attach ใหม่ `history-limit` มีผลกับ window ที่สร้างใหม่)

notification ของ Claude Code จะขึ้นที่ Mac เฉพาะตอนที่ attach อยู่ใน terminal ที่รับ notification (Ghostty, iTerm2, kitty) ถ้าคุยผ่าน Remote Control ดูข้อความในแชทแทน

## 3. `~/.zshrc`: เปิด session คำสั่งเดียว

```zsh
# claude in a tmux session named after this folder; attaches if it already runs
cc() {
  local name="${1:-$(basename "$PWD")}"
  tmux new -A -s "$name" -c "$PWD" claude --name "$name"
}
# same, but continue the folder's last conversation
ccc() {
  local name="${1:-$(basename "$PWD")}"
  tmux new -A -s "$name" -c "$PWD" claude --continue
}
```

`cc` ทับชื่อ `cc` (C compiler) เฉพาะใน shell ที่พิมพ์เอง script กับ `make` ไม่โดน ถ้าไม่อยากทับให้เปลี่ยนชื่อ

## 4. ใช้งานประจำวัน

| ทำอะไร | คำสั่ง |
|---|---|
| เปิดหรือกลับเข้า session ของ repo | `cd <repo> && cc` |
| ออกจาก tmux โดยให้ Claude รันต่อ | `Ctrl-b d` |
| ดู session ทั้งหมด | `tmux ls` |
| กลับเข้า session | `tmux a -t <ชื่อ>` |
| สลับ session ตอนอยู่ใน tmux | `Ctrl-b s` |

`cc` ใช้จากใน tmux ไม่ได้ (tmux ไม่ซ้อน session) ให้ใช้ `Ctrl-b s` แทน

อัปเดต plugin แล้ว ใช้ `/kit-update:reload` พิมพ์ `/reload-plugins` ให้ทุก session ที่ว่างอยู่ได้ในคำสั่งเดียว (ต้องติดตั้ง kit-update)

## 5. ssh จากมือถือ (ไม่บังคับ)

ใช้ตอนต้อง attach tmux จากข้างนอก ผ่าน [Tailscale](https://tailscale.com) และแอป ssh บนมือถือ (เช่น Moshi)

1. ติดตั้ง Tailscale บน Mac และมือถือ login บัญชีเดียวกัน
2. เปิด Remote Login: System Settings → General → Sharing → Remote Login
3. ใส่ public key ของมือถือใน `~/.ssh/authorized_keys`
4. ให้ sshd รับเฉพาะ Tailscale และ key เท่านั้น สร้าง `/etc/ssh/sshd_config.d/100-tailscale-only.conf` (แทน `<user>` ด้วยชื่อ user บน Mac)

   ```
   AllowUsers <user>@100.64.0.0/10 <user>@fd7a:115c:a1e0::/48
   PasswordAuthentication no
   KbdInteractiveAuthentication no
   PermitRootLogin no
   ```

5. ตรวจ config ก่อนใช้: `sudo sshd -t` (ไม่มี output แปลว่าผ่าน)
6. ต่อจากมือถือไปที่ IP หรือชื่อ MagicDNS ของ Mac ใน Tailscale แล้ว `tmux a -t <ชื่อ>` (herdr: `herdr`)

## 6. กัน Mac sleep

ถ้า Mac sleep ทั้ง Remote Control และ ssh จะหลุด ใช้แอปอย่าง Amphetamine หรือ `caffeinate -s` (ทำงานตอนเสียบไฟ) ให้เครื่องตื่นตอนอยู่ห่างคอม

## 7. ใช้ herdr แทน tmux

[herdr](https://herdr.dev) เป็น terminal workspace manager ที่ทำมาสำหรับ coding agent รู้ว่า Claude ใน workspace ไหนกำลังทำงานหรือรอคำตอบ ถ้าใช้ herdr ให้ทำข้อนี้แทนข้อ 2–4 ส่วนข้อ 1, 5, 6 ใช้เหมือนเดิม

1. ติดตั้ง herdr ตามหน้าเว็บ แล้วให้ herdr อ่านสถานะของ Claude Code ได้

   ```sh
   herdr integration install claude
   ```

   เปิด `herdr` ครั้งแรกจะถามว่าจะให้แจ้งเตือนแบบไหน

2. `~/.zshrc` (ต้องมี `jq`)

   ```zsh
   # claude in a herdr workspace named after this folder; jumps to it if it already exists
   _herdr_claude() {
     local name="$1" cmd="$2" list ws out
     list=$(herdr workspace list) || return
     ws=$(jq -r --arg n "$name" '.result.workspaces[] | select(.label == $n) | .workspace_id' <<<"$list" | head -n 1)
     if [[ -n "$ws" ]]; then
       herdr workspace focus "$ws" >/dev/null
     else
       out=$(herdr workspace create --cwd "$PWD" --label "$name" --focus) || return
       herdr pane run "$(jq -r '.result.root_pane.pane_id' <<<"$out")" "$cmd" >/dev/null
     fi
     [[ -n "$HERDR_ENV" ]] || herdr   # outside herdr: open it
   }
   cc() {
     local name="${1:-$(basename "$PWD")}"
     _herdr_claude "$name" "claude --name ${(q)name}"
   }
   # same, but continue the folder's last conversation
   ccc() {
     local name="${1:-$(basename "$PWD")}"
     _herdr_claude "$name" "claude --continue"
   }
   ```

   herdr ต้องเปิดอยู่ก่อน ถ้ายังไม่ได้เปิด ให้พิมพ์ `herdr` สักครั้ง ต่างจาก tmux ตรงที่ `cc` ใช้จากใน herdr ได้ ถ้ามี workspace ของ repo นั้นอยู่แล้วจะกระโดดไปที่ workspace นั้น ถ้ายังไม่มีจะสร้างใหม่

3. ใช้งานประจำวัน (คีย์ตั้งต้นของ herdr ดูทั้งหมดได้ด้วย `herdr --default-config`)

   | ทำอะไร | คำสั่ง |
   |---|---|
   | เปิดหรือกลับไปที่ workspace ของ repo | `cd <repo> && cc` |
   | ออกจาก herdr โดยให้ Claude รันต่อ | `Ctrl-b q` |
   | เลือก workspace | `Ctrl-b w` |
   | กลับเข้า herdr | `herdr` |

   `/kit-update:reload` ใช้กับ herdr ได้เหมือนกัน

## ใช้คู่กับ kit-checkpoint

ทำต่อเองได้สูงสุด 5 รอบ แล้วรอผู้ใช้ ตอบอะไรก็ได้จากมือถือ (เช่น "ทำต่อ") ก็เริ่มนับใหม่ เพราะข้อความผ่าน Remote Control นับเป็นคนตอบ
