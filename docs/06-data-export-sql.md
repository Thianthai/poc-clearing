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

## สถานะข้อมูลบน tenant (อัปเดต 2026-09-09)

รัน Q1 แล้ว **ไม่มี vendor รายไหนที่ open item รวมกันเป็นศูนย์** — ทุกรายเหลือแต่
ยอดเครดิต (invoice ที่ยังไม่จ่าย) ไม่มีฝั่งเดบิตมาหักล้าง

```
0001000001,THB, 8,-171307.00      0003000001,THB, 1, -8000.00
0001000002,THB, 1, -10700.00      0004000012,THB, 1, -1050.00
0001000006,THB,12,  -5350.00      0008000001,THB, 1,-10000.00
0002000001,USD, 2,  -3340.00
```

จาก sample 100 แถวของ Q0 เห็นภาพเดียวกัน:

| ประเภท | สิ่งที่เจอ | ใช้ทำ POC ได้ไหม |
|---|---|---|
| Customer (`D`) | เป็นเดบิตล้วน (invoice ค้างรับ) ไม่มีใบรับเงิน | ❌ |
| Vendor (`K`) | เป็นเครดิตล้วน | ❌ |
| G/L (`S`) | บัญชี `0021082005` มีทั้งเดบิตและเครดิตปนกัน | ✅ **มีหวังที่สุด** |

→ เคสแรกของ POC ควรเป็น **G/L clearing** ไม่ใช่ vendor clearing
ถ้าจำเป็นต้องทดสอบ vendor จริง ๆ ต้อง post เอกสารฝั่งตรงข้ามขึ้นมาก่อน
(credit memo หรือ outgoing payment) แล้วค่อย clear

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
