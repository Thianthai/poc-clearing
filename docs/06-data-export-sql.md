# 06 — SQL สำหรับ export test data

Released CDS view ที่เช็คแล้วบน tenant (2026-09-09):

| View | Status | ใช้ทำอะไร |
|---|---|---|
| `I_OperationalAcctgDocItem` | ✅ Released | **ตัวหลักตัวเดียวพอ** — AP / AR / G/L + `IsOpenItemManaged` |
| `I_GLAccountLineItem` | ✅ Released | cross-check ฝั่ง G/L |
| `I_JournalEntryItem` | ✅ Released | cross-check ยอดจาก ACDOCA |
| `I_GLAccountInCompanyCode` · `I_GLAccountInChartOfAccounts` | ✅ Released | ไม่จำเป็นแล้ว (ดูหมายเหตุ) |
| `I_CompanyCode` · `I_AccountingDocumentType` | ✅ Released | lookup |
| `I_Supplier` · `I_SupplierCompany` · `I_Customer` · `I_CustomerCompany` | ✅ Released | lookup |
| `I_OperationalAcctgDocItemCube` | ❌ ไม่มีบน tenant | — |

> `I_OperationalAcctgDocItem` มี field `IsOpenItemManaged` อยู่ในตัวเอง
> จึงไม่ต้อง join `I_GLAccountInCompanyCode` เพื่อเช็ค open item management

## Field name ที่ยืนยันจาก Q0 แล้ว

`CompanyCode` · `AccountingDocument` · `FiscalYear` · `AccountingDocumentItem` ·
`ClearingDate` · `ClearingAccountingDocument` · `ClearingJournalEntry` · `ClearingItem` ·
`PostingKey` · `FinancialAccountType` · `SpecialGLCode` · `DebitCreditCode` ·
`IsOpenItemManaged` · `GLAccount` · `OperationalGLAccount` · `Customer` · `Supplier` ·
`AssignmentReference` · `DocumentItemText` · `PaymentDifferenceReason` ·
`OffsettingAccount` · `OffsettingAccountType` · `PostingDate` · `DocumentDate` ·
`AccountingDocumentType` · `NetDueDate` · `FiscalPeriod` ·
`TransactionCurrency` · `AmountInTransactionCurrency` ·
`CompanyCodeCurrency` · `AmountInCompanyCodeCurrency`

## วิธีรัน

ทุก query เป็น **ABAP SQL** — วางใน console class (`IF_OO_ADT_CLASSRUN`) แล้ว
`out->write( lt_xxx ).` หรือวางใน ADT SQL Console โดยตัด `INTO TABLE @DATA(...)` ออก

company code ที่ใช้อยู่คือ `'1000'`

---

## สถานะข้อมูลบน tenant (Q7 + Q8 · 2026-09-09)

### Q7 — ภาพรวม open item ที่ `IsOpenItemManaged = 'X'`

| AcctType | Crcy | Total | Debit | Credit | Balance |
|---|---|---:|---:|---:|---:|
| D (customer) | THB | 58 | 48 | 10 | 12,612,591.42 |
| K (vendor) | THB | 24 | 5 | 19 | −206,407.00 |
| S (G/L) | THB | 232 | 111 | 121 | 9,427,836,723.84 |
| D | USD | 2 | 2 | 0 | 20,000.00 |
| K | USD | 2 | 0 | 2 | −3,340.00 |
| S | USD | 9 | 4 | 5 | −1,484,941.42 |

**มีทั้งเดบิตและเครดิตครบทุกประเภทใน THB** — ไม่ใช่ว่าไม่มีข้อมูลเลย

### Q8 — ยอด open item ต่อบัญชี G/L (ถอด HAVING ออก)

ไม่มีบัญชีไหนที่ยอดรวม = 0 บัญชีที่มี item เยอะสุด

| GLAccount | Crcy | Items | Balance |
|---|---|---:|---:|
| `0021082005` | THB | 64 | 85,454.25 |
| `0021082003` | THB | 47 | −660,651,720.15 |
| `0011051001` | THB | 34 | 1,456,042.32 |
| `0011092001` | THB | 28 | 74,481,608.67 |
| `0011093001` | THB | 21 | 10,010,930,203.10 |
| `0021081005` | THB | 14 | −301,540.00 |

### สรุป

เงื่อนไข "ทั้งบัญชีรวมกันเป็นศูนย์" (Q1/Q8 แบบมี HAVING) โหดเกินไป —
ของจริง clearing จับแค่ **subset** ของ item ไม่ใช่ทั้งบัญชี

