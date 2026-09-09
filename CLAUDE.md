# CLAUDE.md — YPOC_CLEARING

Project instructions สำหรับ repo นี้ ใช้ร่วมกับ global rules ที่ `~/.claude/CLAUDE.md`
ถ้าขัดกัน ให้ยึด global rules เป็นหลัก

## บริบทของ project

POC เรียก SOAP API `JournalEntryBulkClearingRequest_In`
(Journal Entry – Clearing, asynchronous) จาก ABAP Cloud console class
บน S/4HANA Cloud Public Edition

- **ไม่ใช่** production RICEFW — ไม่ต้องทำ RAP, ไม่ต้องทำ UI, ไม่ต้องทำ error framework
- ขอบเขตคือ "พิสูจน์ว่ายิง API แล้ว clear เอกสารได้จริง" เท่านั้น
- ข้อมูลทดสอบ fix ใน code ทั้งหมด (constant + internal table ใน private section)

## Naming ที่ใช้ใน project นี้

| Object | ชื่อ |
|---|---|
| Package | `YPOC_CLEARING` |
| Console class | `YCL_CLEARING_RUNNER` |
| Communication scenario | `ZCS_CLEARING` |
| Outbound service | `ZOS_CLEARING_SOAP` |

> **ข้อยกเว้น namespace** — global rule ให้ขึ้นต้น `Y` ทุก object แต่ user สั่ง
> case by case (2026-09-09) ว่า **outbound service ใช้ `ZOS_*` และ
> communication scenario ใช้ `ZCS_*`** สอง object นี้เท่านั้น
> ที่เหลือ (package, class) ยังเป็น `Y` ตามเดิม

prefix ตัวแปรตาม global rules (`gc_` / `lv_` / `lo_` / `ls_` / `lt_` / `iv_` / `rv_` …)

## กฎเฉพาะ repo นี้

- **ห้ามใส่ credential ลง source code** — user / password ของ communication user
  อยู่ที่ communication arrangement เท่านั้น
  ถ้าเจอ `set_authorization_basic( )` พร้อมค่าจริงใน code ให้ทักทันที
- **ห้ามเขียนไฟล์ ABAP ลง repo** (`*.clas.abap`, `*.xml` ของ ADT object ฯลฯ)
  ส่ง code เป็น code block ใน chat ให้ผู้ใช้ copy ไปสร้างใน ADT
  `docs/05-console-class.md` เก็บได้เพราะเป็น markdown snapshot ไม่ใช่ไฟล์ serialize
- `.abapgit.xml` และ `src/**/package.devc.xml` ให้ SAP serialize มาเองตอนผู้ใช้
  link abapGit จาก ADT — Claude ห้ามเขียนล่วงหน้า
- ค่าที่ยังไม่รู้ (host, company code, เลขเอกสาร) ให้ใส่เป็น placeholder ที่เห็นชัด
  เช่น `<CHANGE_ME>` แล้วบอกผู้ใช้ว่าต้องเติมอะไรบ้าง อย่าเดาค่าจริง

## จุดที่พลาดง่าย (เจอแล้วบันทึกไว้)

- API เป็น **async** → HTTP 202 + body ว่าง ไม่ได้แปลว่าสำเร็จ
  ต้องตามผลที่ Fiori app *Message Dashboard* / AIF ด้วย Message ID
- ต้องส่ง **WS-Addressing header** (`wsa:Action` + `wsa:MessageID`) ใน SOAP header
  ไม่งั้น service ตอบ error — เทียบเท่ากับติ๊ก WS-A ใน SoapUI
- Message header `ID` ต้อง **unique และไม่เกิน 35 ตัวอักษร**
- ยิงซ้ำด้วย `ID` เดิม จะโดนมองเป็น duplicate message
- `create_by_comm_arrangement( )` รับ parameter เป็น fixed-length char ไม่ใช่ string
  → `gc_comm_scenario` ต้องเป็น `char30` และ `gc_service_id` ต้องเป็น `char40`
