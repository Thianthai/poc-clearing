# 06 — SQL สำหรับ export test data

Released CDS view ที่เช็คแล้วบน tenant (2026-09-09):

| View | Status | ใช้ทำอะไร |
|---|---|---|
| `I_OperationalAcctgDocItem` | ✅ Released | **ตัวหลัก** — open item ทั้ง AP / AR / G/L |
| `I_GLAccountLineItem` | ✅ Released | cross-check ฝั่ง G/L |
| `I_JournalEntryItem` | ✅ Released | cross-check ยอดจาก ACDOCA |
| `I_GLAccountInCompanyCode` | ✅ Released | เช็ค open item managed |
| `I_GLAccountInChartOfAccounts` | ✅ Released | ชื่อบัญชี |
| `I_CompanyCode` | ✅ Released | lookup |
| `I_AccountingDocumentType` | ✅ Released | lookup |
| `I_Supplier` · `I_SupplierCompany` | ✅ Released | lookup |
| `I_Customer` · `I_CustomerCompany` | ✅ Released | lookup |
| `I_OperationalAcctgDocItemCube` | ❌ ไม่มีบน tenant | — |

## วิธีรัน

ทุก query เขียนเป็น **ABAP SQL** ใช้ได้ 2 ทาง

- **ADT → SQL Console** — วางแล้วตัด `INTO TABLE @DATA(...)` ออก
- **Console class** (`IF_OO_ADT_CLASSRUN`) — วางทั้งก้อน แล้ว `out->write( lt_xxx ).`

ทุกที่ที่เขียน `'CHANGE_ME_CCODE'` ให้แทนด้วย company code จริง

---

## Q0 — ดูชื่อ field จริงก่อน (รันอันนี้ก่อนเสมอ)

ชื่อ field ใน query ถัด ๆ ไปอ้างจาก VDM มาตรฐาน ถ้า syntax error ที่ field ไหน
ให้กลับมาดูชื่อจริงจาก Q0

```abap
SELECT *
  FROM I_OperationalAcctgDocItem
  WHERE CompanyCode = 'CHANGE_ME_CCODE'
  ORDER BY AccountingDocument DESCENDING
  INTO TABLE @DATA(lt_probe)
  UP TO 20 ROWS.
```

---

## Q1 — หา "คู่ที่ clear ได้" ของ vendor (เคสหลักของ POC)

หา supplier ที่ยอด open item รวมกัน **เป็นศูนย์พอดี** → เอาทั้งกลุ่มไป clear ได้เลย
ไม่ต้องมานั่งจับคู่เอง

```abap
SELECT Supplier,
       TransactionCurrency,
       COUNT(*)                           AS OpenItemCount,
       SUM( AmountInTransactionCurrency ) AS OpenBalance
  FROM I_OperationalAcctgDocItem
  WHERE CompanyCode                = 'CHANGE_ME_CCODE'
    AND FinancialAccountType       = 'K'
    AND ClearingAccountingDocument = ''
    AND SpecialGLCode              = ''
  GROUP BY Supplier, TransactionCurrency
  HAVING SUM( AmountInTransactionCurrency ) = 0
     AND COUNT(*) BETWEEN 2 AND 6
  ORDER BY OpenItemCount ASCENDING
  INTO TABLE @DATA(lt_candidates).
```

- `SpecialGLCode = ''` → ตัด down payment / เงินมัดจำทิ้ง (API ไม่รองรับ)
- `COUNT(*) BETWEEN 2 AND 6` → เอาเคสเล็ก ๆ ก่อน จะได้ debug ง่าย
- ได้ผลลัพธ์แล้วเลือก supplier มา 1 ราย → เอาไปใส่ Q2

เคส **customer** เปลี่ยน `FinancialAccountType = 'D'` และ `Supplier` → `Customer`

---

## Q2 — ดึงบรรทัดจริงของ supplier ที่เลือก (ผลลัพธ์นี้คือของที่ต้องส่งมา)

```abap
SELECT CompanyCode,
       FinancialAccountType,
       Supplier,
       FiscalYear,
       AccountingDocument,
       AccountingDocumentItem,
       PostingKey,
       DebitCreditCode,
       TransactionCurrency,
       AmountInTransactionCurrency,
       PostingDate,
       DocumentDate,
       AssignmentReference,
       DocumentItemText,
       SpecialGLCode,
       ClearingAccountingDocument,
       ClearingDate
  FROM I_OperationalAcctgDocItem
  WHERE CompanyCode                = 'CHANGE_ME_CCODE'
    AND FinancialAccountType       = 'K'
    AND Supplier                   = 'CHANGE_ME_VENDOR'
    AND ClearingAccountingDocument = ''
    AND SpecialGLCode              = ''
  ORDER BY AccountingDocument, AccountingDocumentItem
  INTO TABLE @DATA(lt_open_items).
```

7 คอลัมน์แรกที่ console class ต้องใช้จริงคือ
`FinancialAccountType` · `Supplier` · `FiscalYear` · `AccountingDocument` ·
`AccountingDocumentItem` — ที่เหลือไว้ตรวจสอบด้วยตา

---