ทางเลือกที่มี:

1. **Q9 / Q10** — หาคู่ที่ยอดเท่ากันพอดีในบัญชีที่มี item เยอะ
   (`0021082005`, `0011051001`) โอกาสเจอสูง
2. **ให้ functional เตรียม test data ให้** ← เลือกทางนี้ ชัดเจนกว่า
   คุมได้ว่าเอกสารไหนคู่กับไหน

ระหว่างรอ data → `YCL_CLEARING` ตั้ง `gc_dry_run = abap_true`
รันดู payload ได้เลยโดยไม่ต้องมี data

---

## Q0 — probe ชื่อ field (รันครั้งเดียวพอ ทำแล้ว)

```abap
SELECT *
  FROM I_OperationalAcctgDocItem
  WHERE CompanyCode = '1000'
  ORDER BY AccountingDocument DESCENDING
  INTO TABLE @DATA(lt_probe)
  UP TO 20 ROWS.
```

## Q7 — ภาพรวม: ยังเหลืออะไรให้ clear บ้าง (รันอันนี้ก่อนทุกครั้ง)

นับแยกเดบิต/เครดิต ถ้าฝั่งใดฝั่งหนึ่งเป็น 0 แปลว่า clear ไม่ได้ตั้งแต่ต้น

```abap
SELECT FinancialAccountType,
       TransactionCurrency,
       COUNT(*)                                                          AS TotalItems,
       SUM( CASE WHEN AmountInTransactionCurrency > 0 THEN 1 ELSE 0 END ) AS DebitItems,
       SUM( CASE WHEN AmountInTransactionCurrency < 0 THEN 1 ELSE 0 END ) AS CreditItems,
       SUM( AmountInTransactionCurrency )                                 AS Balance
  FROM I_OperationalAcctgDocItem
  WHERE CompanyCode                = '1000'
    AND ClearingAccountingDocument = ''
    AND SpecialGLCode              = ''
    AND IsOpenItemManaged          = 'X'
  GROUP BY FinancialAccountType, TransactionCurrency
  INTO TABLE @DATA(lt_overview).
```

## Q8 — G/L: หาบัญชีที่ open item รวมกันเป็นศูนย์ (เคสหลักตอนนี้)

```abap
SELECT GLAccount,
       TransactionCurrency,
       COUNT(*)                           AS OpenItemCount,
       SUM( AmountInTransactionCurrency ) AS OpenBalance
  FROM I_OperationalAcctgDocItem
  WHERE CompanyCode                = '1000'
    AND FinancialAccountType       = 'S'
    AND IsOpenItemManaged          = 'X'
    AND ClearingAccountingDocument = ''
  GROUP BY GLAccount, TransactionCurrency
  HAVING SUM( AmountInTransactionCurrency ) = 0
     AND COUNT(*) BETWEEN 2 AND 10
  INTO TABLE @DATA(lt_gl_candidates).
```

ถ้าได้ผลลัพธ์ว่าง ให้ถอด `HAVING` ออกแล้วดูด้วยตาว่าบัญชีไหนมีทั้งสองฝั่ง
(`0021082005` เป็นตัวที่เห็นแล้วว่ามี)

## Q9 — หา "คู่ยอดเท่ากันพอดี" ตรง ๆ (ใช้ได้ทั้ง K / D / S)

ไม่ต้องรอให้ทั้งบัญชีเป็นศูนย์ แค่หาเดบิต 1 บรรทัดที่มีเครดิตยอดเท่ากันอยู่

```abap
SELECT a~FinancialAccountType,
       a~GLAccount,
       a~Supplier,
       a~Customer,
       a~TransactionCurrency,
       a~FiscalYear                  AS FiscalYear1,
       a~AccountingDocument          AS Document1,
       a~AccountingDocumentItem      AS Item1,
       a~AmountInTransactionCurrency AS Amount1,
       b~FiscalYear                  AS FiscalYear2,
       b~AccountingDocument          AS Document2,
       b~AccountingDocumentItem      AS Item2,
       b~AmountInTransactionCurrency AS Amount2
  FROM I_OperationalAcctgDocItem AS a
  INNER JOIN I_OperationalAcctgDocItem AS b
          ON  b~CompanyCode          = a~CompanyCode
          AND b~FinancialAccountType = a~FinancialAccountType
          AND b~GLAccount            = a~GLAccount
          AND b~Supplier             = a~Supplier
          AND b~Customer             = a~Customer
          AND b~TransactionCurrency  = a~TransactionCurrency
  WHERE a~CompanyCode                = '1000'
    AND a~ClearingAccountingDocument = ''
    AND b~ClearingAccountingDocument = ''
    AND a~SpecialGLCode              = ''
    AND b~SpecialGLCode              = ''
    AND a~IsOpenItemManaged          = 'X'
    AND b~IsOpenItemManaged          = 'X'
    AND a~AmountInTransactionCurrency > 0
    AND a~AmountInTransactionCurrency + b~AmountInTransactionCurrency = 0
  INTO TABLE @DATA(lt_pairs)
  UP TO 50 ROWS.
```

