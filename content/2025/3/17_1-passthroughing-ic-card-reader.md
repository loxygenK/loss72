+++
title = "QEMU で多機能 IC カードリーダを Passthrough する"
brief = """
確定申告のために、<code>usbredirect</code> を使って、Arch Linux 上の QEMU 上で動作する Windows に
IC カードリーダを Passthrough してマイナンバーカードを読み取れるようにしました。
思ったより苦戦したので、その備忘録です。
"""

[widgets]
ai = "Research"
article_type = "Research"

[[widgets.sources]]
name = "usbredir - SPICE"
url = "https://www.spice-space.org/usbredir.html"

[[widgets.sources]]
name = "usbredirect(1) — Arch manual pages"
url = "https://man.archlinux.org/man/extra/usbredir/usbredirect.1.en"
+++

確定申告お疲れ様でした。

freee の "自動で経理" の未処理帳簿数が 200 とか行ってて横転しそうになりましたが、
X で 2,000 件を超える帳簿が未処理になっているという大横転の光景を目にし、
やっぱりそうなるんだなあという気持ちとそこまで行くんだなあの気持ちになりました。

ところで、私は普段は MacBook Air …… から Arch Linux が動いているデスクトップ PC に
SSH をして作業をしているのですが、今回のように Windows を使いたい場面もあるので、
Arch Linux 上で QEMU を動かして、Windows も使えるようにしています。三刀流です！

そして、Windows 上で e-Tax を使うために、IC カードリーダ経由でマイナンバーカードの
読み取りが必要だったのですが、QEMU 上で動いているのでただ USB ケーブルを指すだけでは
QEMU 上で使えるようになりません。デバイスを Passthrough するのは簡単なので、
大きな問題ではないのですが、私が使っていた IC カードリーダは **SD カードとかも読める多機能なタイプ**で、
デバイスをそのまんま Passthrough すると **USB Composite Device** とだけ認識されて
具体的なインターフェースは使えないという自体に陥りました。

この記事はそれを解決するための備忘録です。

<aside>

確定申告自体には IC カードリーダを用いたマイナンバーカード読み取りは必要ありません。
マイナポータル経由なら、QR コードを用いて、スマホでマイナンバーカードを読み取るかスマホ電子証明書を利用することができますし、freee 経由なら freee の画面/スマホアプリから書類提出が可能です（すごい）。
ただ、確定申告の前処理に e-Tax が必要で、そのログインのためにマイナンバーカードが必要だった感じです。

</aside>

# 解決策: 利用したい Interface を usbredirect でいい感じにする

この世には **USB の Interface を TCP で配信する**というすごい概念[^usbredir-protocol] が存在するらしく、
QEMU がそれに対応しています。

<aside>

**ご利用は自己責任でお願いします！** 大事な処理はこんな変なことしないで普通に
Windows PC をどこかから調達してそれでやるか、税務署に行くのが丸いと思います……！

</aside>

### 具体的な手順

1. `usbredirect` を落とします。Arch Linux はこのパッケージ名ですが、他の Distribution でもあると思う。
  というか Arch Linux であれば `qemu-full` についてくるので、すでに入ってるかも。

  ```bash
  pacman -S usbredir
  ```

2. `lsusb -t` で、リダイレクトしたいやつを見つけます。

```bash
$ lsusb -t
/:  Bus 001.Port 001: Dev 001, Class=root_hub, Driver=xhci_hcd/10p, 480M
    |__ Port 002: Dev 012, If 0, Class=Chip/SmartCard, Driver=[none], 480M
    |__ Port 002: Dev 012, If 1, Class=Mass Storage, Driver=usb-storage, 480M
    |__ Port 009: Dev 006, If 0, Class=Vendor Specific Class, Driver=xpad, 12M
    |__ Port 009: Dev 006, If 1, Class=Vendor Specific Class, Driver=[none], 12M
    |__ Port 009: Dev 006, If 2, Class=Vendor Specific Class, Driver=[none], 12M
    |__ Port 009: Dev 006, If 3, Class=Vendor Specific Class, Driver=[none], 12M
/:  Bus 002.Port 001: Dev 001, Class=root_hub, Driver=xhci_hcd/4p, 10000M
/:  Bus 003.Port 001: Dev 001, Class=root_hub, Driver=xhci_hcd/4p, 480M
    |__ Port 004: Dev 002, If 0, Class=Human Interface Device, Driver=usbhid, 12M
    |__ Port 004: Dev 002, If 1, Class=Human Interface Device, Driver=usbhid, 12M
    |__ Port 004: Dev 002, If 2, Class=Human Interface Device, Driver=usbhid, 12M
/:  Bus 004.Port 001: Dev 001, Class=root_hub, Driver=xhci_hcd/4p, 10000M
```

ここでは、`Bus 001` の下の、`Dev 012, If 0` が `Class=Chip/SmartCard` なので、
これが該当します！ [^xbox-controller]

同じ Device の別 Interface `Dev 012, If 1` に `Class=Mass Storage` が
ありますが、この IC カードリーダは SD カードも読めることから辻褄が合います。

