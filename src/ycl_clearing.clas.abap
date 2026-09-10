CLASS ycl_clearing DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.

    TYPES:
*      "! customer/vendor open item
*      BEGIN OF ty_apar_item,
*        ref_doc_item    TYPE i,
*        company_code    TYPE string,
*        account_type    TYPE string,       "D = customer, K = vendor
*        apar_account    TYPE string,
*        fiscal_year     TYPE string,
*        acctg_doc       TYPE string,
*        acctg_doc_item  TYPE string,
*        partial_amount  TYPE string,       "partial clearing
*        cash_discount   TYPE string,       "residual: ส่วนลดเงินสด
*        other_deduction TYPE string,       "residual: ยอดคงเหลือ (ใส่ค่าติดลบ)
*        diff_reason     TYPE string,       "reason code ของผลต่าง
*      END OF ty_apar_item,
*      tt_apar_item TYPE STANDARD TABLE OF ty_apar_item WITH EMPTY KEY,

      "! customer/vendor open item
      BEGIN OF ty_apar_item,
        ref_doc_item   TYPE i,
        company_code   TYPE string,
        account_type   TYPE string,       "D = customer, K = vendor
        apar_account   TYPE string,
        fiscal_year    TYPE string,
        acctg_doc      TYPE string,
        acctg_doc_item TYPE string,
      END OF ty_apar_item,
      tt_apar_item TYPE STANDARD TABLE OF ty_apar_item WITH EMPTY KEY,

      "! g/l open item
      BEGIN OF ty_gl_item,
        ref_doc_item   TYPE i,
        company_code   TYPE string,
        gl_account     TYPE string,
        fiscal_year    TYPE string,
        acctg_doc      TYPE string,
        acctg_doc_item TYPE string,
      END OF ty_gl_item,
      tt_gl_item TYPE STANDARD TABLE OF ty_gl_item WITH EMPTY KEY.

    "--- destination ---
    CONSTANTS gc_comm_scenario TYPE c LENGTH 30 VALUE 'ZCS_SPORTPACKAGE_CLEARING'.
    CONSTANTS gc_service_id    TYPE c LENGTH 40 VALUE 'ZAPI_SPORTPACKAGE_CLEARING_REST'.
    CONSTANTS gc_soap_action   TYPE string VALUE 'http://sap.com/xi/SAPSCORE/SFIN/JournalEntryBulkClearingRequest_In/JournalEntryBulkClearingRequest_InRequest'.

    CONSTANTS gc_dry_run  TYPE abap_bool VALUE abap_false.
    CONSTANTS gc_test_run TYPE string    VALUE 'false'. "ยิงจริงแต่ให้ SAP simulate ไม่ post เอกสาร

    CONSTANTS gc_company_code  TYPE string VALUE '1000'.
    CONSTANTS gc_document_type TYPE string VALUE 'DA'.
    CONSTANTS gc_currency      TYPE string VALUE 'THB'.
    CONSTANTS gc_header_text   TYPE string VALUE 'POC Clearing via SOAP'.
    CONSTANTS gc_reference_doc TYPE string VALUE 'POC-CLEAR'.
    CONSTANTS gc_created_by    TYPE string VALUE 'POC_USER'.

    "! G/L Deferred Output Tax — ต้อง clear คู่ไปกับฝั่ง AR เสมอ
    CONSTANTS gc_gl_deferred_tax TYPE string VALUE '0021082005'.

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


CLASS ycl_clearing IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.

    "----------------------------------------------------------
    " เก็บไว้ reuse — query ตรวจ open item ก่อนยิง
    " ใช้ยืนยันว่าบรรทัดที่จะ clear ยัง open อยู่จริง ยอดรวม = 0
    " และ ClearingAccountingDocument ยังว่าง
    "----------------------------------------------------------
