# Reboot Handling

Toàn bộ mục đích của VDLU là cập nhật một module mà không flash lại nó, và, bất cứ khi nào có thể, không cần khởi động lại chút nào. Phần lớn tệp trong một module có thể được thay thế khi thiết bị đang chạy. Một số ít thực sự không thể, vì kernel hoặc tiến trình zygote đã ánh xạ chúng và sẽ không nhận ra một thay đổi cho tới lần khởi động tiếp theo.

Nhiệm vụ của VDLU là phân biệt tự động hai nhóm đó, áp dụng mọi thứ nó có thể một cách an toàn **live**, và chỉ hoãn những tệp thực sự bị ràng buộc với lần boot sang một lần khởi động lại mà nó gắn cờ rõ ràng. Trang này giải thích cách làm.

Về cơ chế engine bên dưới điều này, xem [[Engine]]. Về bức tranh lớn, xem [[Architecture]].

## Tại sao không chỉ khởi động lại mỗi lần

Một lần khởi động lại là điều đắt giá nhất mà một bản cập nhật có thể yêu cầu ở ai đó. Nó làm gián đoạn bất cứ thứ gì họ đang làm, nó tốn một phút hoặc hơn, và nó huấn luyện người ta sợ các bản cập nhật. Một bộ cập nhật tăng dần tốt nên cảm thấy vô hình: bạn chạm cập nhật, vài tệp thay đổi dưới hệ thống đang chạy, và bạn đã ở phiên bản mới.

Nên VDLU đảo ngược giả định thông thường. Mặc định là live. Một tệp chỉ bị hoãn sang một lần khởi động lại khi nó chứng minh được là một trong các loại bị ràng buộc với kernel hoặc zygote, và ngay cả khi đó cũng chỉ tệp đó phải chờ. Mọi thứ xung quanh nó vẫn cập nhật ngay lập tức.

## Ba lớp

Mọi tệp trong feed được gán một lớp. Producer có thể đặt nó tường minh trong manifest, nhưng trên thực tế lớp được suy ra từ đường dẫn, và engine sẽ chỉ bao giờ nâng cấp một tệp theo hướng `reboot`, không bao giờ hạ cấp nó theo hướng `live`. Các lớp là:

**LIVE** là trường hợp phổ biến: các tài nguyên web UI, các nhị phân, các script được đọc theo yêu cầu, các tệp cấu hình, `module.prop`, và bất cứ thứ gì khác không khớp với các quy tắc bên dưới. Một tệp live được sao lưu rồi rename một cách nguyên tử đè lên đích trong khi hệ thống chạy. Không khởi động lại, và thay đổi có hiệu lực ngay khoảnh khắc lần rename đáp xuống.

**SOFT** là các script vòng đời của chính module: `service.sh`, `post-fs-data.sh`, và `boot-completed.sh`. Những tệp này được áp dụng live chính xác như các tệp LIVE, nên bản sao mới đã có sẵn trên đĩa. Lý do chúng có lớp riêng là hệ thống đang chạy đã thực thi bản sao cũ ở lần boot này rồi; bản mới đơn giản chạy ở lần boot tới, không staging và không biểu ngữ. Không có gì để hoãn, chỉ là một lần bàn giao tự nhiên.

**REBOOT-hard** là tập hợp nhỏ không thể thay đổi dưới một hệ thống đang chạy:

- các thư viện native, `*.so` (bất cứ thứ gì dưới một đường dẫn `zygisk/`), vì zygote ánh xạ chúng vào mọi app lúc khởi động;
- các tệp overlay `/system`, vì overlay được mount lúc boot;
- các tệp `sepolicy.rule`, vì chính sách SELinux được nạp sớm.

Một tệp REBOOT-hard không bao giờ được ghi đè lên inode đang sống của nó trong khi hệ thống đang chạy. Ghi đè một `.so` mà zygote đã ánh xạ chính là cách bạn gặp crash và trạng thái không nhất quán. Thay vào đó nội dung mới được **staged** bên cạnh thư mục trạng thái và được hoán đổi vào ở lần boot tiếp theo, trước khi bất cứ thứ gì có thể ánh xạ nó.

## Đường dẫn tới lớp, trong một cái nhìn tổng quan

Engine suy ra lớp từ đường dẫn như thế này:

| Mẫu đường dẫn | Lớp | Áp dụng |
|---|---|---|
| `zygisk/**`, `**/zygisk/**` (các tệp `.so`) | REBOOT-hard | staged, hoán đổi pre-zygote lúc boot |
| `system/**` (overlay) | REBOOT-hard | staged, hoán đổi lúc boot |
| `*.rule` (sepolicy) | REBOOT-hard | staged, hoán đổi lúc boot |
| `service.sh`, `post-fs-data.sh`, `boot-completed.sh` | SOFT | ghi live, chạy ở lần boot tới |
| `webroot/**`, `bin/**`, `lib/**`, các config, `module.prop`, mọi thứ khác | LIVE | ghi live, hiệu lực ngay lập tức |

Manifest có thể mang theo một `class` tường minh cho từng tệp, nhưng lớp được suy ra đóng vai trò một mức sàn: nếu một tệp trông REBOOT-hard theo đường dẫn của nó, nó được coi là REBOOT-hard ngay cả khi manifest nói khác. Điều này giữ cho một feed gắn nhãn sai không bao giờ thử hot-swap một `.so`.

