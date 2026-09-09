# 02 — Communication Setup

console class ยิง SOAP ไปที่ **inbound service ของ tenant ตัวเอง** จึงต้อง config
สองฝั่ง คือ ฝั่ง **inbound** (ให้ service เปิดรับ) และฝั่ง **outbound**
(ให้ ABAP มี destination + credential ยิงออก)

```
ADT (dev)                          Fiori (config)                tenant runtime
─────────                          ──────────────                ──────────────
YOS_CLEARING_SOAP  ─┐
 (outbound service) │
                    ├─▶ Communication Arrangement  ─▶  destination + basic auth
YCS_CLEARING       ─┘        (YCS_CLEARING)                      │
 (comm scenario)                                                 ▼
                    Communication Arrangement SAP_COM_0002  ─▶  /sap/bc/srt/scs_ext/sap/
                     (inbound, เปิดรับ clearing)                journalentrybulkclearingreques
```

## ส่วนที่ 1 — เปิด inbound service (SAP_COM_0002)

1. Fiori app **Communication Systems** → สร้าง communication system
   (host = ตัวเอง, inbound user = communication user)
2. Fiori app **Communication Users** → สร้าง user + password
   จดไว้ ใช้ทั้ง inbound และ outbound
3. Fiori app **Communication Arrangements** → New →
   scenario **SAP_COM_0002 (Finance – Posting Integration)**
4. ในแท็บ *Inbound Services* ต้องเห็น
   **Journal Entry – Clearing (Asynchronous)** และติ๊ก active
5. copy **Service URL** ที่แสดงในหน้านั้นไว้ หน้าตาประมาณ

```
https://myXXXXXX-api.s4hana.cloud.sap/sap/bc/srt/scs_ext/sap/journalentrybulkclearingreques
```

> ทดสอบด้วย SOAPUI/Postman ก่อนเขียน ABAP จะ debug ง่ายกว่ามาก
> ใน SOAPUI ต้องติ๊ก **WS-A addressing** + **Generate MessageID**

## ส่วนที่ 2 — สร้าง destination สำหรับยิงออก (ทำใน ADT)

### 2.1 Outbound Service

ADT → package `YPOC_CLEARING` → New → Other ABAP Repository Object →
Cloud Communication Management → **Outbound Service**

| ช่อง | ค่า |
|---|---|
| Name | `YOS_CLEARING_SOAP` |
| Description | Journal Entry Bulk Clearing (SOAP inbound) |
| Service Type | **HTTP** |
| Default Path Prefix | `/sap/bc/srt/scs_ext/sap/journalentrybulkclearingreques` |

### 2.2 Communication Scenario

ADT → New → **Communication Scenario**

| ช่อง | ค่า |
|---|---|
| Name | `YCS_CLEARING` |
| Description | POC Journal Entry Clearing |
| Allowed Instances | Multiple |

แท็บ *Outbound* → เพิ่ม `YOS_CLEARING_SOAP`
→ Supported Authentication Methods: **User Name and Password**

publish scenario แล้ว activate

### 2.3 Communication Arrangement (Fiori)

Fiori app **Communication Arrangements** → New →
scenario `YCS_CLEARING`

| ช่อง | ค่า |
|---|---|
| Communication System | ตัว tenant เอง (host `myXXXXXX-api.s4hana.cloud.sap`, port 443) |
| Outbound user | communication user จากข้อ 1.2 |
| Outbound Service `YOS_CLEARING_SOAP` | ติ๊ก active, path ตามข้อ 2.1 |

> **credential อยู่ที่นี่ที่เดียว** ห้ามย้ายไป hardcode ใน ABAP

## ส่วนที่ 3 — ตรวจว่า ABAP หา destination เจอ

console class เรียก

```abap
cl_http_destination_provider=>create_by_comm_arrangement(
  comm_scenario = 'YCS_CLEARING'
  service_id    = 'YOS_CLEARING_SOAP' )
```

ถ้า throw `CX_HTTP_DEST_PROVIDER_ERROR` แปลว่า comm arrangement ยังไม่ถูกสร้าง
หรือชื่อ scenario/service ไม่ตรง

## ทางเลือกที่ **ไม่แนะนำ**

`cl_http_destination_provider=>create_by_url( )` + `set_authorization_basic( )`
ทำงานได้และเซ็ตเร็วกว่า แต่ต้องเอา user/password ใส่ไว้ใน source code
→ ห้ามใช้ใน repo นี้

## Checklist ก่อนรัน

- [ ] Communication user สร้างแล้ว รู้ password
- [ ] SAP_COM_0002 arrangement เปิด inbound service Clearing แล้ว
- [ ] ยิงผ่าน SOAPUI/Postman สำเร็จ (ได้ HTTP 202)
- [ ] `YOS_CLEARING_SOAP` + `YCS_CLEARING` activate + publish แล้ว
- [ ] `YCS_CLEARING` arrangement สร้างแล้ว ชี้ host ตัวเอง
- [ ] Business user มีสิทธิ์ดู Fiori app **Message Dashboard**
- [ ] Posting period ของ company code เปิดอยู่
- [ ] มี open item จริงที่ยังไม่ถูก clear (ดู `docs/04-test-data.md`)
