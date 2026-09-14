# 04 — Test Data ที่ต้อง export จากระบบ

ค่าทั้งหมดใน `YCL_CLEARING` ที่เขียนว่า `CHANGE_ME...` ต้องแทนด้วยค่าจริง
จาก tenant ก่อนรัน

## 1. ค่าระดับ header

| Constant ใน class | ความหมาย | ค่าที่ต้องหา |
|---|---|---|
| `gc_company_code` | company code ที่จะ post เอกสาร clearing | เช่น `1010` |
| `gc_document_type` | document type ของเอกสาร clearing | **`DA`** (customer document — ที่ใช้จริงในเคสนี้) · `AB` (G/L) · `KZ` (จ่ายเจ้าหนี้) |
| `gc_currency` | สกุลเงินของเอกสาร | ต้องตรงกับสกุลเงินของ open item |
| `gc_created_by` | ชื่อ user ที่จะติดไปกับเอกสาร | free text |
| `gc_test_run` | `true` = simulate เฉย ๆ · `false` = post จริง | เริ่มที่ `true` เสมอ |

> `DocumentDate` / `PostingDate` class คำนวณจากวันปัจจุบันให้อัตโนมัติ
> ถ้าต้องการ fix วันที่เอง แก้ที่ method `build_envelope`

## 2. Open item ที่จะ clear

**เงื่อนไข**: ต้องเป็นบรรทัดที่ยัง open อยู่จริง และผลรวมเดบิต/เครดิตของทุกบรรทัด
ที่ส่งไปต้อง **เป็นศูนย์** (กรณี full clearing)

### กรณี AP / AR (`get_apar_items`)

| Field | ที่มา | ตัวอย่าง |
|---|---|---|
| `account_type` | `K` = vendor · `D` = customer | `K` |
| `apar_account` | เลข supplier / customer | `S10300901` |
| `fiscal_year` | ปีบัญชีของเอกสารต้นทาง | `2026` |
| `acctg_doc` | เลขเอกสาร (BELNR) | `1900000959` |
| `acctg_doc_item` | เลขบรรทัด (BUZEI) | `1` |
| `partial_amount` | ใส่เมื่อทำ partial clearing เท่านั้น | เว้นว่าง = full |
| `diff_reason` | reason code ของผลต่าง | เว้นว่างได้ |

หา open item ได้จาก:
- Fiori app **Manage Supplier Line Items** / **Manage Customer Line Items**
- หรือ OData `API_OPLACCTGDOCITEMCUBE_SRV` filter `IsCleared eq false`

### กรณี G/L (`get_gl_items`)

| Field | ที่มา | ตัวอย่าง |
|---|---|---|
| `gl_account` | บัญชี G/L (ต้องเป็น open item managed) | `11001010` |
| `fiscal_year` | | `2026` |
| `acctg_doc` | | `100003875` |
| `acctg_doc_item` | | `1` |

หาได้จาก Fiori app **Manage G/L Account Line Items** (กรอง Open Items)

> **ทางลัด**: query สำเร็จรูปสำหรับดึงข้อมูลพวกนี้อยู่ที่
> [06-data-export-sql.md](06-data-export-sql.md) — เร็วกว่าไล่กดใน Fiori

## 3. รูปแบบที่สะดวกที่สุดสำหรับส่งข้อมูลมา

ส่งมาเป็นตารางแบบนี้ก็พอ:

```
company_code : 1010
doc_type     : KZ
currency     : THB

items (account_type / account / fiscal_year / document / item):
K / S10300901 / 2026 / 1900000959 / 1
K / S10300901 / 2026 / 1500000241 / 2
```

## 4. เคสทดสอบที่แนะนำ ตามลำดับ

