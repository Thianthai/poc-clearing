# 05 — Console Class `YCL_CLEARING_RUNNER`

> **snapshot เพื่ออ่านอย่างเดียว** — source of truth คือ object บน tenant
> ผู้ใช้เป็นคน copy code นี้ไปสร้างใน ADT แล้ว push ผ่าน abapGit เอง
> ถ้าแก้บน tenant แล้ว ให้บอก Claude มาอัปเดตหน้านี้ตาม

## สถานะ: มี test data จริงแล้ว (AR full clearing)

`get_apar_items( )` เติมข้อมูลจริงแล้ว (invoice 9400000005 กับ payment 3300000017
ของลูกค้า 0001000082 ยอด 6,418.93 THB หักล้างกันพอดี — ดู [04](04-test-data.md))
`get_gl_items( )` ต้องว่าง เพราะเคสนี้เป็น AR

class ยังตั้ง `gc_dry_run = abap_true` ไว้ → รันดู payload ได้โดยไม่ยิงจริง
พร้อมยิงเมื่อไหร่ค่อยเปลี่ยนเป็น `abap_false`

## วิธีใช้

1. ADT → package `YPOC_CLEARING` → New → ABAP Class → `YCL_CLEARING_RUNNER`
2. วาง code ข้างล่างทับทั้งหมด → activate → **F9** (Run as Console Application)
3. ได้ test data มาแล้ว → uncomment `get_gl_items( )` หรือ `get_apar_items( )`
   แล้วเติมค่าจริง
4. พร้อมยิงจริง → ตั้ง `gc_dry_run = abap_false` (ยังคง `gc_test_run = 'true'`
   เพื่อให้ SAP simulate ก่อน)
5. ผ่านแล้วค่อยตั้ง `gc_test_run = 'false'` เพื่อ post จริง

## สวิตช์ 2 ตัวที่ต้องเข้าใจ

| Constant | ค่า | ผล |
|---|---|---|
| `gc_dry_run` | `abap_true` | ประกอบ payload พิมพ์ออกจอ **ไม่ยิง** |
| | `abap_false` | ยิงออกไปจริง |
| `gc_test_run` | `'true'` | ยิงจริง แต่บอก SAP ให้ simulate ไม่ post เอกสาร |
| | `'false'` | post เอกสาร clearing จริง |

## สิ่งที่ class นี้ทำ

| ขั้น | รายละเอียด |
|---|---|
| 1 | generate Message ID (unique, < 35 chars) + WS-A MessageID (uuid) |
| 2 | เช็คว่ามี item ให้ clear ไหม ถ้าไม่มีก็หยุด |
| 3 | ประกอบ SOAP envelope เป็น string — WS-A header + payload |
| 4 | ถ้า dry run → พิมพ์แล้วจบ |
| 5 | ขอ destination จาก comm arrangement `ZCS_SPORTPACKAGE_CLEARING` แล้ว POST |
| 6 | พิมพ์ HTTP status / body ออก console |

รองรับครบทั้ง full / partial / residual clearing ผ่าน field ใน `ty_apar_item`

**ไม่ทำ**: ไม่ retry, ไม่ log ลง table, ไม่ตามผลจาก Message Dashboard ให้

## Source

