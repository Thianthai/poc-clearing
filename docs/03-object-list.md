# 03 — Object List

สถานะ ณ วันที่อัปเดตล่าสุด · Claude อัปเดตตารางนี้ตามที่เห็นใน `git log`
หลังผู้ใช้ push object ผ่าน abapGit

| # | Object | Type | ใครสร้าง | Status |
|---|---|---|---|---|
| 1 | `YPOC_CLEARING` | Package | ผู้ใช้ (ADT) | ⬜ ยังไม่สร้าง |
| 2 | `YOS_CLEARING_SOAP` | Outbound Service (HTTP) | ผู้ใช้ (ADT) | ⬜ ยังไม่สร้าง |
| 3 | `YCS_CLEARING` | Communication Scenario | ผู้ใช้ (ADT) | ⬜ ยังไม่สร้าง |
| 4 | `YCL_CLEARING_RUNNER` | Class (console, `IF_OO_ADT_CLASSRUN`) | ผู้ใช้ copy จาก chat | ⬜ ยังไม่สร้าง |

Legend: ⬜ ยังไม่สร้าง · 🟡 สร้างแล้วยังไม่ push · ✅ push ขึ้น repo แล้ว

## Config ที่ไม่ใช่ repository object

| # | สิ่งที่ต้องทำ | ที่ | Status |
|---|---|---|---|
| C1 | Communication User | Fiori: Maintain Communication Users | ⬜ |
| C2 | Communication System (ชี้ tenant ตัวเอง) | Fiori: Communication Systems | ⬜ |
| C3 | Comm Arrangement `SAP_COM_0002` (inbound) | Fiori: Communication Arrangements | ⬜ |
| C4 | Comm Arrangement `YCS_CLEARING` (outbound) | Fiori: Communication Arrangements | ⬜ |

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