## Q3 — เคส G/L: หาบัญชีที่ open item managed

```abap
SELECT gl~CompanyCode,
       gl~GLAccount,
       coa~GLAccountLongName
  FROM I_GLAccountInCompanyCode AS gl
  INNER JOIN I_GLAccountInChartOfAccounts AS coa
    ON coa~GLAccount = gl~GLAccount
  WHERE gl~CompanyCode = 'CHANGE_ME_CCODE'
  ORDER BY gl~GLAccount
  INTO TABLE @DATA(lt_gl_accounts).
```

> `I_GLAccountInCompanyCode` มี field เกี่ยวกับ open item management อยู่ —
> รัน `SELECT *` ดูชื่อจริงก่อน (น่าจะขึ้นต้น/ลงท้ายด้วย `OpenItem`)
> แล้วค่อยเติม `AND <field> = 'X'` เข้าไปใน WHERE

## Q4 — เคส G/L: หากลุ่ม open item ที่ยอดเป็นศูนย์

```abap
SELECT GLAccount,
       TransactionCurrency,
       COUNT(*)                           AS OpenItemCount,
       SUM( AmountInTransactionCurrency ) AS OpenBalance
  FROM I_OperationalAcctgDocItem
  WHERE CompanyCode                = 'CHANGE_ME_CCODE'
    AND FinancialAccountType       = 'S'
    AND ClearingAccountingDocument = ''
  GROUP BY GLAccount, TransactionCurrency
  HAVING SUM( AmountInTransactionCurrency ) = 0
     AND COUNT(*) BETWEEN 2 AND 6
  ORDER BY OpenItemCount ASCENDING
  INTO TABLE @DATA(lt_gl_candidates).
```

จากนั้นดึงบรรทัดจริงแบบเดียวกับ Q2 แต่เปลี่ยน filter เป็น
`FinancialAccountType = 'S' AND GLAccount = 'CHANGE_ME_GLACCT'`

---

## Q5 — lookup ประกอบ

```abap
"company code + สกุลเงิน + chart of accounts
SELECT CompanyCode, CompanyCodeName, Currency, ChartOfAccounts
  FROM I_CompanyCode
  WHERE CompanyCode = 'CHANGE_ME_CCODE'
  INTO TABLE @DATA(lt_ccode).

"document type ที่จะใช้ตอน clear
SELECT AccountingDocumentType, NumberRange, IsNetDocumentType
  FROM I_AccountingDocumentType
  WHERE AccountingDocumentType IN ( 'AB', 'DZ', 'KZ' )
  INTO TABLE @DATA(lt_doctype).

"ยืนยัน vendor + recon account
SELECT sc~Supplier, s~SupplierName, sc~CompanyCode, sc~ReconciliationAccount
  FROM I_SupplierCompany AS sc
  INNER JOIN I_Supplier AS s ON s~Supplier = sc~Supplier
  WHERE sc~CompanyCode = 'CHANGE_ME_CCODE'
    AND sc~Supplier    = 'CHANGE_ME_VENDOR'
  INTO TABLE @DATA(lt_supplier).
```

---

## Q6 — cross-check ยอดจาก ACDOCA (ถ้าตัวเลขไม่ตรง)

`I_OperationalAcctgDocItem` มาจาก BSEG · `I_JournalEntryItem` มาจาก ACDOCA
ถ้าสองอันไม่ตรงแปลว่าเลือก ledger ผิดหรือมี item ที่ไม่ใช่ leading ledger

```abap
SELECT CompanyCode,
       FiscalYear,
       AccountingDocument,
       AccountingDocumentItem,
       GLAccount,
       AmountInTransactionCurrency,
       TransactionCurrency
  FROM I_JournalEntryItem
  WHERE CompanyCode        = 'CHANGE_ME_CCODE'
    AND FiscalYear         = 'CHANGE_ME_YEAR'
    AND AccountingDocument = 'CHANGE_ME_DOC1'
  INTO TABLE @DATA(lt_acdoca).
```

---

## รูปแบบผลลัพธ์ที่ส่งกลับมา

จาก Q1 + Q2 ส่งมาแค่นี้พอ

```
company_code : ____
currency     : ____
supplier     : ____

FinancialAccountType / Supplier / FiscalYear / AccountingDocument / AccountingDocumentItem / Amount
K / .......... / 2026 / .......... / 1 / +1,000.00
K / .......... / 2026 / .......... / 1 / -1,000.00
```

แล้วผมจะเอาไปเติมใน `get_apar_items( )` ของ `YCL_CLEARING_RUNNER` ให้

## ข้อควรระวังตอนอ่านผล

- `AmountInTransactionCurrency` ใน VDM เป็น **signed** (บวก = เดบิต, ลบ = เครดิต)
  ผลรวมต้อง = 0 เท่านั้นถึงจะ full clear ได้
- ถ้า `ClearingAccountingDocument` ไม่ว่าง = ถูก clear ไปแล้ว ใช้ไม่ได้
- ถ้า `SpecialGLCode` ไม่ว่าง = ข้ามไป API ไม่รองรับ
- item ที่ `TransactionCurrency` ต่างกัน อย่าเอามาปนใน request เดียว
