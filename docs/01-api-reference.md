# 01 — API Reference: Journal Entry – Clearing (Asynchronous)

## ข้อมูลพื้นฐาน

| หัวข้อ | ค่า |
|---|---|
| API Hub | <https://api.sap.com/api/JOURNALENTRYBULKCLEARINGREQUES/overview> |
| Service interface | `JournalEntryBulkClearingRequest_In` |
| Root element | `JournalEntryBulkClearingRequest` |
| Namespace | `http://sap.com/xi/SAPSCORE/SFIN` |
| Protocol | SOAP 1.1 · **asynchronous** (fire & forget) |
| Endpoint | `https://<host>-api.s4hana.cloud.sap/sap/bc/srt/scs_ext/sap/journalentrybulkclearingreques` |
| SOAPAction | `http://sap.com/xi/SAPSCORE/SFIN/JournalEntryBulkClearingRequest_In/JournalEntryBulkClearingRequest_InRequest` |
| Communication scenario (มาตรฐาน) | `SAP_COM_0002` — Finance: Posting Integration (ขา inbound) |
| ผลลัพธ์ | Fiori app **Message Dashboard** (AIF) |
| ตั้งแต่ release | CE1908 |

รองรับการ clear ของ **G/L account**, **customer (D)** และ **vendor (K)**
ทั้งแบบ full / partial / residual

## โครงสร้าง message

```
JournalEntryBulkClearingRequest
├── MessageHeader                       (1)
│   ├── ID                              mandatory · unique · ≤ 35 chars
│   ├── CreationDateTime                xsd:dateTime
│   └── TestDataIndicator               true = simulate เท่านั้น ไม่ post จริง
└── JournalEntryClearingRequest         (1..n)  ← 1 request = 1 เอกสาร clearing
    ├── MessageHeader
    │   ├── ID
    │   ├── CreationDateTime
    │   └── TestDataIndicator
    └── JournalEntry
        ├── CompanyCode                 mandatory
        ├── AccountingDocumentType      mandatory (AB / DZ / KZ …)
        ├── DocumentDate                mandatory  YYYY-MM-DD
        ├── PostingDate                 mandatory  YYYY-MM-DD (ต้องอยู่ใน period ที่เปิด)
        ├── CurrencyCode                mandatory
        ├── AccountingDocument          optional — เลขเอกสารที่อยากกำหนดเอง
        ├── CurrencyTranslationDate     optional
        ├── FiscalPeriod                optional
        ├── ExchangeRate                optional
        ├── DocumentHeaderText          optional
        ├── ReferenceDocument           optional
        ├── CreatedByUser               optional
        ├── GLItems                     (0..n) — clear G/L open item
        └── APARItems                   (0..n) — clear customer / vendor open item
```

### GLItems

| Field | หมายเหตุ |
|---|---|
| `ReferenceDocumentItem` | ลำดับบรรทัดใน request (1, 2, 3 …) |
| `CompanyCode` | optional — ไม่ใส่ = ใช้ของ header |
| `GLAccount` | บัญชี G/L ที่เปิด open item management |
| `FiscalYear` | ปีบัญชีของเอกสารต้นทาง |
| `AccountingDocument` | เลขเอกสารต้นทางที่จะ clear |
| `AccountingDocumentItem` | บรรทัดของเอกสารต้นทาง |

### APARItems

| Field | หมายเหตุ |
|---|---|
| `ReferenceDocumentItem` | ลำดับบรรทัดใน request |
| `CompanyCode` | optional |
| `AccountType` | `D` = customer · `K` = vendor |
| `APARAccount` | เลข customer / vendor |
| `FiscalYear` | ปีบัญชีของเอกสารต้นทาง |
| `AccountingDocument` | เลขเอกสารต้นทาง |
| `AccountingDocumentItem` | บรรทัดของเอกสารต้นทาง |
| `PartialPaymentAmtInDspCrcy` | partial clearing · มี attribute `currencyCode` |
| `CashDiscountAmountInDspCrcy` | residual · ส่วนลดเงินสด |
| `OtherDeductionAmountInDspCrcy` | residual · ยอดคงเหลือ (ใส่ค่าติดลบ) |
| `PaymentDifferenceReason` | reason code ของผลต่าง |
| `PaymentDifferenceDistribution` | (0..n) กระจายผลต่างตาม reason code (ตั้งแต่ CE2108) |

> ทุก field ที่เป็นจำนวนเงินต้องมี attribute `currencyCode="THB"` กำกับ

## ตัวอย่าง payload

### Full clearing — vendor open items

