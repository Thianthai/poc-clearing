# YPOC_CLEARING — POC: Journal Entry Clearing ผ่าน SOAP API

POC เรียก SOAP API **Journal Entry – Clearing (Asynchronous)**
(`JournalEntryBulkClearingRequest_In`) จาก ABAP Cloud console class
บน **SAP S/4HANA Cloud Public Edition**

- API บน SAP Business Accelerator Hub:
  <https://api.sap.com/api/JOURNALENTRYBULKCLEARINGREQUES/overview>
- ขอบเขต: console class ตัวเดียว รัน clearing ครั้งละ 1 request
  ข้อมูลทดสอบ fix ไว้ใน code ทั้งหมด (ยังไม่มี UI / ไม่มี RAP)

## ทำไมต้องเรียกแบบ "ยิง HTTP เอง"

`JournalEntryBulkClearingRequest_In` เป็น **inbound** SOAP service ของ tenant เอง
(external system → SAP) และ ABAP Cloud บน Public Edition **ไม่มี** SOAP consumer
proxy / Service Consumption Model สำหรับ SOAP

POC นี้จึงทำตัวเป็น external client: ประกอบ SOAP envelope เป็น string แล้ว POST
ผ่าน `CL_WEB_HTTP_CLIENT_MANAGER` ไปที่ endpoint ของ tenant ตัวเอง
โดยใช้ **communication arrangement** เป็นตัวเก็บ host + credential
(ไม่ hardcode รหัสผ่านใน code)

```
YCL_CLEARING  ──POST──▶  https://<host>-api.s4hana.cloud.sap
 (console class)                /sap/bc/srt/scs_ext/sap/journalentrybulkclearingreques
        │                                        │
        │ comm arrangement ZCS_SPORTPACKAGE_CLEARING          ▼
        └──────────────────────────────▶  AIF / Message Dashboard (ดูผลลัพธ์)
```

เพราะเป็น API แบบ **asynchronous** → HTTP response ที่ได้คือ `202 Accepted`
body ว่าง ไม่ได้แปลว่า clear สำเร็จ ต้องไปดูผลจริงที่ Message Dashboard
ด้วย Message ID ที่ console พิมพ์ออกมา

## ผลลัพธ์ POC — 🟡 ยิงผ่านแล้ว กำลังแก้ scope ของ clearing (2026-09-09)

ยิง SOAP API จาก ABAP Cloud console class แล้ว **clear เอกสารได้จริง**

| | |
|---|---|
| Test case | AR full clearing · customer `0001000082` · THB |
| Invoice | `9400000005` / 2026 / item 001 · +6,418.93 |
| Payment | `3300000017` / 2026 / item 005 · −6,418.93 |
| **Clearing document** | **`0100000000`** ลงวันที่ 2026-09-09 |

> ⚠️ functional ตรวจแล้วพบว่า **ยังไม่ครบ** — ต้อง clear บรรทัด
> **Deferred Output Tax** (G/L `0021082005` item 003 ของทั้งสองใบ) คู่ไปด้วย
> ขั้นตอนถัดไป: reverse `0100000000` แล้วยิงใหม่ให้ครบทั้ง 4 บรรทัด

บรรทัด G/L ที่เหลือ (bank / revenue) ไม่ต้องส่งเข้า API — ระบบสร้าง offsetting ให้เอง

### สิ่งที่พิสูจน์ได้

- ABAP Cloud เรียก inbound SOAP service ของ tenant ตัวเองได้ผ่าน
  communication arrangement โดยไม่ต้อง hardcode credential
- ประกอบ SOAP envelope + WS-Addressing header เองด้วย string template ใช้งานได้จริง
  ไม่ต้องมี consumer proxy
- รองรับ full / partial / residual clearing ครบตาม field ที่ API เปิดให้

### ข้อจำกัดที่ต้องรู้ก่อนเอาไปทำต่อ

- API **ไม่รองรับ Special G/L indicator** และ **สร้างบรรทัด bank เองไม่ได้**
  ทำได้แค่ clear open item ที่มีอยู่แล้ว
- เป็น async → ต้องมีทางตามผล (AIF Message Dashboard หรือเปิด
  outbound confirmation service)

## เอกสาร

| ไฟล์ | เนื้อหา |
|---|---|
| [docs/01-api-reference.md](docs/01-api-reference.md) | โครงสร้าง payload, field, ข้อจำกัดของ API |
| [docs/02-communication-setup.md](docs/02-communication-setup.md) | ขั้นตอน config comm scenario / arrangement |
| [docs/03-object-list.md](docs/03-object-list.md) | รายการ ABAP object + สถานะ |
| [docs/04-test-data.md](docs/04-test-data.md) | ช่องข้อมูลที่ต้อง export จากระบบมาเติม |
| [docs/05-console-class.md](docs/05-console-class.md) | snapshot source code ของ console class |
| [docs/06-data-export-sql.md](docs/06-data-export-sql.md) | ABAP SQL ดึง open item จาก released CDS view |

## การแบ่งงาน push

- **ABAP object** (class, comm scenario, outbound service) → ผู้ใช้สร้างใน ADT
  แล้ว push ผ่าน abapGit เอง
- **เอกสารทั้งหมดใน repo นี้** → Claude เป็นคน push

source of truth ของ ABAP object คือ tenant เสมอ
`docs/05-console-class.md` เป็นแค่ snapshot ไว้อ่าน ไม่ใช่ตัวจริง
