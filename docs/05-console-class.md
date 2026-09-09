# 05 — Console Class `YCL_CLEARING_RUNNER`

> **snapshot เพื่ออ่านอย่างเดียว** — source of truth คือ object บน tenant
> ผู้ใช้เป็นคน copy code นี้ไปสร้างใน ADT แล้ว push ผ่าน abapGit เอง
> ถ้าแก้บน tenant แล้ว ให้บอก Claude มาอัปเดตหน้านี้ตาม

## วิธีใช้

1. ADT → package `YPOC_CLEARING` → New → ABAP Class → `YCL_CLEARING_RUNNER`
2. วาง code ข้างล่างทับทั้งหมด → activate
3. แก้ constant ที่ขึ้นต้น `CHANGE_ME_` และ `get_apar_items( )` ให้เป็นค่าจริง
4. กด **F9** (Run as Console Application)

รอบแรกให้ `gc_test_run = 'true'` ก่อน (simulate) แล้วค่อยเปลี่ยนเป็น `'false'`

## สิ่งที่ class นี้ทำ

| ขั้น | รายละเอียด |
|---|---|
| 1 | generate Message ID (unique, < 35 chars) + WS-A MessageID (uuid) |
| 2 | ประกอบ SOAP envelope เป็น string — WS-A header + payload |
| 3 | ขอ destination จาก comm arrangement `YCS_CLEARING` |
| 4 | POST พร้อม header `Content-Type: text/xml` + `SOAPAction` |
| 5 | พิมพ์ request / HTTP status / body ออก console |

**ไม่ทำ**: ไม่ retry, ไม่ log ลง table, ไม่ตามผลจาก Message Dashboard ให้
เป็น POC ล้วน ๆ

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
        ref_doc_item   TYPE i,
        company_code   TYPE string,
        account_type   TYPE string,        "D = customer, K = vendor
        apar_account   TYPE string,
        fiscal_year    TYPE string,
        acctg_doc      TYPE string,
        acctg_doc_item TYPE string,
        partial_amount TYPE string,        "เว้นว่าง = full clearing
        diff_reason    TYPE string,
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
    CONSTANTS gc_comm_scenario TYPE string VALUE 'YCS_CLEARING'.
    CONSTANTS gc_service_id    TYPE string VALUE 'YOS_CLEARING_SOAP'.
    CONSTANTS gc_soap_action   TYPE string
      VALUE 'http://sap.com/xi/SAPSCORE/SFIN/JournalEntryBulkClearingRequest_In/JournalEntryBulkClearingRequest_InRequest'.

    "--- ข้อมูลทดสอบระดับ header : แก้ค่าตรงนี้ ---
    CONSTANTS gc_test_run      TYPE string VALUE 'true'.   "true = simulate, false = post จริง
    CONSTANTS gc_company_code  TYPE string VALUE 'CHANGE_ME_CCODE'.
    CONSTANTS gc_document_type TYPE string VALUE 'AB'.
    CONSTANTS gc_currency      TYPE string VALUE 'THB'.
    CONSTANTS gc_header_text   TYPE string VALUE 'POC Clearing via SOAP'.
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

    DATA(lv_payload) = build_envelope( iv_message_id     = lv_message_id
                                       iv_wsa_message_id = lv_wsa_msg_id ).

    out->write( |Message ID : { lv_message_id }| ).
    out->write( |Test run   : { gc_test_run }| ).
    out->write( `----- SOAP request -----` ).
    out->write( lv_payload ).

    TRY.
        DATA(lo_destination) = cl_http_destination_provider=>create_by_comm_arrangement(
                                 comm_scenario = gc_comm_scenario
                                 service_id    = gc_service_id ).

        DATA(lo_client) = cl_web_http_client_manager=>create_by_http_destination( lo_destination ).

        DATA(lo_request) = lo_client->get_http_request( ).
        lo_request->set_header_fields( VALUE #(
            ( name = 'Content-Type' value = 'text/xml; charset=utf-8' )
            ( name = 'SOAPAction'   value = gc_soap_action ) ) ).
        lo_request->set_text( lv_payload ).

        DATA(lo_response) = lo_client->execute( if_web_http_client=>post ).
        DATA(ls_status)   = lo_response->get_status( ).
        DATA(lv_body)     = lo_response->get_text( ).

        lo_client->close( ).

        out->write( `----- HTTP response -----` ).
        out->write( |HTTP { ls_status-code } { ls_status-reason }| ).
        out->write( COND string( WHEN lv_body IS INITIAL THEN `(body ว่าง — ปกติสำหรับ async)` ELSE lv_body ) ).

        IF ls_status-code = 202 OR ls_status-code = 200.
          out->write( |รับ request แล้ว — ผลจริงดูที่ Fiori app Message Dashboard ด้วย ID { lv_message_id }| ).
        ELSE.
          out->write( `ยิงไม่ผ่าน — ดู body ข้างบนเป็น SOAP fault` ).
        ENDIF.

      CATCH cx_http_dest_provider_error
            cx_web_http_client_error
            cx_web_message_error INTO DATA(lx_error).
        out->write( |ERROR: { lx_error->get_text( ) }| ).
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
        COND string( WHEN ls_apar-diff_reason IS NOT INITIAL
                     THEN |            <PaymentDifferenceReason>{ ls_apar-diff_reason }</PaymentDifferenceReason>\n| ) &&
        |          </APARItems>\n|.
    ENDLOOP.

  ENDMETHOD.


  METHOD get_apar_items.

    "ข้อมูลทดสอบ: open item ของ vendor 2 บรรทัดที่หักล้างกันพอดี
    "แทน CHANGE_ME_* ด้วยค่าจริงจากระบบ (ดู docs/04-test-data.md)
    rt_items = VALUE #(
      company_code = gc_company_code
      account_type = 'K'
      ( ref_doc_item   = 1
        apar_account   = 'CHANGE_ME_VENDOR'
        fiscal_year    = 'CHANGE_ME_YEAR'
        acctg_doc      = 'CHANGE_ME_DOC1'
        acctg_doc_item = '1' )
      ( ref_doc_item   = 2
        apar_account   = 'CHANGE_ME_VENDOR'
        fiscal_year    = 'CHANGE_ME_YEAR'
        acctg_doc      = 'CHANGE_ME_DOC2'
        acctg_doc_item = '1' ) ).

  ENDMETHOD.


  METHOD get_gl_items.

    "เว้นว่างไว้ = ไม่ clear ฝั่ง G/L
    "ถ้าจะทดสอบ G/L clearing ให้ย้ายมาใส่ที่นี่ แล้วเคลียร์ get_apar_items ให้ว่าง
    CLEAR rt_items.

  ENDMETHOD.