```abap
CLASS ycl_clearing_runner DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.

    TYPES:
      "! open item ฝั่ง customer / vendor ที่จะ clear
      BEGIN OF ty_apar_item,
        ref_doc_item    TYPE i,
        company_code    TYPE string,
        account_type    TYPE string,       "D = customer, K = vendor
        apar_account    TYPE string,
        fiscal_year     TYPE string,
        acctg_doc       TYPE string,
        acctg_doc_item  TYPE string,
        partial_amount  TYPE string,       "partial clearing
        cash_discount   TYPE string,       "residual: ส่วนลดเงินสด
        other_deduction TYPE string,       "residual: ยอดคงเหลือ (ใส่ค่าติดลบ)
        diff_reason     TYPE string,       "reason code ของผลต่าง
      END OF ty_apar_item,
      tt_apar_item TYPE STANDARD TABLE OF ty_apar_item WITH EMPTY KEY,

      "! open item ฝั่ง G/L ที่จะ clear
      BEGIN OF ty_gl_item,
        ref_doc_item   TYPE i,
        company_code   TYPE string,
        gl_account     TYPE string,
        fiscal_year    TYPE string,
        acctg_doc      TYPE string,
        acctg_doc_item TYPE string,
      END OF ty_gl_item,
      tt_gl_item TYPE STANDARD TABLE OF ty_gl_item WITH EMPTY KEY.

    "--- destination (ดู docs/02-communication-setup.md) ---
    CONSTANTS gc_comm_scenario TYPE char30 VALUE 'ZCS_SPORTPACKAGE_CLEARING'.
    CONSTANTS gc_service_id    TYPE char40 VALUE 'ZAPI_SPORTPACKAGE_CLEARING_REST'.
    CONSTANTS gc_soap_action   TYPE string
      VALUE 'http://sap.com/xi/SAPSCORE/SFIN/JournalEntryBulkClearingRequest_In/JournalEntryBulkClearingRequest_InRequest'.

    "--- โหมดการรัน ---
    "gc_dry_run  = X  → ประกอบ payload แล้วพิมพ์ออกจอเฉย ๆ ไม่ยิงจริง
    "                   ใช้ตอนยังไม่มี comm arrangement / ยังไม่มี test data
    "gc_test_run = true → ยิงจริงแต่ให้ SAP simulate ไม่ post เอกสาร
    CONSTANTS gc_dry_run  TYPE abap_bool     VALUE abap_true.
    CONSTANTS gc_test_run TYPE string       VALUE 'true'.

    "--- ข้อมูลทดสอบระดับ header ---
    CONSTANTS gc_company_code  TYPE string VALUE '1000'.
    CONSTANTS gc_document_type TYPE string VALUE 'AB'.
    CONSTANTS gc_currency      TYPE string VALUE 'THB'.
    CONSTANTS gc_header_text   TYPE string VALUE 'POC Clearing via SOAP'.
    CONSTANTS gc_reference_doc TYPE string VALUE 'POC-CLEAR'.
    CONSTANTS gc_created_by    TYPE string VALUE 'POC_USER'.

    METHODS get_apar_items
      RETURNING VALUE(rt_items) TYPE tt_apar_item.

    METHODS get_gl_items
      RETURNING VALUE(rt_items) TYPE tt_gl_item.

    METHODS build_items_xml
      RETURNING VALUE(rv_xml) TYPE string.

    METHODS build_envelope
      IMPORTING iv_message_id     TYPE string
                iv_wsa_message_id TYPE string
      RETURNING VALUE(rv_xml)     TYPE string.

    METHODS send_request
      IMPORTING iv_payload TYPE string
                io_out     TYPE REF TO if_oo_adt_classrun_out.

ENDCLASS.


CLASS ycl_clearing_runner IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.

    "1) Message ID ต้อง unique และสั้นกว่า 35 ตัวอักษร
    TRY.
        DATA(lv_uuid32)     = cl_system_uuid=>create_uuid_c32_static( ).
        DATA(lv_message_id) = |POC_{ lv_uuid32+0(24) }|.
        DATA(lv_wsa_msg_id) = |uuid:{ cl_system_uuid=>create_uuid_c36_static( ) }|.
      CATCH cx_uuid_error INTO DATA(lx_uuid).
        out->write( |สร้าง UUID ไม่ได้: { lx_uuid->get_text( ) }| ).
        RETURN.
    ENDTRY.

    "2) เช็คว่ามี item ให้ clear จริงไหม
    DATA(lv_item_count) = lines( get_gl_items( ) ) + lines( get_apar_items( ) ).

    out->write( |Message ID  : { lv_message_id }| ).
    out->write( |Company code: { gc_company_code }| ).
    out->write( |Items       : { lv_item_count }| ).
    out->write( |Test run    : { gc_test_run }| ).
    out->write( |Dry run     : { gc_dry_run }| ).

    IF lv_item_count = 0.
      out->write( `ยังไม่มี open item ใน get_gl_items( ) / get_apar_items( ) — เติมข้อมูลก่อน` ).
      RETURN.
    ENDIF.

    "3) ประกอบ payload
    DATA(lv_payload) = build_envelope( iv_message_id     = lv_message_id
                                       iv_wsa_message_id = lv_wsa_msg_id ).

    out->write( `----- SOAP request -----` ).
    out->write( lv_payload ).

    "4) ยิงจริง (ข้ามถ้าอยู่ในโหมด dry run)
    IF gc_dry_run = abap_true.
      out->write( `DRY RUN — ยังไม่ได้ยิงออกไป ตั้ง gc_dry_run = abap_false เมื่อพร้อม` ).
      RETURN.
    ENDIF.

    send_request( iv_payload = lv_payload
                  io_out     = out ).

    out->write( |ตามผลที่ Fiori app Message Dashboard ด้วย ID { lv_message_id }| ).

  ENDMETHOD.


  METHOD send_request.

    TRY.
        DATA(lo_destination) = cl_http_destination_provider=>create_by_comm_arrangement(
                                 comm_scenario = gc_comm_scenario
                                 service_id    = gc_service_id ).

        DATA(lo_client) = cl_web_http_client_manager=>create_by_http_destination( lo_destination ).

        DATA(lo_request) = lo_client->get_http_request( ).
        lo_request->set_header_fields( VALUE #(
            ( name = 'Content-Type' value = 'text/xml; charset=utf-8' )
            ( name = 'SOAPAction'   value = gc_soap_action ) ) ).
        lo_request->set_text( iv_payload ).

        DATA(lo_response) = lo_client->execute( if_web_http_client=>post ).
        DATA(ls_status)   = lo_response->get_status( ).
        DATA(lv_body)     = lo_response->get_text( ).

        lo_client->close( ).

        io_out->write( `----- HTTP response -----` ).
        io_out->write( |HTTP { ls_status-code } { ls_status-reason }| ).
        io_out->write( COND string( WHEN lv_body IS INITIAL
                                    THEN `(body ว่าง — ปกติสำหรับ async)`
                                    ELSE lv_body ) ).

        IF ls_status-code <> 202 AND ls_status-code <> 200.
          io_out->write( `ยิงไม่ผ่าน — body ข้างบนคือ SOAP fault` ).
        ENDIF.

      CATCH cx_http_dest_provider_error
            cx_web_http_client_error
            cx_web_message_error INTO DATA(lx_error).
        io_out->write( |ERROR: { lx_error->get_text( ) }| ).
    ENDTRY.

  ENDMETHOD.


  METHOD build_envelope.

    "วันที่เอกสาร / วันที่ผ่านรายการ = วันนี้ (แก้เป็นค่า fix ได้ที่นี่)
    DATA(lv_doc_date) = |{ cl_abap_context_info=>get_system_date( ) DATE = ISO }|.

    DATA lv_utc_date TYPE d.
    DATA lv_utc_time TYPE t.
    DATA(lv_utc) = utclong_current( ).
    CONVERT UTCLONG lv_utc INTO DATE lv_utc_date TIME lv_utc_time TIME ZONE 'UTC'.
    DATA(lv_created_at) = |{ lv_utc_date DATE = ISO }T{ lv_utc_time TIME = ISO }Z|.

    rv_xml =
      |<?xml version="1.0" encoding="UTF-8"?>\n| &&
      |<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"| &&
      | xmlns:sfin="http://sap.com/xi/SAPSCORE/SFIN">\n| &&
      |  <soapenv:Header xmlns:wsa="http://www.w3.org/2005/08/addressing">\n| &&
      |    <wsa:Action soapenv:mustUnderstand="1">{ gc_soap_action }</wsa:Action>\n| &&
      |    <wsa:MessageID soapenv:mustUnderstand="1">{ iv_wsa_message_id }</wsa:MessageID>\n| &&
      |  </soapenv:Header>\n| &&
      |  <soapenv:Body>\n| &&
      |    <sfin:JournalEntryBulkClearingRequest>\n| &&
      |      <MessageHeader>\n| &&
      |        <ID>{ iv_message_id }</ID>\n| &&
      |        <CreationDateTime>{ lv_created_at }</CreationDateTime>\n| &&
      |        <TestDataIndicator>{ gc_test_run }</TestDataIndicator>\n| &&
      |      </MessageHeader>\n| &&
      |      <JournalEntryClearingRequest>\n| &&
      |        <MessageHeader>\n| &&
      |          <ID>{ iv_message_id }_01</ID>\n| &&
      |          <CreationDateTime>{ lv_created_at }</CreationDateTime>\n| &&
      |        </MessageHeader>\n| &&
      |        <JournalEntry>\n| &&
      |          <CompanyCode>{ gc_company_code }</CompanyCode>\n| &&
      |          <AccountingDocumentType>{ gc_document_type }</AccountingDocumentType>\n| &&
      |          <DocumentDate>{ lv_doc_date }</DocumentDate>\n| &&
      |          <PostingDate>{ lv_doc_date }</PostingDate>\n| &&
      |          <CurrencyCode>{ gc_currency }</CurrencyCode>\n| &&
      |          <DocumentHeaderText>| &&
      |{ escape( val = gc_header_text format = cl_abap_format=>e_xml_text ) }| &&
      |</DocumentHeaderText>\n| &&
      |          <ReferenceDocument>| &&
      |{ escape( val = gc_reference_doc format = cl_abap_format=>e_xml_text ) }| &&
      |</ReferenceDocument>\n| &&
      |          <CreatedByUser>{ gc_created_by }</CreatedByUser>\n| &&
      build_items_xml( ) &&
      |        </JournalEntry>\n| &&
      |      </JournalEntryClearingRequest>\n| &&
      |    </sfin:JournalEntryBulkClearingRequest>\n| &&
      |  </soapenv:Body>\n| &&
      |</soapenv:Envelope>|.

  ENDMETHOD.


  METHOD build_items_xml.

    DATA(lt_gl) = get_gl_items( ).
    LOOP AT lt_gl INTO DATA(ls_gl).
      rv_xml = rv_xml &&
        |          <GLItems>\n| &&
        |            <ReferenceDocumentItem>{ ls_gl-ref_doc_item }</ReferenceDocumentItem>\n| &&
        COND string( WHEN ls_gl-company_code IS NOT INITIAL
                     THEN |            <CompanyCode>{ ls_gl-company_code }</CompanyCode>\n| ) &&
        |            <GLAccount>{ ls_gl-gl_account }</GLAccount>\n| &&
        |            <FiscalYear>{ ls_gl-fiscal_year }</FiscalYear>\n| &&
        |            <AccountingDocument>{ ls_gl-acctg_doc }</AccountingDocument>\n| &&
        |            <AccountingDocumentItem>{ ls_gl-acctg_doc_item }</AccountingDocumentItem>\n| &&
        |          </GLItems>\n|.
    ENDLOOP.

    DATA(lt_apar) = get_apar_items( ).
    LOOP AT lt_apar INTO DATA(ls_apar).
      rv_xml = rv_xml &&
        |          <APARItems>\n| &&
        |            <ReferenceDocumentItem>{ ls_apar-ref_doc_item }</ReferenceDocumentItem>\n| &&
        COND string( WHEN ls_apar-company_code IS NOT INITIAL
                     THEN |            <CompanyCode>{ ls_apar-company_code }</CompanyCode>\n| ) &&
        |            <AccountType>{ ls_apar-account_type }</AccountType>\n| &&
        |            <APARAccount>{ ls_apar-apar_account }</APARAccount>\n| &&
        |            <FiscalYear>{ ls_apar-fiscal_year }</FiscalYear>\n| &&
        |            <AccountingDocument>{ ls_apar-acctg_doc }</AccountingDocument>\n| &&
        |            <AccountingDocumentItem>{ ls_apar-acctg_doc_item }</AccountingDocumentItem>\n| &&
        COND string( WHEN ls_apar-partial_amount IS NOT INITIAL
                     THEN |            <PartialPaymentAmtInDspCrcy currencyCode="{ gc_currency }">| &&
                          |{ ls_apar-partial_amount }</PartialPaymentAmtInDspCrcy>\n| ) &&
        COND string( WHEN ls_apar-cash_discount IS NOT INITIAL
                     THEN |            <CashDiscountAmountInDspCrcy currencyCode="{ gc_currency }">| &&
                          |{ ls_apar-cash_discount }</CashDiscountAmountInDspCrcy>\n| ) &&
        COND string( WHEN ls_apar-other_deduction IS NOT INITIAL
                     THEN |            <OtherDeductionAmountInDspCrcy currencyCode="{ gc_currency }">| &&
                          |{ ls_apar-other_deduction }</OtherDeductionAmountInDspCrcy>\n| ) &&
        COND string( WHEN ls_apar-diff_reason IS NOT INITIAL
                     THEN |            <PaymentDifferenceReason>{ ls_apar-diff_reason }</PaymentDifferenceReason>\n| ) &&
        |          </APARItems>\n|.
    ENDLOOP.

  ENDMETHOD.


  METHOD get_apar_items.

    "==========================================================
    " Test case จาก functional (2026-09-09) — เคส AR full clearing
    "   SO JA30000116 > billing JA70000046
    "   invoice 9400000005/2026 item 001 : +6,418.93  (PK 01)
    "   payment 3300000017/2026 item 005 : -6,418.93  (PK 15)
    "   customer 0001000082 · THB · รวมกัน = 0.00 พอดี
    " ระวัง: เอกสารเลขเดียวกันมีใน FY2025 ด้วย ต้องระบุ fiscal_year เสมอ
    "==========================================================
    rt_items = VALUE #(
      company_code = gc_company_code
      account_type = 'D'
      apar_account = '0001000082'
      fiscal_year  = '2026'
      ( ref_doc_item   = 1
        acctg_doc      = '9400000005'
        acctg_doc_item = '001' )
      ( ref_doc_item   = 2
        acctg_doc      = '3300000017'
        acctg_doc_item = '005' ) ).

  ENDMETHOD.


  METHOD get_gl_items.

    "==========================================================
    " เคส G/L — รอ test data จาก functional
    " บัญชีต้อง IsOpenItemManaged = 'X'
    "==========================================================
*    rt_items = VALUE #(
*      company_code = gc_company_code
*      ( ref_doc_item   = 1
*        gl_account     = 'CHANGE_ME_GLACCT'
*        fiscal_year    = 'CHANGE_ME_YEAR'
*        acctg_doc      = 'CHANGE_ME_DOC1'
*        acctg_doc_item = '1' )
*      ( ref_doc_item   = 2
*        gl_account     = 'CHANGE_ME_GLACCT'
*        fiscal_year    = 'CHANGE_ME_YEAR'
*        acctg_doc      = 'CHANGE_ME_DOC2'
*        acctg_doc_item = '1' ) ).

    "เคสปัจจุบันเป็น AR → ฝั่ง G/L ต้องว่าง ห้าม uncomment block ข้างบน

  ENDMETHOD.

ENDCLASS.
```

