# 03 — Object List

สถานะ ณ วันที่อัปเดตล่าสุด · Claude อัปเดตตารางนี้ตามที่เห็นใน `git log`
หลังผู้ใช้ push object ผ่าน abapGit

| # | Object | Type | ใครสร้าง | Status |
|---|---|---|---|---|
| 1 | `YPOC_CLEARING` | Package | ผู้ใช้ (ADT) | ✅ [`src/package.devc.xml`](../src/package.devc.xml) |
| 2 | `ZAPI_SPORTPACKAGE_CLEARING_REST` | Outbound Service (HTTP) | ผู้ใช้ (ADT) | ✅ [`src/zapi_sportpackage_clearing_rest.sco3.xml`](../src/zapi_sportpackage_clearing_rest.sco3.xml) |
| 3 | `ZCS_SPORTPACKAGE_CLEARING` | Communication Scenario | ผู้ใช้ (ADT) | ✅ [`src/zcs_sportpackage_clearing.sco1.xml`](../src/zcs_sportpackage_clearing.sco1.xml) |
| 4 | `YCL_CLEARING` | Class (console, `IF_OO_ADT_CLASSRUN`) | ผู้ใช้ (ADT) | ✅ [`src/ycl_clearing.clas.abap`](../src/ycl_clearing.clas.abap) |

Legend: ⬜ ยังไม่สร้าง · 🟡 สร้างแล้วยังไม่ push · ✅ push ขึ้น repo แล้ว

**push ครบทุก object แล้ว** (2026-09-10) — abapGit serialize ด้วย
`FOLDER_LOGIC = FULL`, `STARTING_FOLDER = /src/`

## Config ที่ไม่ใช่ repository object

| # | สิ่งที่ต้องทำ | ที่ | Status |
|---|---|---|---|
| C1 | Communication User `ABAP_DEV` | Fiori: Maintain Communication Users | ✅ ใช้ตัวที่มีอยู่แล้ว |
| C2 | Communication System `ABAP_DEV` (host `my423102-api...`) | Fiori: Communication Systems | ✅ inbound + outbound user พร้อม |
| C3 | Comm Arrangement `SAP_COM_0002` (inbound) | Fiori: Communication Arrangements | ✅ Save พ้น Draft + ปิด confirmation outbound แล้ว |
| C4 | Comm Arrangement `SPORTPACKAGE_CLEARING_API` (outbound) | Fiori: Communication Arrangements | ✅ Save + Check Connection ผ่าน |

รายละเอียดขั้นตอนอยู่ที่ [02-communication-setup.md](02-communication-setup.md)

## ลำดับการทำ

```
1. C1 → C2 → C3          เปิด inbound service ให้ได้ก่อน
2. ทดสอบด้วย SOAPUI      ต้องได้ HTTP 202 ก่อนค่อยเขียน ABAP
3. Object 1 → 2 → 3      สร้าง destination ฝั่ง outbound
4. C4                    ผูก arrangement
5. Object 4              copy console class จาก chat → รัน F9
```

ถ้าข้อ 2 ยังไม่ผ่าน อย่าเพิ่งไปข้อ 3 — จะแยกไม่ออกว่า error มาจาก
payload หรือมาจาก destination

## Log การทดสอบ

