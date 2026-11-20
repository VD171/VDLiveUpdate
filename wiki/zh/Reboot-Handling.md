# Reboot Handling

VDLU 的全部意义在于更新一个模块而不重新刷入它，并且在任何可能的地方，完全不重启。模块中的大多数文件可以在设备运行时被替换。少数确实不能，因为内核或 zygote 进程已经把它们映射（map）了，并且直到下一次启动前都不会注意到变化。

VDLU 的职责是自动区分这两组，把它安全能应用的一切都**实时**应用，并只把确实绑定于启动的文件推迟到一次它清楚标记出来的重启。本页解释如何做到。

关于这背后的引擎机制，参见 [[Engine]]。关于大局，参见 [[Architecture]]。

## 为什么不每次都重启

重启是一次更新能向人提出的最昂贵的要求。它打断人们正在做的事，它要花一分钟或更久，而且它训练人们惧怕更新。一个好的增量更新器应该感觉不到它的存在：你点一下更新，几个文件在运行中的系统之下发生变化，而你已经在新版本上了。

因此 VDLU 反转了惯常的假设。默认是实时。只有在一个文件被证明是内核绑定或 zygote 绑定的那几种之一时，它才会被推迟到一次重启，而即便如此，也只有那个文件在等待。它周围的一切仍然立即更新。

## 三个 class

feed 中的每个文件都被指派一个 class。producer 可以在清单中显式地设置它，但在实践中 class 是从路径推导出来的，而且引擎只会把一个文件向 `reboot` 方向升级，绝不会向 `live` 方向降级。这些 class 是：

**LIVE** 是常见情形：web UI 资源、二进制、按需读取的脚本、配置文件、`module.prop`，以及任何其他未被下面规则匹配的东西。一个 live 文件在系统运行时被备份、然后原子地 rename 覆盖目标。无需重启，而且变化在 rename 落地的那一刻即生效。

**SOFT** 是模块自己的生命周期脚本：`service.sh`、`post-fs-data.sh` 和 `boot-completed.sh`。这些文件完全像 LIVE 文件那样被实时应用，因此新副本已经在磁盘上。它们之所以有自己的 class，是因为运行中的系统在这次启动中已经执行了旧副本；新副本只会在下一次启动时运行，无需 staging 也无需横幅。没有什么要推迟，只是一次自然的交接。

**REBOOT-hard** 是那一小组无法在运行中的系统下更改的文件：

- 原生库，`*.so`（任何在一个 `zygisk/` 路径下的东西），因为 zygote 在启动时把它们映射进每个 app；
- `/system` overlay 文件，因为 overlay 在启动时被挂载；
- `sepolicy.rule` 文件，因为 SELinux 策略很早就被加载。

一个 REBOOT-hard 文件在系统处于运行时，绝不会被写在它在用的 inode 上。覆盖一个 zygote 已经映射的 `.so`，正是你招致崩溃和不一致状态的方式。取而代之，新内容被 **staged** 在状态目录旁边，并在下一次启动时、在任何东西能映射它之前被交换。

## 路径到 class，一览

引擎像这样从路径推导 class：

| 路径模式 | class | 应用方式 |
|---|---|---|
| `zygisk/**`、`**/zygisk/**`（`.so` 文件） | REBOOT-hard | staged，在启动时于 pre-zygote 交换 |
| `system/**`（overlay） | REBOOT-hard | staged，在启动时交换 |
| `*.rule`（sepolicy） | REBOOT-hard | staged，在启动时交换 |
| `service.sh`、`post-fs-data.sh`、`boot-completed.sh` | SOFT | 实时写入，在下一次启动时运行 |
| `webroot/**`、`bin/**`、`lib/**`、各种配置、`module.prop`、其他一切 | LIVE | 实时写入，立即生效 |

清单可以为每个文件携带一个显式的 `class`，但推导出的 class 充当一个下限：如果一个文件按其路径看起来是 REBOOT-hard，它就被当作 REBOOT-hard 处理，即使清单另有说法。这使得一个标注错误的 feed 永远不会去尝试热交换一个 `.so`。

