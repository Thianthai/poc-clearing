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
| Console class | `YCL_CLEARING` |
| Communication scenario | `ZCS_SPORTPACKAGE_CLEARING` |
| Outbound service | `ZAPI_SPORTPACKAGE_CLEARING_REST` |

> **ข้อยกเว้น namespace** — global rule ให้ขึ้นต้น `Y` ทุก object แต่ user สั่ง
> case by case (2026-09-09) ว่า **communication scenario ใช้ `ZCS_*` และ
> outbound service ใช้ `ZAPI_*`**
>
> เหตุผล: สอง object นี้จะถูก **reassign package ไปใช้งานจริงต่อหลังจบ POC**
> ไม่ได้ถูกทิ้งไปพร้อม POC เหมือน object อื่น จึงตั้งชื่อตามระบบงานจริง
> (`SPORTPACKAGE`) ตั้งแต่แรก
>
> ที่เหลือ (package `YPOC_CLEARING`, class `YCL_CLEARING`) ยังเป็น `Y`
> ตามเดิม เพราะเป็นของ POC ล้วน

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
- **Message Dashboard ว่างเปล่าทั้งที่ได้ 202** = user ยังไม่ถูก assign กับ
  AIF recipient ไม่ใช่ว่า message ไม่เข้า → Fiori app *Assign Recipients to Users*
  (ต้องมี business catalog `SAP_CA_BC_COM_CONF_PC`)
  ทางพิสูจน์ที่ไม่พึ่ง AIF: ยิงด้วย `gc_test_run = 'false'` แล้ว query
  `ClearingAccountingDocument` ใน `I_OperationalAcctgDocItem`
- ต้องส่ง **WS-Addressing header** (`wsa:Action` + `wsa:MessageID`) ใน SOAP header
  ไม่งั้น service ตอบ error — เทียบเท่ากับติ๊ก WS-A ใน SoapUI
- Message header `ID` ต้อง **unique และไม่เกิน 35 ตัวอักษร**
- ยิงซ้ำด้วย `ID` เดิม จะโดนมองเป็น duplicate message
- ADT เติม suffix **`_REST`** ให้ outbound service แบบ HTTP อัตโนมัติ
  → ชื่อจริงคือ `ZAPI_SPORTPACKAGE_CLEARING_REST` ไม่ใช่ `ZAPI_SPORTPACKAGE_CLEARING`
  `gc_service_id` ต้องตรงกับชื่อจริง ไม่งั้น `CX_HTTP_DEST_PROVIDER_ERROR`
- Outbound service ตั้ง **HTTP Version = 1.1** (ADT default ให้มา 1.0)
- `ERROR: The selection did not return any results.` จาก
  `CX_HTTP_DEST_PROVIDER_ERROR` = หา comm arrangement ไม่เจอ
  **ยังไม่ได้ยิงออกไปเลย** ไม่ใช่ปัญหา payload — เช็ค `gc_service_id`
  ให้ตรงกับคอลัมน์ *Outbound Service ID* ใน ADT > comm scenario > tab Outbound
- **Communication arrangement ผูกกับ client** — พิสูจน์แล้ว 2026-09-09
  รันจาก client 80 ได้ `The selection did not return any results.`
  รันจาก client 100 (client ที่สร้าง arrangement ไว้) ได้ HTTP 202
  ทั้งที่ scenario id / service id เหมือนกันทุกตัวอักษร
  **`comm_system_id` ไม่จำเป็น** — ทดสอบแล้วไม่ส่งก็ผ่าน
- `create_by_comm_arrangement( )` รับ parameter เป็น fixed-length char ไม่ใช่ string
  → `comm_scenario` = `char30` · `service_id` = `char40` ·
  `comm_system_id` = `c LENGTH 60`
