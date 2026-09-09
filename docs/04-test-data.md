# 04 — Test Data ที่ต้อง export จากระบบ

ค่าทั้งหมดใน `YCL_CLEARING` ที่เขียนว่า `CHANGE_ME...` ต้องแทนด้วยค่าจริง
จาก tenant ก่อนรัน

## 1. ค่าระดับ header

| Constant ใน class | ความหมาย | ค่าที่ต้องหา |
|---|---|---|
| `gc_company_code` | company code ที่จะ post เอกสาร clearing | เช่น `1010` |
| `gc_document_type` | document type ของเอกสาร clearing | `AB` (G/L) · `DZ` (รับเงินลูกหนี้) · `KZ` (จ่ายเจ้าหนี้) |
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

> ⚠️ **ชุดนี้ถูกใช้ไปแล้ว** (2026-09-09) — ทั้งสองบรรทัดถูก clear ด้วยเอกสาร
> `0100000000` เอามาทดสอบซ้ำไม่ได้ ถ้าจะทดสอบ partial / residual ต่อ
> ต้องขอ functional เตรียมชุดใหม่ หรือ reverse เอกสาร `0100000000` ทิ้ง
> เพื่อให้ open item กลับมา

### บรรทัดที่ **ไม่** ส่ง

บรรทัด `FinancialAccountType = 'S'` ทั้งหมด (bank `0011092001`, revenue
`0021060006`, tax `0021082005` / `0021082003`, ค่าธรรมเนียม `0011047003`)
API สร้าง offsetting ให้เอง

### กับดักที่เจอตอนดึงข้อมูล

- **เลขเอกสารซ้ำข้ามปี** — `9400000005` และ `3300000017` มีทั้ง FY2025 และ FY2026
  ถ้า query ไม่กรอง `FiscalYear` จะได้เอกสารคนละใบปนมา และ FY2025 นั้น
  invoice ถูก clear ไปแล้ว (`ClearingAccountingDocument = 3300000003`)
  → **ต้องระบุ `fiscal_year` ใน payload เสมอ**
- ค่าที่ใส่ใน payload ใช้ตามที่ view คืนมาตรง ๆ: customer `0001000082`
  (มี leading zero), item `001` / `005` (NUMC 3 หลัก)
  ถ้า API ฟ้องหา item ไม่เจอ ค่อยลองตัด leading zero