## จุดที่ต้องแก้ถ้าเปลี่ยนเคส

| อยากทำ | แก้ที่ |
|---|---|
| full clearing G/L | uncomment `get_gl_items( )` เติม `gl_account` + เลขเอกสาร |
| full clearing AP/AR | uncomment `get_apar_items( )` ตั้ง `account_type` = `K` หรือ `D` |
| partial clearing | ใส่ `partial_amount` (+ `diff_reason` ถ้ามี) ในบรรทัดที่จ่ายบางส่วน |
| residual clearing | ใส่ `cash_discount` และ/หรือ `other_deduction` (ค่าติดลบ) |
| fix วันที่แทนวันนี้ | แก้ `lv_doc_date` ใน `build_envelope( )` เป็น literal `'2026-09-30'` |
| clear หลายเอกสารใน request เดียว | ทำ `JournalEntryClearingRequest` ซ้ำหลาย node ใน `build_envelope( )` |

> partial clearing ใช้ร่วมกับ cash discount / residual **ไม่ได้** เป็นข้อจำกัดของ API

## Troubleshooting

| อาการ | สาเหตุที่เจอบ่อย |
|---|---|
| `CX_HTTP_DEST_PROVIDER_ERROR` | comm arrangement `ZCS_SPORTPACKAGE_CLEARING` ยังไม่สร้าง หรือชื่อ scenario/service ไม่ตรง |
| HTTP 401 | communication user / password ใน arrangement ผิด |
| HTTP 404 | path ใน outbound service ผิด — ต้องเป็น `/sap/bc/srt/scs_ext/sap/journalentrybulkclearingreques` |
| HTTP 500 + SOAP fault `WS-Addressing` | header `wsa:Action` / `wsa:MessageID` หาย หรือ `SOAPAction` ไม่ตรง — ลองใส่ `"` ครอบค่า SOAPAction ดู |
| HTTP 202 แต่ Message Dashboard ขึ้นแดง | payload ถูกรับแล้วแต่ business error เช่น ยอดไม่ balance / period ปิด / item ถูก clear ไปแล้ว |
| *There are no open items managed in Account* | บัญชี G/L ไม่ได้เปิด open item management |
| ไม่เห็น message ใน dashboard เลย | Message ID ซ้ำกับที่เคยส่ง → ถูกมองเป็น duplicate |

## Watch list ตอนยิงจริงครั้งแรก

| field | ความเสี่ยง | ถ้าพัง |
|---|---|---|
| `CreatedByUser` = `POC_USER` | เป็น field optional ถ้าระบบ validate กับ user จริงจะไม่ผ่าน | ลบ node นี้ออกจาก `build_envelope( )` ไปเลย หรือใส่ user จริง |
| `AccountingDocumentType` = `AB` | config อาจจำกัด account type ที่ doc type นี้รับได้ | เปลี่ยนเป็น `DZ` (เคส customer) |
| `AccountingDocumentItem` = `001` | ถ้า API ต้องการ external format | ตัด leading zero เหลือ `1` / `5` |
| `APARAccount` = `0001000082` | เช่นเดียวกัน | ตัดเหลือ `1000082` |
| `SOAPAction` ไม่มี `"` ครอบ | บาง stack ต้องการ quote | ใส่ `"` ครอบค่าใน `set_header_fields( )` |

ทั้ง 5 อันแก้ที่เดียวคือ constant หรือ `build_envelope( )` ไม่ต้องรื้อโครงสร้าง