## 一次运行如何同时处理两组

在一次正常的 `run`（在 [[Engine]] 中描述的 DIFF 到 FETCH 到 APPLY 到 COMMIT 周期）期间，两组在同一笔事务中被处理：

```
run:
  LIVE + SOFT  --> backup -> write .vdlu-tmp -> verify -> atomic rename   (effective now)
  REBOOT-hard  --> materialize into staged/<path>.vdlu-new                (live inode untouched)

  re-hash every LIVE + SOFT file
       |
       +-- nothing staged  --> DONE
       +-- something staged --> PENDING_REBOOT  (reboot banner in the WebUI)
```

因此在一次触碰了某个 `.so` 的运行之后，你对于每个 live 文件都已经在新版本上，只有那些 staged 的部分在等待。日志报告 `reboot_pending`，而 WebUI 显示一个持久横幅，邀请一次重启以激活那些 staged 文件。没有虚假的 "done"：一次带 staged 文件的运行以 `PENDING_REBOOT` 结束，而不是 `DONE`。

## 启动时的交换

staged 文件由 `boot` 命令应用，宿主模块把它接入 `post-fs-data.sh`，使它同步地、在 **pre-zygote** 运行，先于任何进程能映射那个新 `.so`。

`boot` 先做一次 `resume`（以完成任何被中断的阶段），然后做交换。对每个 staged 的 REBOOT-hard 文件，它：

1. 确认 staged 路径留在模块目录内（一次包含性检查）；
2. 对照清单哈希重新哈希 `staged/<path>.vdlu-new`；
3. 备份当前的 live 文件；
4. `mv -f` staged 文件覆盖 live 文件并 `chmod` 它；
5. 重新哈希如今就位的文件，以确认交换正确落地；
6. 把它标记为已应用。

只有当每个 staged 文件都已交换并重新验证之后，事务才从 `PENDING_REBOOT` 关闭为 `DONE`。如果任何一步失败，日志记录该错误，而模块保留它先前的文件；没有任何东西被留在半交换状态。

由于交换是一串重新哈希与原子 rename，运行 `boot` 即使上次被中断也是安全的。它只是把那些 staged 文件重新捡起来。

## auto_on_reboot

staging 只是免重启体验的一半；另一半是用户永远不必记得去运行那次交换。配置中有 `auto_on_reboot=1` 时，宿主模块的 `post-fs-data.sh` 在每次启动时调用 `update.sh boot`。这意味着：

- 如果一笔事务处于待重启状态，staged 文件会在 zygote 启动之前被自动交换，而用户只会发现自己已经完全在新版本上；
- 如果没有待处理内容，`boot` 可以运行一个全新周期并在那一次启动中应用一切，包括一个 `.so`，因为它已经在 pre-zygote 运行。

换言之，一个 staged `.so` 对用户的代价不超过一次他们本来就要做的重启。他们不必在第二次去点任何东西。

## 启动时离线，而不耗干电池

有时 `boot` 想检查 feed，但设备还没有网络。VDLU 能耐心而廉价地等待它，由 `boot_retry_minutes` 控制（0 关闭它）。该等待被刻意设计得对电池安全：

- 在各次尝试之间它只是 `sleep`，这在深度睡眠（deep sleep）中冻结，因此设备正常睡眠，而重试只在设备已经醒来后才续接；
- 它不持有任何 wakelock，也不在等待期间持有引擎锁，因此一次手动运行永远不会被阻塞；
- 在每次尝试之前，它用一次不发送任何数据包、也不唤醒射频的内核路由查询来检查网络是否被允许；
- 它从不重试一个确定性的失败，例如一个坏签名或一次被阻止的降级，只重试一个真正的网络缺席状况。

清单检查本身在任何网络上都保持免费，因此你总能得知存在一个更新；只有下载在等待网络策略被满足，干净地推迟，而不是报错。

## 另见

- [[Engine]]：事务、按 class 应用的逻辑，以及完整的 `boot` 命令。
- [[Architecture]]：引擎在 producer 与 WebUI 之间所处的位置。