| วันที่ | ทำอะไร | ผล |
|---|---|---|
| 2026-09-09 | activate `YCL_CLEARING` แล้วรัน dry-run โดยยังไม่มี item | ✅ UUID + guard + dry-run ทำงานถูก ไม่ยิงออกไป |
| 2026-09-09 | dry-run ด้วย GLItems 2 บรรทัด (ค่า placeholder) | ✅ payload ตรงกับตัวอย่าง SAP ทุก element — **payload builder ปิดจ๊อบ** |
| 2026-09-09 | ได้ test data จริงจาก functional (AR: invoice 9400000005 + payment 3300000017) | ✅ ตรวจแล้วยอดหักล้างกันพอดี ยังไม่ถูก clear เติมลง `get_apar_items( )` แล้ว |
| 2026-09-09 | dry-run ด้วย data จริง | ✅ payload ครบถูกต้อง — `APARItems` 2 ก้อน, `AccountType D`, FY2026, item 001/005 · **ฝั่ง ABAP พร้อมยิง** |
| 2026-09-09 | config C1–C4 ครบ + **Check Connection ผ่าน** | ✅ host + credential + path ถูกต้อง — พร้อมยิงจริง |
| 2026-09-09 | ยิงจริงครั้งที่ 1 (**client 80**) | ❌ `CX_HTTP_DEST_PROVIDER_ERROR` |
| 2026-09-09 | ยิงจริงครั้งที่ 2 (**client 100** + `comm_system_id`) | ✅ **HTTP 202 Accepted** |
| 2026-09-09 | ยิงครั้งที่ 3 (**client 100** ไม่ส่ง `comm_system_id`) | ✅ 202 → พิสูจน์ว่าสาเหตุคือ **client** ไม่ใช่ `comm_system_id` |
| 2026-09-09 | Message Dashboard ว่างเปล่าทั้งเดือน | ⚠️ user ไม่ถูก assign AIF recipient — ไม่ใช่ว่า message ไม่เข้า |
| 2026-09-09 10:00 UTC | **ยิง post จริง** (`TestDataIndicator = false`) | ✅ clear สำเร็จ เอกสาร `0100000000` — แต่**ยังไม่ครบ** |
| 2026-09-09 | functional ตรวจ clearing doc | ⚠️ ขาดบรรทัด **Deferred Output Tax** (G/L `0021082005`) ต้อง clear คู่ไปด้วย |
| 2026-09-09 | เพิ่ม `get_gl_items( )` = G/L `0021082005` ทั้ง 2 ใบ + reverse `0100000000` | ✅ |
| 2026-09-09 10:46 UTC | **ยิง post จริงครบ 4 บรรทัด** | ✅ clearing document `0100000002` · พิสูจน์ว่าใส่ `GLItems` + `APARItems` ปนกันใน `JournalEntry` เดียวได้ |
| 2026-09-09 | functional ตรวจ `0100000002` | ⚠️ มีบรรทัด zero-balance clearing `0012990002` ±5,999.00 ที่ standard app ไม่มี — เกิดจาก document splitting เพราะ profit center สองฝั่งไม่ตรงกัน |
| 2026-09-10 | เปลี่ยน document type `AB` → `DA` แล้วยิงใหม่ | ⚠️ ได้เอกสาร `3000000003` แต่ `0012990002` ยังอยู่ — **document type ไม่ใช่ต้นเหตุ** |
| 2026-09-10 | สรุปต้นเหตุ | profit center ของ invoice (`DUMMY`) กับ payment (`0000010002`) ไม่ตรงกัน → document splitting เติม zero-balance |
| 2026-09-10 | **functional ยืนยันกลับ** | ✅ **บรรทัด zero-balance ถูกต้องแล้ว** — เข้าใจผิดตอนแรก · ใช้ doc type `DA` · **ปิดเคส POC สำเร็จ** |
| 2026-09-10 | push ABAP object ขึ้น repo ผ่าน abapGit | ✅ ครบทุก object |
| 2026-09-10 | เทียบ `src/` กับเอกสาร แล้วตกลงชุดแก้ไข | ✅ อัปเดตบน tenant + push แล้ว — `gc_test_run` กลับเป็น `'true'`, คืน hint ใน CATCH, คืน comment ที่หายไป, คง `ty_apar_item` แบบ reference · **`src/` = docs/05 ตรงกันทุกบรรทัด** |

### ยังพิสูจน์ไม่ได้ (รออะไรอยู่)

| หัวข้อ | รอ |
|---|---|
| ~~destination + auth~~ | ✅ ping ผ่านแล้ว |
| ~~endpoint / SOAPAction~~ | ✅ HTTP 202 |
| ~~business logic ของ clearing~~ | ✅ clear สำเร็จจริง |

## งานที่ยังค้าง (2026-09-10)

| # | เรื่อง | สถานะ |
|---|---|---|
| 1 | ~~ยืนยัน `HTTP Version`~~ | ✅ **ปิด** — ตั้งเป็น 1.1 ตั้งแต่ตอนสร้างแล้ว (`<HTTP_VERSION>1</HTTP_VERSION>` = 1.1) |
| 2 | AIF recipient assignment (ให้ Message Dashboard มองเห็น message) | ⏸️ พักไว้ก่อน — ต้องทำถ้าจะเอาไป production |
| 3 | ~~ทดสอบ partial / residual clearing~~ | ❌ **ปิด** — ไม่อยู่ใน scope ของ POC นี้ |

**POC ปิดครบทุกข้อแล้ว** เหลือเฉพาะข้อ 2 ซึ่งเป็นเรื่องของการเอาไปใช้งานจริง
ไม่ใช่เงื่อนไขของ POC