```xml
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"
                  xmlns:sfin="http://sap.com/xi/SAPSCORE/SFIN">
  <soapenv:Header xmlns:wsa="http://www.w3.org/2005/08/addressing">
    <wsa:Action soapenv:mustUnderstand="1">http://sap.com/xi/SAPSCORE/SFIN/JournalEntryBulkClearingRequest_In/JournalEntryBulkClearingRequest_InRequest</wsa:Action>
    <wsa:MessageID soapenv:mustUnderstand="1">uuid:2f8a...c31</wsa:MessageID>
  </soapenv:Header>
  <soapenv:Body>
    <sfin:JournalEntryBulkClearingRequest>
      <MessageHeader>
        <ID>POC_CLEAR_0001</ID>
        <CreationDateTime>2026-09-09T03:00:00Z</CreationDateTime>
        <TestDataIndicator>false</TestDataIndicator>
      </MessageHeader>
      <JournalEntryClearingRequest>
        <MessageHeader>
          <ID>POC_CLEAR_0001_01</ID>
          <CreationDateTime>2026-09-09T03:00:00Z</CreationDateTime>
        </MessageHeader>
        <JournalEntry>
          <CompanyCode>1010</CompanyCode>
          <AccountingDocumentType>AB</AccountingDocumentType>
          <DocumentDate>2026-09-09</DocumentDate>
          <PostingDate>2026-09-09</PostingDate>
          <CurrencyCode>THB</CurrencyCode>
          <DocumentHeaderText>POC Clearing</DocumentHeaderText>
          <CreatedByUser>POC_USER</CreatedByUser>
          <APARItems>
            <ReferenceDocumentItem>1</ReferenceDocumentItem>
            <AccountType>K</AccountType>
            <APARAccount>S10300901</APARAccount>
            <FiscalYear>2026</FiscalYear>
            <AccountingDocument>1900000959</AccountingDocument>
            <AccountingDocumentItem>1</AccountingDocumentItem>
          </APARItems>
          <APARItems>
            <ReferenceDocumentItem>2</ReferenceDocumentItem>
            <AccountType>K</AccountType>
            <APARAccount>S10300901</APARAccount>
            <FiscalYear>2026</FiscalYear>
            <AccountingDocument>1500000241</AccountingDocument>
            <AccountingDocumentItem>2</AccountingDocumentItem>
          </APARItems>
        </JournalEntry>
      </JournalEntryClearingRequest>
    </sfin:JournalEntryBulkClearingRequest>
  </soapenv:Body>
</soapenv:Envelope>
```

### Partial clearing

เพิ่มใน `APARItems` บรรทัดที่ต้องการจ่ายบางส่วน:

```xml
<PartialPaymentAmtInDspCrcy currencyCode="THB">70</PartialPaymentAmtInDspCrcy>
<PaymentDifferenceReason>910</PaymentDifferenceReason>
```

### Residual clearing (มีส่วนลด)

```xml
<CashDiscountAmountInDspCrcy currencyCode="THB">2</CashDiscountAmountInDspCrcy>
<OtherDeductionAmountInDspCrcy currencyCode="THB">-28</OtherDeductionAmountInDspCrcy>
<PaymentDifferenceReason>910</PaymentDifferenceReason>
```

### G/L clearing

ใช้ node `GLItems` แทน `APARItems`:

```xml
<GLItems>
  <ReferenceDocumentItem>1</ReferenceDocumentItem>
  <GLAccount>11001010</GLAccount>
  <FiscalYear>2026</FiscalYear>
  <AccountingDocument>100003875</AccountingDocument>
  <AccountingDocumentItem>1</AccountingDocumentItem>
</GLItems>
```

## ข้อจำกัดที่ต้องรู้ก่อนออกแบบ

| ข้อจำกัด | ผลกระทบ |
|---|---|
| Cash discount ใช้กับ **partial clearing ไม่ได้** | ต้องเลือกอย่างใดอย่างหนึ่ง |
| Residual amount ใช้กับ **partial clearing ไม่ได้** | เช่นกัน |
| **ไม่รองรับ Special G/L indicator** (`UMSKZ`) | เคลียร์ down payment / เงินมัดจำไม่ได้ผ่าน API นี้ |
| ไม่มี `XNOPS` (select only non-special G/L) | ต่างจาก FB05 |
| `GLItems` เลือกได้เฉพาะ open item ที่มีอยู่แล้ว | **สร้างบรรทัด bank account เองไม่ได้** — API นี้ทำแค่ clear ไม่ได้ post payment |
| บัญชี G/L ต้องเป็น open item managed | ไม่งั้นได้ error "There are no open items managed in Account" |
| Message header `ID` ต้อง unique ≤ 35 chars | ยิงซ้ำ ID เดิม = duplicate |