> ถ้า compiler ไม่ยอมให้บวกกันใน `WHERE` ให้ใช้ Q10 แล้วจับคู่ด้วยตาแทน

## Q10 — list open item ทั้งหมดแบบเรียงตามยอด (fallback ของ Q9)

เรียงตามบัญชี + ยอด จะเห็นคู่ที่ยอดเท่ากันติดกันเอง

```abap
SELECT FinancialAccountType,
       GLAccount,
       Supplier,
       Customer,
       TransactionCurrency,
       AmountInTransactionCurrency,
       FiscalYear,
       AccountingDocument,
       AccountingDocumentItem,
       PostingKey,
       DebitCreditCode,
       PostingDate,
       AccountingDocumentType,
       AssignmentReference,
       DocumentItemText
  FROM I_OperationalAcctgDocItem
  WHERE CompanyCode                = '1000'
    AND ClearingAccountingDocument = ''
    AND SpecialGLCode              = ''
    AND IsOpenItemManaged          = 'X'
  ORDER BY FinancialAccountType, GLAccount, Supplier, Customer,
           TransactionCurrency, AmountInTransactionCurrency
  INTO TABLE @DATA(lt_all_open).
```

---

## Q12 — ดึงบรรทัดของเอกสารที่ functional เตรียมให้ (เคสจริงของ POC)

ชุดที่ได้มา 2026-09-09 — เป็นเคส **AR (customer)**

```
Sales order        JA30000116
Billing document   JA70000046
FI invoice         9400000005     ← เดบิตลูกหนี้
Payment document   3300000017     ← เครดิตลูกหนี้
```

```abap
SELECT CompanyCode,
       FinancialAccountType,
       Customer,
       Supplier,
       GLAccount,
       FiscalYear,
       AccountingDocument,
       AccountingDocumentItem,
       PostingKey,
       DebitCreditCode,
       TransactionCurrency,
       AmountInTransactionCurrency,
       PostingDate,
       DocumentDate,
       AccountingDocumentType,
       SpecialGLCode,
       IsOpenItemManaged,
       ClearingAccountingDocument,
       ClearingDate,
       AssignmentReference,
       DocumentItemText
  FROM I_OperationalAcctgDocItem
  WHERE CompanyCode        = '1000'
    AND AccountingDocument IN ( '9400000005', '3300000017' )
  ORDER BY AccountingDocument, AccountingDocumentItem
  INTO TABLE @DATA(lt_case).
```

### อ่านผลยังไง

| เช็ค | ต้องเป็น |
|---|---|
| `FinancialAccountType` | เอาเฉพาะบรรทัด `D` — บรรทัด revenue / tax / bank (`S`) ไม่ต้องส่งเข้า API |
| `ClearingAccountingDocument` | **ต้องว่าง** ถ้าไม่ว่าง = payment เคลียร์ invoice ไปแล้วตอน post ใช้ทำ POC ไม่ได้ |
| `IsOpenItemManaged` | `X` |
| `SpecialGLCode` | ว่าง |
| `AmountInTransactionCurrency` | สองบรรทัดต้องบวกกันได้ 0 พอดี |
| `Customer` | ต้องเป็นรายเดียวกันทั้งสองเอกสาร |

> ถ้า payment ปิด invoice ไปแล้ว ให้ขอ functional post payment ใหม่แบบ
> **ไม่ระบุ invoice** (post เป็น open item ลอย ๆ) แล้วค่อยให้ API เป็นตัว clear

---

## Q11 — open item ที่เพิ่ง post ล่าสุด (ใช้หา data ที่ functional เพิ่งเตรียมให้)

เรียงจากเอกสารใหม่สุด ครอบคลุมทั้ง K / D / S ในทีเดียว