| # | เคส | `gc_test_run` | คาดหวัง |
|---|---|---|---|
| 1 | full clearing 2 บรรทัด ยอดหักล้างกันพอดี | `true` | 202 + Message Dashboard ขึ้นเขียว |
| 2 | เคสเดิม | `false` | เกิดเอกสาร clearing จริง |
| 3 | ยิงซ้ำ item ที่ clear ไปแล้ว | `false` | error "document already cleared" |
| 4 | partial clearing | `true` → `false` | เหลือ open item ยอดคงเหลือ |

## 5. ข้อควรระวัง

- **Posting period ต้องเปิด** สำหรับ company code + วันที่ที่ post
- ถ้ายอดไม่ balance จะขึ้น error ที่ Message Dashboard ไม่ใช่ที่ HTTP response
- อย่าใช้ item ที่มี **Special G/L indicator** — API นี้ไม่รองรับ
  (ดู [01-api-reference.md](01-api-reference.md#ข้อจำกัดที่ต้องรู้ก่อนออกแบบ))
- แต่ละครั้งที่รัน class จะ generate Message ID ใหม่ให้เอง ไม่ชนกัน

## 6. รูปแบบเลขบรรทัด (`AccountingDocumentItem`)

`I_OperationalAcctgDocItem` คืนค่ามาเป็น 3 หลักมี leading zero (`001`, `002`)
แต่ payload ตัวอย่างของ SAP ใช้ `1`, `2`

ตอนทดสอบครั้งแรกให้ใส่**ตามที่ view คืนมา** (`001`) ก่อน ถ้า Message Dashboard
ฟ้องว่าหา item ไม่เจอ ค่อยลองตัด leading zero ออก

---

## 7. Test case จริง (functional ส่งให้ 2026-09-09)

เคส **AR full clearing** — chain เอกสาร

```
Sales order       JA30000116
Billing document  JA70000046
FI invoice        9400000005   FY2026
Payment document  3300000017   FY2026
```

### บรรทัดที่ส่งเข้า API (เฉพาะ FinancialAccountType = 'D')

| # | เอกสาร | FY | Item | PK | Customer | Amount (THB) | Cleared |
|---|---|---|---|---|---|---:|---|
| 1 | `9400000005` | 2026 | `001` | 01 | `0001000082` | +6,418.93 | ว่าง |
| 2 | `3300000017` | 2026 | `005` | 15 | `0001000082` | −6,418.93 | ว่าง |

รวม = **0.00** → full clearing ได้

> ⚠️ **ชุดนี้ถูกใช้ไปแล้ว** — ทั้ง 4 บรรทัด (AR 2 + deferred output tax 2)
> ถูก clear ด้วยเอกสาร **`0100000002`** เมื่อ 2026-09-09
> ถ้าจะทดสอบ partial / residual ต่อ ต้องขอ functional เตรียมชุดใหม่
> หรือ reverse `0100000002` ทิ้งเพื่อให้ open item กลับมา
>
> (`0100000000` คือรอบแรกที่ clear ไม่ครบ ถูก reverse ไปแล้ว)

### บรรทัด G/L ที่ **ต้อง** ส่งด้วย (functional ยืนยัน 2026-09-09)

**Deferred Output Tax** ต้อง clear คู่ไปกับฝั่ง AR ไม่งั้น clearing document ไม่สมบูรณ์

| # | เอกสาร | FY | Item | G/L | Amount (THB) |
|---|---|---|---|---|---:|
| 1 | `9400000005` | 2026 | `003` | `0021082005` | −419.93 |
| 2 | `3300000017` | 2026 | `003` | `0021082005` | +419.93 |

รวม = **0.00** · `IsOpenItemManaged = 'X'` ทั้งคู่

### บรรทัดที่ **ไม่** ส่ง

บรรทัด `FinancialAccountType = 'S'` ที่เหลือ — bank `0011092001`,
revenue `0021060006`, tax `0021082003`, ค่าธรรมเนียม `0011047003`
API สร้าง offsetting ให้เอง

### กับดักที่เจอตอนดึงข้อมูล

- **เลขเอกสารซ้ำข้ามปี** — `9400000005` และ `3300000017` มีทั้ง FY2025 และ FY2026
  ถ้า query ไม่กรอง `FiscalYear` จะได้เอกสารคนละใบปนมา และ FY2025 นั้น
  invoice ถูก clear ไปแล้ว (`ClearingAccountingDocument = 3300000003`)
  → **ต้องระบุ `fiscal_year` ใน payload เสมอ**
- ค่าที่ใส่ใน payload ใช้ตามที่ view คืนมาตรง ๆ: customer `0001000082`
  (มี leading zero), item `001` / `005` (NUMC 3 หลัก)
  ถ้า API ฟ้องหา item ไม่เจอ ค่อยลองตัด leading zero

---

## 8. Test case ชุดที่ 2 (2026-09-14) — payment แยก deferred tax เป็นคนละ doc

หลัง POC ชุดแรก functional เปลี่ยนวิธี post payment เป็น **2 เอกสาร**

| เอกสาร | Type | เนื้อหา |
|---|---|---|
| `3300000026` / 2026 | DZ | payment — bank + ค่าธรรมเนียม + AR (3 บรรทัด) |
| `7200000001` / 2026 | SA | deferred output tax โอนออก (4 บรรทัด) |

invoice ยังเป็น `9400000005` / 2026 ใบเดิม (reverse `3000000003` แล้ว)

### บรรทัดที่ส่งเข้า API

| Node | เอกสาร | Item | Account | PK | Amount (THB) |
|---|---|---|---|---|---:|
| `GLItems` | `9400000005` | 003 | G/L `0021082005` | 50 | −419.93 |
| `GLItems` | `7200000001` | 003 | G/L `0021082005` | 40 | +419.93 |
| `APARItems` | `9400000005` | 001 | Customer `0001000082` | 01 | +6,418.93 |
| `APARItems` | `3300000026` | **003** | Customer `0001000082` | 11 | −6,418.93 |

ต่างจากชุดที่ 1 แค่ 2 จุด: AR ฝั่ง payment เปลี่ยนเอกสาร + item (`005` → `003`)
และ deferred tax ฝั่งหักล้างย้ายจาก payment ไปอยู่ `7200000001`

### บรรทัดที่ **ไม่** ส่ง

- `3300000026` 001–002 (bank, ค่าธรรมเนียม)
- `7200000001` 001–002 (G/L `0011054001` ±419.93 ไม่ใช่ open item managed)
- `7200000001` 004 (G/L `0021082003` −419.93 — output tax จริง รอ process อื่น
  ไม่อยู่ใน scope นี้)
- `9400000005` 002 (revenue)

### ผลการยิง (2026-09-14)

| รอบ | ส่ง | ผล |
|---|---|---|
| เต็ม 4 บรรทัด | GL 2 + AR 2 | ❌ ไม่มีอะไรถูก clear |
| bisect 1 | AR 2 บรรทัด | ❌ |
| bisect 2 | GL 2 บรรทัด | ✅ `3000000004` |

→ **AR pair ถูกปฏิเสธ** — ต่างจากชุดที่ 1 ตรงที่ `3300000026`/003 เป็น
**PK 11** (credit memo) ส่วน `3300000017`/005 ที่เคยผ่านเป็น PK 15
(incoming payment) · attribute อื่นเหมือนกันหมด (tax code, OIM, special G/L,
assignment) · เหตุผลจริงต้องอ่านจาก AIF

`3000000004` ต้อง **reverse** ก่อนยิงรอบสุดท้าย เพราะ functional ต้องการ
clearing doc ใบเดียวคลุมทั้ง 4 บรรทัด

### กับดักเดิม

เลขเอกสารทั้ง 3 ใบมีซ้ำใน **FY2025** อีกแล้ว (`3300000026`, `7200000001`,
`9400000005` ปี 2025 เป็นคนละใบ) — payload ต้องระบุ `FiscalYear = 2026` เสมอ