*    SELECT CompanyCode,
*           FinancialAccountType,
*           Customer,
*           Supplier,
*           GLAccount,
*           FiscalYear,
*           AccountingDocument,
*           AccountingDocumentItem,
*           PostingKey,
*           DebitCreditCode,
*           TransactionCurrency,
*           AmountInTransactionCurrency,
*           PostingDate,
*           DocumentDate,
*           AccountingDocumentType,
*           SpecialGLCode,
*           IsOpenItemManaged,
*           ClearingAccountingDocument,
*           ClearingDate,
*           AssignmentReference,
*           DocumentItemText
*      FROM I_OperationalAcctgDocItem
*      WHERE CompanyCode        = '1000'
*        AND AccountingDocument IN ( '9400000005', '3300000017' )
*      ORDER BY AccountingDocument, AccountingDocumentItem
*      INTO TABLE @DATA(lt_case).

    "1) set message id
    TRY.
        DATA(lv_uuid32)     = cl_system_uuid=>create_uuid_c32_static( ).
        DATA(lv_message_id) = |POC_{ lv_uuid32+0(24) }|.
        DATA(lv_wsa_msg_id) = |uuid:{ cl_system_uuid=>create_uuid_c36_static( ) }|.
      CATCH cx_uuid_error INTO DATA(lx_uuid).
        out->write( |สร้าง UUID ไม่ได้: { lx_uuid->get_text( ) }| ).
        RETURN.
    ENDTRY.

    "2) check clearing item
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

    "3) build payload
    DATA(lv_payload) = build_envelope( iv_message_id     = lv_message_id
                                       iv_wsa_message_id = lv_wsa_msg_id ).

    out->write( `----- SOAP request -----` ).
    out->write( lv_payload ).

    "4) call api
    IF gc_dry_run = abap_true.
      out->write( `DRY RUN — ยังไม่ได้ยิงออกไป ตั้ง gc_dry_run = abap_false เมื่อพร้อม` ).
      RETURN.
    ENDIF.

    send_request( iv_payload = lv_payload
                  io_out     = out ).

    out->write( |ตามผลที่ Fiori app Message Dashboard ด้วย ID { lv_message_id }| ).

  ENDMETHOD.


  METHOD send_request.

    io_out->write( |Scenario    : { gc_comm_scenario }| ).
    io_out->write( |Service ID  : { gc_service_id }| ).

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

      CATCH cx_http_dest_provider_error INTO DATA(lx_dest).
        io_out->write( |ERROR (destination): { lx_dest->get_text( ) }| ).

      CATCH cx_web_http_client_error
            cx_web_message_error INTO DATA(lx_error).
        io_out->write( |ERROR (http): { lx_error->get_text( ) }| ).
    ENDTRY.

  ENDMETHOD.


  METHOD build_envelope.

    "วันที่เอกสาร/วันที่ผ่านรายการ
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
      |          <DocumentHeaderText>| && |{ escape( val = gc_header_text format = cl_abap_format=>e_xml_text ) }| && |</DocumentHeaderText>\n| &&
      |          <ReferenceDocument>| && |{ escape( val = gc_reference_doc format = cl_abap_format=>e_xml_text ) }| && |</ReferenceDocument>\n| &&
      |          <CreatedByUser>{ gc_created_by }</CreatedByUser>\n| && build_items_xml( ) &&
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
        |          </APARItems>\n|.
    ENDLOOP.