## Cách một lần run xử lý cả hai nhóm cùng lúc

Trong một `run` thông thường (chu trình DIFF tới FETCH tới APPLY tới COMMIT được mô tả trong [[Engine]]), hai nhóm được xử lý trong cùng một giao dịch:

```
run:
  LIVE + SOFT  --> backup -> write .vdlu-tmp -> verify -> atomic rename   (effective now)
  REBOOT-hard  --> materialize into staged/<path>.vdlu-new                (live inode untouched)

  re-hash every LIVE + SOFT file
       |
       +-- nothing staged  --> DONE
       +-- something staged --> PENDING_REBOOT  (reboot banner in the WebUI)
```

Nên sau một lần run chạm vào một `.so`, bạn đã ở phiên bản mới cho mọi tệp live, và chỉ các mảnh đã staged đang chờ. Nhật ký báo cáo `reboot_pending`, và WebUI hiển thị một biểu ngữ dai dẳng mời một lần khởi động lại để kích hoạt các tệp đã staged. Không có "done" giả: một lần run có các tệp staged kết thúc ở `PENDING_REBOOT`, không phải `DONE`.

## Lần hoán đổi lúc boot

Các tệp đã staged được áp dụng bởi lệnh `boot`, lệnh mà module chủ nối vào `post-fs-data.sh` để nó chạy đồng bộ và **pre-zygote**, trước khi bất kỳ tiến trình nào có thể ánh xạ `.so` mới.

`boot` thực hiện một `resume` (để hoàn thành bất kỳ pha nào bị gián đoạn) rồi lần hoán đổi. Với mỗi tệp REBOOT-hard đã staged, nó:

1. xác nhận đường dẫn đã staged ở lại bên trong thư mục module (một lần kiểm tra chứa đựng);
2. băm lại `staged/<path>.vdlu-new` so với hash của manifest;
3. sao lưu tệp live hiện tại;
4. `mv -f` tệp đã staged đè lên tệp live và `chmod` nó;
5. băm lại tệp giờ đang ở đúng chỗ, để xác nhận lần hoán đổi đáp xuống đúng;
6. đánh dấu nó đã áp dụng.

Chỉ khi mọi tệp đã staged đã hoán đổi và đã xác minh lại thì giao dịch mới đóng từ `PENDING_REBOOT` thành `DONE`. Nếu bất kỳ bước nào thất bại, nhật ký ghi lại lỗi và module giữ các tệp trước đó của nó; không có gì bị bỏ lại hoán đổi dở dang.

Vì lần hoán đổi là một chuỗi các lần băm lại và các lần rename nguyên tử, chạy `boot` an toàn ngay cả khi nó bị gián đoạn lần trước. Nó đơn giản nhặt lại các tệp đã staged.

## auto_on_reboot

Staging chỉ là một nửa của cảm giác không-cần-khởi-động-lại; nửa còn lại là người dùng không bao giờ phải nhớ chạy lần hoán đổi. Với `auto_on_reboot=1` trong cấu hình, `post-fs-data.sh` của module chủ gọi `update.sh boot` ở mỗi lần boot. Điều đó nghĩa là:

- nếu một giao dịch đang chờ khởi động lại, các tệp đã staged được hoán đổi vào tự động trước khi zygote khởi động, và người dùng chỉ thấy mình đã hoàn toàn ở phiên bản mới;
- nếu không có gì đang chờ, `boot` có thể chạy một chu trình mới và áp dụng mọi thứ, bao gồm cả một `.so`, trong lần boot duy nhất đó, vì nó đã chạy pre-zygote rồi.

Nói cách khác, một `.so` đã staged không tốn của người dùng gì ngoài một lần khởi động lại mà dù sao họ cũng sẽ làm. Họ không phải chạm vào bất cứ thứ gì lần thứ hai.

## Offline lúc boot, mà không làm cạn pin

Đôi khi `boot` muốn kiểm tra feed nhưng thiết bị chưa có mạng. VDLU có thể chờ nó, một cách kiên nhẫn và rẻ, được điều khiển bởi `boot_retry_minutes` (0 tắt nó đi). Việc chờ được cố ý làm an toàn pin:

- giữa các lần thử nó đơn giản `sleep`, điều này đóng băng trong giấc ngủ sâu (deep sleep), nên thiết bị ngủ bình thường và lần thử lại chỉ tiếp tục một khi thiết bị đã thức;
- nó không giữ wakelock nào và không giữ khóa engine trong khi chờ, nên một lần run thủ công không bao giờ bị chặn;
- trước mỗi lần thử nó kiểm tra xem mạng có được phép không bằng một lần tra cứu tuyến (route) của kernel mà không gửi gói tin nào và không đánh thức sóng;
- nó không bao giờ thử lại một thất bại tất định như một chữ ký sai hoặc một lần hạ cấp bị chặn, chỉ một điều kiện mạng-vắng-mặt thực sự.

Bản thân lần check manifest vẫn miễn phí trên bất kỳ mạng nào, nên bạn luôn biết có một bản cập nhật tồn tại; chỉ lần tải mới chờ chính sách mạng được thỏa mãn, hoãn lại gọn gàng thay vì báo lỗi.

## Xem thêm

- [[Engine]]: giao dịch, logic apply-theo-lớp, và lệnh `boot` đầy đủ.
- [[Architecture]]: nơi engine nằm giữa producer và WebUI.