> ถ้าเคสจริงต้องการ "จ่ายเงิน + clear ในเอกสารเดียว" API ตัวนี้ทำไม่ได้
> ต้องใช้ Journal Entry – Post ควบคู่ หรือ Payment API แทน

## การตรวจผลลัพธ์

1. Fiori app **Message Dashboard** (AIF) → ค้นด้วย Message ID ที่ console พิมพ์
2. หรือ enable outbound service **Journal Entry – Clearing Confirmation
   (Asynchronous)** (ตั้งแต่ CE2108) ให้ระบบส่งผลกลับมาที่ระบบต้นทาง

## แหล่งอ้างอิง

- [Guidelines for API Journal Entry – Clearing (Asynchronous)](https://community.sap.com/t5/enterprise-resource-planning-blog-posts-by-sap/guidelines-for-api-journal-entry-clearing-asynchronous/ba-p/13410748)
- [Journal Entry – Clearing (Asynchronous) — SAP Help Portal](https://help.sap.com/docs/SAP_S4HANA_CLOUD/b978f98fc5884ff2aeb10c8fdeb8a43b/5142cdd767b04122a8beb6ecd460a922.html)
- [Calling SOAP Asynchronous Api In RAP (Public Cloud)](https://community.sap.com/t5/technology-blog-posts-by-members/calling-soap-asynchronous-api-in-rap-public-cloud/ba-p/14012118)
- [APIs for Journal Entries – The Collection](https://community.sap.com/t5/technology-blog-posts-by-sap/apis-for-journal-entries-the-collection-updated-july-2025/ba-p/13565258)

---

## Document splitting กับ clearing document ที่ API สร้าง

> **ข้อสรุป (2026-09-10): พฤติกรรมนี้ถูกต้องแล้ว** — functional ยืนยันหลังตรวจซ้ำ
> ที่ตั้งข้อสงสัยตอนแรกว่าไม่ควรมีบรรทัด zero-balance เป็นความเข้าใจผิด
> ส่วนนี้เก็บไว้เป็นความรู้ว่าบรรทัดพวกนี้มาจากไหน

clearing document ที่ API สร้างจะมีบรรทัดมากกว่าที่ส่งใน payload เช่น
`3000000003` ส่ง 4 บรรทัดแต่ได้ 6 บรรทัดใน ACDOCA

### บรรทัดส่วนเกินมาจาก document splitting

| Ledger item | G/L | Amount | Profit Center | Partner PC | `AccountingDocumentItem` |
|---|---|---:|---|---|---|
| 000005 | `0012990002` | +5,999.00 | `0000010002` | `DUMMY` | **`000`** |
| 000006 | `0012990002` | −5,999.00 | `DUMMY` | `0000010002` | **`000`** |

`AccountingDocumentItem = 000` = ไม่มีใน BSEG มีแต่ใน ACDOCA → เป็นบรรทัดที่
**document splitting สร้างเอง** (Zero-Balance Clearing Account)
จึงไม่โผล่ใน `I_OperationalAcctgDocItem` ตอนเช็คผล

### กลไก

clearing line **inherit** profit center จาก open item ที่ถูก clear

| ฝั่ง | เอกสาร | Profit Center | AR | Tax | รวม |
|---|---|---|---:|---:|---:|
| invoice | `9400000005` | `DUMMY` | +6,418.93 | −419.93 | **+5,999.00** |
| payment | `3300000017` | `0000010002` | −6,418.93 | +419.93 | **−5,999.00** |

เอกสาร balance โดยรวมแต่ไม่ balance รายตัว profit center → splitting เติม
บรรทัด zero-balance เข้ามาให้แต่ละ PC เป็นศูนย์ เป็นพฤติกรรมมาตรฐาน
เกิดเหมือนกันไม่ว่าจะ clear ด้วย API หรือ standard app

### สิ่งที่ทดสอบแล้วว่า **ไม่เกี่ยว**

| ทดสอบ | ผล |
|---|---|
| document type `AB` (เอกสาร `0100000002`) | มีบรรทัด zero-balance |
| document type `DA` (เอกสาร `3000000003`) | มีบรรทัด zero-balance เหมือนกันเป๊ะ |

API ไม่มี field ให้ระบุ profit center ของบรรทัด clearing และไม่ควรมี
เพราะต้อง inherit จากต้นทาง

> document type ที่ใช้จริงคือ **`DA` (Customer Document)** ตามที่ functional กำหนด
