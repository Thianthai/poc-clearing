# 02 — Communication Setup (C1–C4)

console class ยิง SOAP ไปที่ **inbound service ของ tenant ตัวเอง** จึงต้อง config
สองฝั่ง: **inbound** (ให้ service เปิดรับ) และ **outbound** (ให้ ABAP มี destination
+ credential ยิงออก) โดยใช้ communication system ตัวเดียวกันทำทั้งสองหน้าที่

```
C1 Communication User ──┐
                        ├──▶ C2 Communication System (ชี้ host ตัวเอง)
                        │         │                    │
                        │         │ inbound            │ outbound
                        │         ▼                    ▼
                        └──▶ C3 Arrangement       C4 Arrangement
                             SAP_COM_0002           ZCS_SPORTPACKAGE_CLEARING
                             (เปิดรับ clearing)     (ให้ ABAP ยิงออก)
                                  ▲                    │
                                  └────────────────────┘
                                     ยิงกลับเข้าตัวเอง

ADT: ZAPI_SPORTPACKAGE_CLEARING_REST (outbound service) + ZCS_SPORTPACKAGE_CLEARING (comm scenario)
     ต้องสร้าง + publish ก่อนถึงจะเห็น scenario ตอนทำ C4
```

**ลำดับที่ต้องทำ**: C1 → C2 → C3 → (ADT objects) → C4

---

## C1 — Communication User

Fiori app **Maintain Communication Users**

| ช่อง | ค่า |
|---|---|
| User Name | `ABAP_DEV` (ใช้ตัวที่มีอยู่แล้วบน tenant) |
| Description | `Sport Package Journal Entry Clearing` (ค่าจริงบน tenant) |
| Password | กด *Propose Password* แล้ว **copy เก็บไว้** |

> password แสดงครั้งเดียว ถ้าหายต้อง reset ใหม่
> user นี้ใช้ทั้งขา inbound และ outbound เพราะยิงกลับเข้า tenant ตัวเอง

---

## C2 — Communication System

Fiori app **Communication Systems** → New

| ช่อง | ค่า |
|---|---|
| System ID | `ABAP_DEV` (ใช้ตัวที่มีอยู่แล้ว) |
| System Name | POC Self Call |
| **Host Name** | `my423102-api.s4hana.cloud.sap` ← host **-api** ของ tenant ตัวเอง |
| Port | `443` |

จากนั้นเพิ่ม user ทั้งสองฝั่ง

- **Users for Inbound Communication** → เพิ่ม `ABAP_DEV`
  · Authentication Method: *User Name and Password*
- **Users for Outbound Communication** → เพิ่ม `ABAP_DEV` + password จาก C1
  · Authentication Method: *User Name and Password*

Save → ตรวจว่าสถานะเป็น active

> **host ต้องเป็นตัว `-api`** ไม่ใช่ host ที่ใช้เปิด Fiori launchpad
> (launchpad = `my423102.s4hana.cloud.sap` · API = `my423102-api.s4hana.cloud.sap`)

---

## C3 — Communication Arrangement `SAP_COM_0002` (inbound)

Fiori app **Communication Arrangements** → New

| ช่อง | ค่า |
|---|---|
| Scenario | `SAP_COM_0002` — Finance: Posting Integration |
| Arrangement Name | ปล่อยตามที่ระบบเสนอ |
| Communication System | `ABAP_DEV` |
| Inbound Communication → User Name | `ABAP_DEV` |

ในส่วน **Inbound Services** ต้องเห็น **Journal Entry – Clearing (Asynchronous)**
และติ๊ก active

**Service URL ที่ระบบแสดง** (ยืนยันแล้วจาก tenant 2026-09-09)

```
https://my423102-api.s4hana.cloud.sap/sap/bc/srt/scs_ext/sap/journalentrybulkclearingreques
```

Save — **ต้องกด Save ให้พ้นสถานะ Draft** ไม่งั้น service ยังไม่เปิดรับ

### ⚠️ Outbound Services ของ `SAP_COM_0002` — ปิดไว้ก่อน

ในหน้าเดียวกันจะมี outbound service 3 ตัว
*Journal Entry – Change / Create / **Clear** (Asynchronous) Confirmation*
พวกนี้คือช่องทางที่ SAP ส่ง **ผลลัพธ์กลับ** ไปยังระบบต้นทาง