```abap
SELECT FinancialAccountType,
       GLAccount,
       Supplier,
       Customer,
       TransactionCurrency,
       AmountInTransactionCurrency,
       FiscalYear,
       AccountingDocument,
       AccountingDocumentItem,
       PostingKey,
       DebitCreditCode,
       PostingDate,
       DocumentDate,
       AccountingDocumentType,
       AssignmentReference,
       DocumentItemText,
       SpecialGLCode,
       IsOpenItemManaged
  FROM I_OperationalAcctgDocItem
  WHERE CompanyCode                = '1000'
    AND ClearingAccountingDocument = ''
    AND SpecialGLCode              = ''
    AND IsOpenItemManaged          = 'X'
  ORDER BY PostingDate DESCENDING, AccountingDocument DESCENDING,
           AccountingDocumentItem
  INTO TABLE @DATA(lt_latest)
  UP TO 60 ROWS.
```

ถ้ารู้วันที่ที่ functional post ให้เติม `AND PostingDate >= '20260901'` เข้าไป
จะแคบลงเยอะ

---

## Q2 — ดึงบรรทัดจริงหลังเลือกได้แล้ว

เปลี่ยน filter ตามเคสที่เลือก (G/L ใช้ `FinancialAccountType = 'S'` + `GLAccount`)

```abap
SELECT CompanyCode,
       FinancialAccountType,
       GLAccount,
       Supplier,
       Customer,
       FiscalYear,
       AccountingDocument,
       AccountingDocumentItem,
       PostingKey,
       DebitCreditCode,
       TransactionCurrency,
       AmountInTransactionCurrency,
       PostingDate,
       DocumentDate,
       AccountingDocumentType,
       AssignmentReference,
       DocumentItemText,
       SpecialGLCode,
       IsOpenItemManaged,
       ClearingAccountingDocument,
       ClearingDate
  FROM I_OperationalAcctgDocItem
  WHERE CompanyCode                = '1000'
    AND FinancialAccountType       = 'S'
    AND GLAccount                  = 'CHANGE_ME_GLACCT'
    AND ClearingAccountingDocument = ''
    AND SpecialGLCode              = ''
  ORDER BY AccountingDocument, AccountingDocumentItem
  INTO TABLE @DATA(lt_open_items).
```

## Q1 — เคส vendor (เก็บไว้ใช้ทีหลัง หลังมีเอกสารฝั่งตรงข้ามแล้ว)

```abap
SELECT Supplier,
       TransactionCurrency,
       COUNT(*)                           AS OpenItemCount,
       SUM( AmountInTransactionCurrency ) AS OpenBalance
  FROM I_OperationalAcctgDocItem
  WHERE CompanyCode                = '1000'
    AND FinancialAccountType       = 'K'
    AND ClearingAccountingDocument = ''
    AND SpecialGLCode              = ''
  GROUP BY Supplier, TransactionCurrency
  HAVING SUM( AmountInTransactionCurrency ) = 0
     AND COUNT(*) BETWEEN 2 AND 6
  INTO TABLE @DATA(lt_candidates).
```

เคส customer เปลี่ยนเป็น `FinancialAccountType = 'D'` และ `Supplier` → `Customer`

## Q5 — lookup ประกอบ

```abap
SELECT CompanyCode, CompanyCodeName, Currency, ChartOfAccounts
  FROM I_CompanyCode
  WHERE CompanyCode = '1000'
  INTO TABLE @DATA(lt_ccode).

SELECT AccountingDocumentType, NumberRange, IsNetDocumentType
  FROM I_AccountingDocumentType
  WHERE AccountingDocumentType IN ( 'AB', 'DZ', 'KZ', 'SA' )
  INTO TABLE @DATA(lt_doctype).
```

---

## รูปแบบผลลัพธ์ที่ส่งกลับมา

```
company_code : 1000
currency     : THB
gl_account   : ____        (หรือ supplier / customer)

FinancialAccountType / GLAccount / FiscalYear / AccountingDocument / AccountingDocumentItem / Amount
S / .......... / 2025 / .......... / 001 / +5,000.00
S / .......... / 2025 / .......... / 002 / -5,000.00
```

## ข้อควรระวังตอนอ่านผล

- `AmountInTransactionCurrency` เป็นค่า **signed** (บวก = เดบิต, ลบ = เครดิต)
  ผลรวมของบรรทัดที่ส่งเข้า API ต้อง = 0 ถึงจะ full clear ได้
- `ClearingAccountingDocument` ไม่ว่าง = ถูก clear ไปแล้ว ใช้ไม่ได้
- `SpecialGLCode` ไม่ว่าง = ข้ามไป API ไม่รองรับ
- `IsOpenItemManaged` ต้องเป็น `'X'` ไม่งั้นจะได้ error
  *"There are no open items managed in Account"*
- item ที่ `TransactionCurrency` ต่างกัน อย่าเอามาปนใน request เดียว