[^xbox-controller]: 同じように大量の Interface があるやつに `Dev 006` がありますが、
こいつは XBox 360 コントローラです。こいつを Passthrough したときは特に大きな問題は
発生しませんでした。こいつは `-device` じゃなくて、`-object input-linux` で
出してるので、その違いで問題に直面しなかったのかな

3. QEMU の引数に以下を追加します。

```bash
  # Create a USB 3.0 Controller...
  -device qemu-xhci,id=xhci
  # Receive redirection...
  -chardev socket,id=scredir,host=127.0.0.1,port=12345,server=off
  # Connect it to the controller
  -device usb-redir,chardev=scredir,bus=xhci.0
```

<aside>
USB 3.0 のコントローラを作って、ソケットと接続して、
そのデバイスをコントローラにつないでいるらしい。ChatGPT 談。
</aside>

libvirt 等、別の方法で仮想マシンを立てている場合の設定方法は、申し訳ないですがわかりかねます[^why-directly-doing-that-though]、、ChatGPT に聞いたほうがいいかも。

[^why-directly-doing-that-though]: 私はなぜか自分で QEMU の引数を組み立てて使っています。そのうち libvirt に移したいですね、、


4. `usbredirect` を起動します。<br>
   後述しますが、**`(Dev)` に `1` を指定すると即死攻撃を受ける**ので本当に気をつけてください……！

```bash
$ sudo usbredirect --device "(Bus)-(Dev)-(If).0" --as 127.0.0.1:12345
```

**Port はガン無視です！** 例えば、上の例なら `1-12-0.0` が指定結果になります。

最後の `.0` は、ChatGPT 曰く `bAlternateSetting` の値らしい。
`lsusb -v` でそれも含めた細かい値を全部見れるので、
「ちゃんと指定してるのに上手くいかないんだけど」という問題が発生したら、
`bAlternateSetting` がワンチャン `0` 以外になってるかもしれません。

正しく指定できれば、エラーメッセージも何も出ず、`usbredirect` がずっとそのターミナルで
動き続けるはずです!

<aside>

`(Dev)` に `1` を指定するなど、番号の指定を盛大にミスると、
**該当するバス所属の USB デバイスが全部切断される挙げ句、
物理的に再接続しても何故か復活しなくなる**という
**デストラップ**が存在します[^root_hub-maybe]。
このデストラップを踏んだ時、**USB キーボード以外にターミナルにアクセスする方法がない場合は詰みです。**
ノーパソとかなら大丈夫かな。

[^root_hub-maybe]: `Class=root_hub` か、`Driver=xhci_hcd` な
Device を指定してしまうと破滅するっぽいです。

こんな感じになります:

```bash
$ # snip (i don't want to forcefully disconnect anybody's usbs)
(usbredirect:3385282): usbredirect-WARNING **: 02:03:34.824: Error starting usbredirhost
usbredirect: os/threads_posix.h:58: usbi_mutex_destroy: Assertion `pthread_mutex_destroy(mutex) == 0` failed.
zsh: IOT instruction  sudo usbredirect --device "1-1-2:0.0" --as 127.16.0.1:30001

$ lsusb -t
/:  Bus 001.Port 001: Dev 001, Class=root_hub, Driver=xhci_hcd/0p, 480M
/:  Bus 002.Port 001: Dev 001, Class=root_hub, Driver=xhci_hcd/4p, 10000M
/:  Bus 003.Port 001: Dev 001, Class=root_hub, Driver=xhci_hcd/4p, 480M
    |__ Port 004: Dev 002, If 0, Class=Human Interface Device, Driver=usbhid, 12M
    |__ Port 004: Dev 002, If 1, Class=Human Interface Device, Driver=usbhid, 12M
    |__ Port 004: Dev 002, If 2, Class=Human Interface Device, Driver=usbhid, 12M
/:  Bus 004.Port 001: Dev 001, Class=root_hub, Driver=xhci_hcd/4p, 10000M

# めっちゃ消えてる!!
```

こうなった場合は、少なくとも私の環境では、SSH とか何かしらでターミナルを調達して、
**Root で**以下のコマンドを叩けば治りました[^stackoverflow-guy]。

```bash
for i in /sys/bus/pci/drivers/[uoex]hci_hcd/*:*; do
  [ -e "$i" ] || continue;
  echo "${i##*/}" > "${i%/*}/unbind";
  echo "${i##*/}" > "${i%/*}/bind";
done 
```

これ以外のミスり方であれば、今のところ私は単純に "Failed to open a device!" と
言われるだけで済んでいますが、他にもデストラップが隠れてる可能性はあるので、
番号指定はご用心ください。

</aside>

5. 後は QEMU を起動すれば使えるはずです！
   Windows にログイン後、Windows+X → デバイスマネージャで、スマートカードリーダーが
   認識されていれば、Windows も JPKI の仲間入りです！

[^usbredir-protocol]: [https://www.spice-space.org/usbredir.html](https://www.spice-space.org/usbredir.html)
[^stackoverflow-guy]: [https://askubuntu.com/a/290519](https://askubuntu.com/a/290519)