POC นี้ไม่มีตัวรับ ถ้าปล่อย Active ไว้ทั้งที่ Path ว่าง จะมี outbound message
fail ค้างในคิวทุกครั้งที่ยิง → **uncheck Active ทั้ง 3 ตัว**

ไม่กระทบการ clear เพราะ inbound กับ outbound แยกทางกัน
ถ้าอยากลองรับ confirmation จริง ๆ ค่อยเปิดทีหลังตอน POC หลักผ่านแล้ว

> ส่วน Outbound ของ `SAP_COM_0002` **ไม่ใช่** ตัวที่ console class ใช้
> ตัวที่ใช้คือ arrangement `ZCS_SPORTPACKAGE_CLEARING` ใน C4 คนละอันกัน

### ทดสอบก่อนไปต่อ (แนะนำมาก)

ยิงด้วย SOAPUI / Postman โดยใช้ payload ก้อนที่ dry-run พิมพ์ออกมา

- Method `POST` · URL = Service URL ข้างบน
- Auth: Basic — `ABAP_DEV` + password
- Header `Content-Type: text/xml; charset=utf-8`
- Header `SOAPAction:` ค่าเดียวกับ `gc_soap_action`
- SOAPUI ต้องติ๊ก **WS-A addressing** + **Generate MessageID**
  (Postman ไม่มีให้ติ๊ก แต่ payload ของเรามี `wsa:` header ฝังมาแล้ว)

ได้ **HTTP 202** = inbound พร้อม → ผ่านด่านนี้แล้วปัญหาที่เหลือจะอยู่ฝั่ง
outbound destination อย่างเดียว แยกปัญหาได้ชัด

---

## ADT objects (ทำก่อน C4)

### Outbound Service

ADT → package `YPOC_CLEARING` → New → Other ABAP Repository Object →
Cloud Communication Management → **Outbound Service**

| ช่อง | ค่า |
|---|---|
| Name | พิมพ์ `ZAPI_SPORTPACKAGE_CLEARING` → ADT เติม `_REST` ให้เอง กลายเป็น **`ZAPI_SPORTPACKAGE_CLEARING_REST`** (31 ตัวอักษร) |
| Description | `Journal Entry Clearing` (ค่าจริงบน tenant) |
| Service Type | **HTTP** |
| Default Path Prefix | `/sap/bc/srt/scs_ext/sap/journalentrybulkclearingreques` |

> editor ของ Outbound Service มีแค่ **Service Type** กับ **Default Path Prefix**
> เท่านั้น · ส่วน HTTP Version / Port / Supports Ping ตั้งที่ **Communication
> Scenario → tab Outbound** (ดูหัวข้อถัดไป)

> **ตัด `?sap-client=100` ออก** เอาเฉพาะ path — query string ใส่ตรงนี้ไม่ได้

> **ADT เติม suffix `_REST` ให้อัตโนมัติ** ตอนสร้าง outbound service แบบ HTTP
> ชื่อที่พิมพ์ `ZAPI_SPORTPACKAGE_CLEARING` จะกลายเป็น `ZAPI_SPORTPACKAGE_CLEARING_REST`
> → `gc_service_id` ใน class ต้องใช้ชื่อที่มี `_REST` ต่อท้าย
>
> ชื่อเต็มยาว **31 ตัวอักษร** ถ้า ADT ไม่ยอมเพราะเกินลิมิต 30 ต้องย่อชื่อที่พิมพ์
> ให้สั้นลง 1 ตัว (เช่น `ZAPI_SPORTPKG_CLEARING`) แล้วแก้ constant ตาม

### Communication Scenario

ADT → New → **Communication Scenario**

| ช่อง | ค่า |
|---|---|
| Name | `ZCS_SPORTPACKAGE_CLEARING` |
| Communication Scenario Type | `Customer` |
| Description | `Sport Package Journal Entry Clearing` (ค่าจริงบน tenant) |
| Allowed Instances | *One instance per scenario & communication system* |

- Scope Dependent → **ไม่ต้องติ๊ก**
- แท็บ **Outbound** → Add → `ZAPI_SPORTPACKAGE_CLEARING_REST`
- Supported Authentication Methods → ติ๊ก **User Name and Password**
- ในกล่อง **Outbound Service** ด้านล่าง → **REST Service Settings** →
  ตั้ง **HTTP Version = 1.1** (ADT default ให้มา 1.0 ซึ่งไม่รองรับ
  persistent connection / chunked transfer)