*    DATA(lt_gl) = get_gl_items( ).
*    LOOP AT lt_gl INTO DATA(ls_gl).
*      rv_xml = rv_xml &&
*        |          <GLItems>\n| &&
*        |            <ReferenceDocumentItem>{ ls_gl-ref_doc_item }</ReferenceDocumentItem>\n| &&
*        COND string( WHEN ls_gl-company_code IS NOT INITIAL
*                     THEN |            <CompanyCode>{ ls_gl-company_code }</CompanyCode>\n| ) &&
*        |            <GLAccount>{ ls_gl-gl_account }</GLAccount>\n| &&
*        |            <FiscalYear>{ ls_gl-fiscal_year }</FiscalYear>\n| &&
*        |            <AccountingDocument>{ ls_gl-acctg_doc }</AccountingDocument>\n| &&
*        |            <AccountingDocumentItem>{ ls_gl-acctg_doc_item }</AccountingDocumentItem>\n| &&
*        |          </GLItems>\n|.
*    ENDLOOP.
*
*    DATA(lt_apar) = get_apar_items( ).
*    LOOP AT lt_apar INTO DATA(ls_apar).
*      rv_xml = rv_xml &&
*        |          <APARItems>\n| &&
*        |            <ReferenceDocumentItem>{ ls_apar-ref_doc_item }</ReferenceDocumentItem>\n| &&
*        COND string( WHEN ls_apar-company_code IS NOT INITIAL
*                     THEN |            <CompanyCode>{ ls_apar-company_code }</CompanyCode>\n| ) &&
*        |            <AccountType>{ ls_apar-account_type }</AccountType>\n| &&
*        |            <APARAccount>{ ls_apar-apar_account }</APARAccount>\n| &&
*        |            <FiscalYear>{ ls_apar-fiscal_year }</FiscalYear>\n| &&
*        |            <AccountingDocument>{ ls_apar-acctg_doc }</AccountingDocument>\n| &&
*        |            <AccountingDocumentItem>{ ls_apar-acctg_doc_item }</AccountingDocumentItem>\n| &&
*        COND string( WHEN ls_apar-partial_amount IS NOT INITIAL
*                     THEN |            <PartialPaymentAmtInDspCrcy currencyCode="{ gc_currency }">| &&
*                          |{ ls_apar-partial_amount }</PartialPaymentAmtInDspCrcy>\n| ) &&
*        COND string( WHEN ls_apar-cash_discount IS NOT INITIAL
*                     THEN |            <CashDiscountAmountInDspCrcy currencyCode="{ gc_currency }">| &&
*                          |{ ls_apar-cash_discount }</CashDiscountAmountInDspCrcy>\n| ) &&
*        COND string( WHEN ls_apar-other_deduction IS NOT INITIAL
*                     THEN |            <OtherDeductionAmountInDspCrcy currencyCode="{ gc_currency }">| &&
*                          |{ ls_apar-other_deduction }</OtherDeductionAmountInDspCrcy>\n| ) &&
*        COND string( WHEN ls_apar-diff_reason IS NOT INITIAL
*                     THEN |            <PaymentDifferenceReason>{ ls_apar-diff_reason }</PaymentDifferenceReason>\n| ) &&
*        |          </APARItems>\n|.
*    ENDLOOP.

  ENDMETHOD.


  METHOD get_apar_items.

    " Test case: AR full clearing
    "   ทุกบรรทัดต้องเป็น open item จริง ยอดรวม (signed) = 0
    "   SpecialGLCode ต้องว่าง (API ไม่รองรับ special G/L)
    " SO JA30000116 > billing JA70000046
    " invoice 9400000005/2026 item 001 : +6,418.93  (PK 01)
    " payment 3300000017/2026 item 005 : -6,418.93  (PK 15)
    " customer 0001000082 - THB - รวมกัน = 0.00 พอดี
    rt_items = VALUE #(
      company_code = gc_company_code
      account_type = 'D'
      apar_account = '0001000082'
      fiscal_year  = '2026'
      ( ref_doc_item   = 3
        acctg_doc      = '9400000005'
        acctg_doc_item = '001' )
      ( ref_doc_item   = 4
        acctg_doc      = '3300000017'
        acctg_doc_item = '005' ) ).

  ENDMETHOD.


  METHOD get_gl_items.

    " Deferred Output Tax — functional ยืนยันว่าต้อง clear คู่กับฝั่ง AR
    "   invoice 9400000005/2026 item 003 : -419.93
    "   payment 3300000017/2026 item 003 : +419.93
    "   G/L 0021082005 - IsOpenItemManaged = 'X' - รวมกัน = 0.00 พอดี
    " GLItems ถูก emit ก่อน APARItems จึงใช้ ReferenceDocumentItem 1-2
    rt_items = VALUE #(
      company_code = gc_company_code
      gl_account   = gc_gl_deferred_tax
      fiscal_year  = '2026'
      ( ref_doc_item   = 1
        acctg_doc      = '9400000005'
        acctg_doc_item = '003' )
      ( ref_doc_item   = 2
        acctg_doc      = '3300000017'
        acctg_doc_item = '003' ) ).

  ENDMETHOD.

ENDCLASS.
