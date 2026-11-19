> **Languages:** [English](../../CONTRIBUTING.md) · [العربية](../ar/CONTRIBUTING.md) · [Čeština](../cs/CONTRIBUTING.md) · [Deutsch](../de/CONTRIBUTING.md) · [Español](../es/CONTRIBUTING.md) · [فارسی](../fa/CONTRIBUTING.md) · [Français](../fr/CONTRIBUTING.md) · [हिन्दी](../hi/CONTRIBUTING.md) · [Bahasa Indonesia](../id/CONTRIBUTING.md) · [Italiano](../it/CONTRIBUTING.md) · [日本語](../ja/CONTRIBUTING.md) · [한국어](../ko/CONTRIBUTING.md) · [Nederlands](../nl/CONTRIBUTING.md) · [Polski](../pl/CONTRIBUTING.md) · [Português](../pt/CONTRIBUTING.md) · [Русский](../ru/CONTRIBUTING.md) · [Svenska](../sv/CONTRIBUTING.md) · [ไทย](../th/CONTRIBUTING.md) · [Türkçe](../tr/CONTRIBUTING.md) · [Українська](../uk/CONTRIBUTING.md) · Tiếng Việt · [中文](../zh/CONTRIBUTING.md)

---

# Đóng góp cho VDLiveUpdate

VDLU là một engine tự-cập-nhật tăng tiến, flashless được vendor vào các module KernelSU/APatch/Magisk.
Hoan nghênh các đóng góp.

- Đọc [INTERFACES.md](INTERFACES.md) trước: nó là hợp đồng đường ghép giữa các thành phần (luật
  hội tụ). Coi nó như bất biến trừ khi một thay đổi được phối hợp qua engine, producer và WebUI.
- Kiểm thử đầu-cuối trước một PR: `producer/vdlu-keygen`, `vdlu-pack`, `vdlu-sign`, rồi engine
  (`check` / `run` / `boot`). Cũng `sh -n engine/*.sh` và `node --check webui/vdlu.js`.
- Bảo mật là không thể thương lượng: mỗi trường manifest là đầu vào thù địch và `validate_plan()` luôn
  fail-closed; khóa ký riêng không bao giờ chạm vào CI hay một thiết bị.
- POSIX sh trên thiết bị (không bashism ngoài `local`, không `jq`); giữ chú thích ngắn gọn.
- Một thay đổi logic cho mỗi PR; nói cái gì đã đổi và tại sao.

## Liên hệ

- Telegram: @VD_Priv8 https://t.me/VD_Priv8
- Kênh: @Priv8_VD https://t.me/Priv8_VD
- E-mail: vd.priv8@pm.me

<!-- doc-footer -->

---

> _Tài liệu này được tạo bằng Claude (Anthropic) và được duy trì bởi VD171. Chúng tôi hoan nghênh các chỉnh sửa và cải tiến; xem [CONTRIBUTING.md](CONTRIBUTING.md)._