- Save → **Activate** → **Publish Locally**

> ค่าพวกนี้ serialize ลง `.sco1.xml` ของ comm scenario ไม่ใช่ `.sco3.xml`
> ของ outbound service · `<HTTP_VERSION>1</HTTP_VERSION>` = **HTTP 1.1**

> ถ้าไม่ publish จะไม่เห็น scenario นี้ตอนสร้าง arrangement ใน C4

---

## C4 — Communication Arrangement `ZCS_SPORTPACKAGE_CLEARING` (outbound)

Fiori app **Communication Arrangements** → New

| ช่อง | ค่า |
|---|---|
| Arrangement Name | `SPORTPACKAGE_CLEARING_API` |
| Scenario | `ZCS_SPORTPACKAGE_CLEARING` |
| Communication System | `ABAP_DEV` |
| Outbound Communication → User Name | `ABAP_DEV` |
| Outbound Communication → Password | password จาก C1 |

ในส่วน **Outbound Services** → `ZAPI_SPORTPACKAGE_CLEARING_REST`

- ติ๊ก active
- Path ต้องเป็น `/sap/bc/srt/scs_ext/sap/journalentrybulkclearingreques`

Save — จากนั้นกด **Check Connection** ที่ outbound service
ได้ *"The ping of the outbound service was successful"* = host + credential + path ถูกหมด

> **Authentication Method** ในหน้านี้เป็น derived field — ระบบเอาค่าจาก
> communication system / communication user มาให้เอง ไม่ต้องเลือกเอง
> ที่เห็นเป็นตัวเทาคือปกติ

---

## ตรวจว่า ABAP หา destination เจอ

console class เรียก

```abap
cl_http_destination_provider=>create_by_comm_arrangement(
  comm_scenario = 'ZCS_SPORTPACKAGE_CLEARING'
  service_id    = 'ZAPI_SPORTPACKAGE_CLEARING_REST' )
```

ถ้า throw `CX_HTTP_DEST_PROVIDER_ERROR` = C4 ยังไม่ถูกสร้าง หรือชื่อ
scenario / service ไม่ตรง

---

## Checklist

- [ ] C1 comm user สร้างแล้ว จด password ไว้
- [ ] C2 comm system ชี้ host `-api` ของตัวเอง มี user ทั้ง inbound + outbound
- [ ] C3 `SAP_COM_0002` เปิด inbound service Clearing แล้ว และ **Save พ้น Draft**
- [ ] Outbound confirmation service 3 ตัวใน `SAP_COM_0002` uncheck Active แล้ว
- [ ] ยิงผ่าน SOAPUI/Postman ได้ HTTP 202
- [ ] `ZAPI_SPORTPACKAGE_CLEARING_REST` + `ZCS_SPORTPACKAGE_CLEARING` activate + publish locally แล้ว
- [ ] C4 arrangement สร้างแล้ว outbound service active
- [ ] Business user มีสิทธิ์เปิด Fiori app **Message Dashboard**
- [ ] Posting period ของ company code `1000` เปิดอยู่สำหรับวันที่ที่จะ post

## ทางเลือกที่ **ไม่ใช้** ใน repo นี้

`cl_http_destination_provider=>create_by_url( )` + `set_authorization_basic( )`
เซ็ตเร็วกว่ามาก ข้าม C2/C4 ได้เลย แต่ต้องเอา user/password ใส่ไว้ใน source code
→ ห้ามใช้

## Troubleshooting

| อาการ | สาเหตุ |
|---|---|
| ไม่เห็น `ZCS_SPORTPACKAGE_CLEARING` ตอนสร้าง arrangement | ยังไม่ได้ *Publish Locally* ที่ comm scenario |
| ไม่เห็น *Journal Entry – Clearing* ใน `SAP_COM_0002` | scope item ยังไม่ activate — คุยกับ functional |
| HTTP 401 | password ใน outbound ของ C2/C4 ไม่ตรงกับ C1 |
| HTTP 404 | path มี `?sap-client=` ติดมา หรือสะกด service ผิด |
| `CX_HTTP_DEST_PROVIDER_ERROR` | C4 ยังไม่มี หรือชื่อไม่ตรงกับ constant ใน class |
