# phimee-and-kit-mods

Claude Code mods ที่พี่หมีกับกิตทำด้วยกัน ทำขึ้นจากปัญหาที่เจอจริงตอนใช้ Claude ทุกวัน

## ติดตั้ง

พิมพ์ใน Claude Code (terminal):

```
/plugin marketplace add krittikarnver/phimee-and-kit-mods
/plugin install kit-time@phimee-and-kit-mods
/plugin install kit-usage@phimee-and-kit-mods
/plugin install kit-scrutinize@phimee-and-kit-mods
```

เลือกติดตั้งเฉพาะตัวที่อยากใช้ก็ได้ แต่ละตัวทำงานแยกกัน

## Mods

### kit-time

ให้ Claude รู้ว่าตอนนี้วันอะไร กี่โมงตามเวลาไทย และห่างจากข้อความก่อนหน้านานแค่ไหน เกิดจากที่คุยกันอยู่ดีๆ แล้ว Claude ไม่รู้ว่าผ่านไปข้ามคืนแล้ว

- ทุกครั้งที่ส่งข้อความ แนบเวลาไทย (พ.ศ./ค.ศ.) และระยะห่างจากข้อความก่อนหน้าไปให้ Claude แบบที่คนไม่เห็น
- แถบเหนือช่องพิมพ์: `🕰 ข้อความล่าสุด 18:24 · 5 นาทีที่แล้ว · ตอนนี้ 18:29`

### kit-usage

ให้ Claude รู้ว่า context ของ session ใช้ไปเท่าไหร่ และ rate limit ถึงไหนแล้ว พอใกล้โดน compact ก็เตือนให้จดเรื่องสำคัญไว้ก่อน จะได้ไม่ลืมกลางทาง

- ทุกครั้งที่ส่งข้อความ แนบให้ Claude ว่า context ใช้ไปกี่ % และ rate limit (5 ชม. / 7 วัน) ถึงไหนแล้ว พร้อมเวลารีเซ็ต (เวลาไทย)
- ถ้า context เกิน 85% บอก Claude ให้เตือนก่อนโดน compact และเด้ง toast เตือนหนึ่งครั้ง
- แถบเหนือช่องพิมพ์: `📊 context 72% (144k/200k) · 5 ชม. 41% รีเซ็ต 15:00`

### kit-scrutinize

คำสั่งเดียวแทน prompt ยาวที่ต้องพิมพ์ทุกครั้งหลังเขียน spec หรือ plan

- `/scrutinize-loop <ไฟล์ spec หรือ plan>` รีวิวด้วย subagent `scrutinizer` แล้วแก้ไฟล์ตาม feedback ทันที
- ทำอย่างน้อย 3 รอบ ถ้ารอบล่าสุดยังมี blocker หรือ major ทำต่อทีละรอบจนไม่เหลือ ทางแก้ของรอบสุดท้ายจะได้ถูกตรวจด้วย (หยุดที่รอบ 8 แล้วถามผู้ใช้)
- เปิด subagent ใหม่ทุกรอบ รอบแรกรีวิวเต็ม รอบต่อไปข้ามข้อ "มีทางที่ง่ายกว่านี้ไหม"
- ถ้า verdict เป็น `rework` หรือ `reject` หยุดแล้วถามผู้ใช้ก่อน ไม่ออกแบบใหม่เอง
- subagent อ่านไฟล์ได้อย่างเดียว แก้ไฟล์ไม่ได้

ตัวรีวิวใช้ [scrutinize skill ของ 9arm](https://github.com/thananon/9arm-skills/tree/main/skills/engineering/scrutinize) ติดตั้ง kit-scrutinize แล้ว plugin `9arm-skills` จะถูกติดตั้งให้อัตโนมัติ ดึงจาก [repo ของ 9arm](https://github.com/thananon/9arm-skills) ตรงๆ และอัปเดตตามต้นฉบับ ขอบคุณที่แบ่งปันครับ

## พัฒนา

```
claude --plugin-dir ./plugins/kit-time
claude plugin validate ./plugins/kit-time
claude plugin test ./plugins/kit-time
```

## License

[MIT](LICENSE) ยกเว้น 9arm-skills ซึ่งไม่ได้อยู่ใน repo นี้ เป็นของเจ้าของ repo ต้นฉบับ
