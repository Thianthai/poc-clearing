# 03 — Object List

สถานะ ณ วันที่อัปเดตล่าสุด · Claude อัปเดตตารางนี้ตามที่เห็นใน `git log`
หลังผู้ใช้ push object ผ่าน abapGit

| # | Object | Type | ใครสร้าง | Status |
|---|---|---|---|---|
| 1 | `YPOC_CLEARING` | Package | ผู้ใช้ (ADT) | ⬜ ยังไม่สร้าง |
| 2 | `ZOS_CLEARING_SOAP` | Outbound Service (HTTP) | ผู้ใช้ (ADT) | 🔜 ทำต่อจากนี้ |
| 3 | `ZCS_CLEARING` | Communication Scenario | ผู้ใช้ (ADT) | 🔜 ทำต่อจากนี้ |
| 4 | `YCL_CLEARING_RUNNER` | Class (console, `IF_OO_ADT_CLASSRUN`) | ผู้ใช้ copy จาก chat | 🟡 activate + รัน dry-run ผ่านแล้ว ยังไม่ push |

Legend: ⬜ ยังไม่สร้าง · 🟡 สร้างแล้วยังไม่ push · ✅ push ขึ้น repo แล้ว

## Config ที่ไม่ใช่ repository object

| # | สิ่งที่ต้องทำ | ที่ | Status |
|---|---|---|---|
| C1 | Communication User `ABAP_DEV` | Fiori: Maintain Communication Users | ✅ ใช้ตัวที่มีอยู่แล้ว |
| C2 | Communication System `ABAP_DEV` (host `my423102-api...`) | Fiori: Communication Systems | ✅ inbound + outbound user พร้อม |
| C3 | Comm Arrangement `SAP_COM_0002` (inbound) | Fiori: Communication Arrangements | ✅ Save พ้น Draft + ปิด confirmation outbound แล้ว |
| C4 | Comm Arrangement `ZCS_CLEARING` (outbound) | Fiori: Communication Arrangements | ⬜ |

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
| 2026-09-09 | activate `YCL_CLEARING_RUNNER` แล้วรัน dry-run โดยยังไม่มี item | ✅ UUID + guard + dry-run ทำงานถูก ไม่ยิงออกไป |
| 2026-09-09 | dry-run ด้วย GLItems 2 บรรทัด (ค่า placeholder) | ✅ payload ตรงกับตัวอย่าง SAP ทุก element — **payload builder ปิดจ๊อบ** |
| 2026-09-09 | ได้ test data จริงจาก functional (AR: invoice 9400000005 + payment 3300000017) | ✅ ตรวจแล้วยอดหักล้างกันพอดี ยังไม่ถูก clear เติมลง `get_apar_items( )` แล้ว |
| 2026-09-09 | dry-run ด้วย data จริง | ✅ payload ครบถูกต้อง — `APARItems` 2 ก้อน, `AccountType D`, FY2026, item 001/005 · **ฝั่ง ABAP พร้อมยิง** |

### ยังพิสูจน์ไม่ได้ (รออะไรอยู่)

| หัวข้อ | รอ |
|---|---|
| destination + auth | config C1–C4 |
| endpoint / SOAPAction ถูกไหม | ยิงจริงครั้งแรก |
| business logic ของ clearing | ยิงจริงครั้งแรก (test data พร้อมแล้ว) |