ENDCLASS.
```

## จุดที่ต้องแก้ถ้าเปลี่ยนเคส

| อยากทำ | แก้ที่ |
|---|---|
| clear ฝั่ง G/L แทน AP/AR | ใส่ข้อมูลใน `get_gl_items( )` แล้วให้ `get_apar_items( )` คืนค่าว่าง |
| partial clearing | ใส่ `partial_amount` (+ `diff_reason` ถ้ามี) ในบรรทัดที่ต้องการ |
| residual clearing | เพิ่ม node `CashDiscountAmountInDspCrcy` / `OtherDeductionAmountInDspCrcy` ใน `build_items_xml( )` |
| fix วันที่แทนวันนี้ | แก้ `lv_doc_date` ใน `build_envelope( )` เป็น literal `'2026-09-30'` |
| clear หลายเอกสารใน request เดียว | ทำ `JournalEntryClearingRequest` ซ้ำหลาย node ใน `build_envelope( )` |

## Troubleshooting

| อาการ | สาเหตุที่เจอบ่อย |
|---|---|
| `CX_HTTP_DEST_PROVIDER_ERROR` | comm arrangement `YCS_CLEARING` ยังไม่สร้าง หรือชื่อ scenario/service ไม่ตรง |
| HTTP 401 | communication user / password ใน arrangement ผิด |
| HTTP 404 | path ใน outbound service ผิด — ต้องเป็น `/sap/bc/srt/scs_ext/sap/journalentrybulkclearingreques` |
| HTTP 500 + SOAP fault `WS-Addressing` | header `wsa:Action` / `wsa:MessageID` หาย หรือ `SOAPAction` ไม่ตรง — ลองใส่ `"` ครอบค่า SOAPAction ดู |
| HTTP 202 แต่ Message Dashboard ขึ้นแดง | payload ถูกรับแล้วแต่ business error เช่น ยอดไม่ balance / period ปิด / item ถูก clear ไปแล้ว |
| ไม่เห็น message ใน dashboard เลย | Message ID ซ้ำกับที่เคยส่ง → ถูกมองเป็น duplicate |
