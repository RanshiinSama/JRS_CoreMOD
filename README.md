# Ramen MODs for Japanese Ramen Simulator

*Japanese Ramen Simulator* 向けの UE4SS Lua MOD 集です。製作: AIlly

| MOD | バージョン | 内容 |
|---|---|---|
| RamenCore | 0.11.0 | 全MOD共通の前提ライブラリ（必須）。MOD登録・設定・ログ・ゲーム状態取得 |
| RamenUI | 0.7.0 | ゲーム内のMOD一覧・設定パネル（必須扱い）。有効/無効切替、設定編集、キー割り当て変更、MOD再読込 |
| RamenMoney | 0.5.0 | 所持金の追加（既定 `F7`）と、指定額への変更（既定 `F8`）。0～9999999 |
| RamenOutline | 0.4.0 | アウトラインの色・太さ変更、コップ・ジョッキ・ボトルを個別に選べる常時アウトライン（既定 `F9` で全体のON/OFF） |

## 目次

- [必要なもの](#必要なもの)
- [UE4SS の導入方法](#ue4ss-の導入方法)
- [インストール](#インストール)
- [使い方](#使い方)
- [既知の制限](#既知の制限)
- [アンインストール](#アンインストール)
- [注意](#注意)
- [ライセンスと利用条件](#ライセンスと利用条件)

## 必要なもの

- UE4SS 3.0.1（experimental 版）が導入済みであること
  （Japanese Ramen Simulator の `RealRamenSimulator\Binaries\Win64\` に `UE4SS.dll` がある状態）
- これらの MOD は Lua MOD です。UE4SS 本体は同梱していません。

## UE4SS の導入方法

未導入の場合の手順です。動作確認した版は UE4SS v3.0.1（Git SHA `03dbd5c0` / zip 名 `UE4SS_v3.0.1-1151-g03dbd5c0.zip`）です。

1. [配布ページ](https://github.com/UE4SS-RE/RE-UE4SS/releases)を開きます。
   「experimental-latest」（または v3.0.1 以降の experimental 版）の Assets から、`UE4SS_v3.0.1-～.zip` をダウンロードします。
   名前が「z」で始まるものや「DEV」版ではなく、普通の `UE4SS_v～.zip` を選びます。配布ページの並びや名前は変わることがあります。
2. ゲームの実行ファイルがあるフォルダを開きます。`RealRamenSimulator-Win64-Shipping.exe` があるフォルダです。
   ```
   <Steam>\steamapps\common\Japanese Ramen Simulator\RealRamenSimulator\Binaries\Win64\
   ```
3. zip の中身（`dwmapi.dll` と `ue4ss` フォルダ）を、そのフォルダにすべて展開します。
   展開後、次のようになっていれば成功です。
   ```
   Win64\dwmapi.dll
   Win64\ue4ss\UE4SS.dll
   Win64\ue4ss\UE4SS-settings.ini
   Win64\ue4ss\Mods\   (mods.txt や標準MODが入っています)
   ```
   zip の構造が違う場合（Win64 直下に `UE4SS.dll` がある旧構成など）でも、
   「`UE4SS.dll` と `UE4SS-settings.ini` と `Mods` フォルダが同じ場所にあること」と、
   「`dwmapi.dll` が exe と同じフォルダにあること」を目安に配置してください。
4. ゲームを起動します。動作確認は、`ue4ss` フォルダに `UE4SS.log` ができることと、
   その先頭に「UE4SS - v3.0.1 …」と書かれていることで行えます。
5. うまく動かない場合:
   - ウイルス対策ソフトが `dwmapi.dll` を隔離することがあります。除外設定を確認してください。
   - ゲームのアップデート直後は、UE4SS 側の更新が必要なことがあります。
   - UE4SS を外すときは、Win64 の `dwmapi.dll` と `ue4ss` フォルダを削除します。
   - UE4SS は別の作者の配布物です。詳しくは [UE4SS の公式ドキュメント](https://docs.ue4ss.com/)を参照してください。

## インストール

1. [Releases](../../releases) から最新の zip をダウンロードします。
2. 中の `ue4ss` フォルダの中身を、次の場所へ上書きコピーします。
   `Mods` フォルダの中に RamenCore、RamenMoney、RamenOutline、RamenUI、shared が入ります。
   ```
   <Steam>\steamapps\common\Japanese Ramen Simulator\RealRamenSimulator\Binaries\Win64\ue4ss\
   ```
3. `ue4ss\Mods\mods.txt` を開き、次の4行を `Keybinds : 1` の行より前に追加します（RamenCore が先頭になるように）。
   同じ内容を「mods.txt 追記内容.txt」にも入れています。
   ```
   RamenCore : 1
   RamenMoney : 1
   RamenOutline : 1
   RamenUI : 1
   ```
4. （推奨）`ue4ss\UE4SS-settings.ini` で、次の2項目を `1` にします。
   ```
   EnableHotReloadSystem = 1        (Ctrl+R で全MOD再読込)
   EnableAutoReloadingLuaMods = 1   (パネルの「MOD再読込」ボタンに必要)
   ```
   NVIDIA / Steam のオーバーレイと干渉する場合は、次を `0` にするとコンソール画面が出なくなります。
   ```
   ConsoleEnabled = 0
   GuiConsoleEnabled = 0
   GuiConsoleVisible = 0
   ```
5. ゲームを起動し、セーブデータを読み込みます。

## 使い方

- `F5`（またはポーズメニュー（Esc）の最下部にある「MOD」ボタン）で、MOD 一覧・設定パネルを開閉します。
- 左の一覧で MOD を選ぶと、右に説明・キー割り当て・設定が出ます。
- 「有効/無効」は次回起動から反映されます（無効にするとゲーム中も機能が止まります）。RamenCore と RamenUI は無効にできません。
- 設定を変更して「保存」を押すと、1秒以内に反映されます。「初期値に戻す」は、保存するまで反映されません。
- キー割り当て: `A`～`Z`、`0`～`9`、`NUM0`～`NUM9`、`F1`～`F10`、`INS` `DEL` `HOME` `END` `PGUP` `PGDN` が使えます。
  - 空欄、または「なし(解除)」で割り当てを解除できます。
  - MOD 同士でキーが重なる設定は保存できません。
  - ゲーム本来の操作キーと重なっても警告しません。文字キーは、ゲーム内の文字入力中にも反応するのでご注意ください。
  - `F11` はゲームのフルスクリーン切替、`F12` は Steam のスクリーンショットに使われるため、選べません。
- 設定ファイル: `ue4ss\Mods\RamenCore\Configs\*.ini`（直接編集も可。ゲームを起動したまま編集しても1秒以内に反映）
- ログ: `ue4ss\Mods\RamenCore\RamenCore.log`

## 既知の制限

- コップを積み重ねた場合、常時アウトラインは一番下の1個にしか付きません（クロスヘアを合わせている間は、ゲーム本来の処理で全体に付きます）。
- ポーズメニューの「MOD」ボタンは、メニューの最下部に追加されます。
- 「MOD再読込」や `Ctrl+R` のあとに動作がおかしい場合は、ゲームを再起動してください。

## アンインストール

`mods.txt` の4行を削除するか「`: 0`」にして、`ue4ss\Mods` の RamenCore、RamenMoney、RamenOutline、RamenUI、shared を削除します。

## 注意

- 自己責任でご利用ください。ゲームのアップデートで動かなくなる場合があります。
- 所持金の変更は、Steam 実績などに影響する可能性があります。ご自身の判断でお使いください。

## ライセンスと利用条件

[CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/deed.ja)（表示 - 非営利 4.0 国際）で公開しています。全文は [LICENSE](LICENSE) を参照してください。

**できること**
- 個人利用、改変、非営利での再配布（改変版の公開を含む）
- このソースコードを元にした新しい MOD の作成と公開（非営利に限る）

**守ってほしいこと**
- **クレジット表示（必須）**: 改変版・派生 MOD を公開するときは、説明文などに次の3点を書いてください。
  1. 元作者の名前（AIlly）
  2. 元のリポジトリ URL（https://github.com/RanshiinSama/JRS_CoreMOD）
  3. ライセンス（CC BY-NC 4.0）へのリンク。改変した場合は、その旨も書いてください。
- **商用利用の禁止**: 有料での配布・販売、金銭を得ることを主な目的とした利用はできません。
  - 支払い・サブスクリプション・特典付き寄付などの対価を条件にしたダウンロード（Patreon、Ko-fi などを用いた会員限定配布を含む）は、商用利用とみなします。
  - 無料で誰でも入手できる配布に、任意の寄付ボタンを置くことは構いません。

### RamenCore を使って MOD を作りたい方へ

RamenCore（`ue4ss/Mods/RamenCore` と `ue4ss/Mods/shared/RamenCoreLib.lua`）を**前提にして、その関数を呼び出すだけの MOD** は、このリポジトリの派生物とはみなしません。次のとおり扱えます。

- 自分の MOD のコードには、好きなライセンスを付けられます。
- ただし、**非営利での配布に限ります**（RamenCore が CC BY-NC のため、有料配布の MOD の前提にはできません）。
- お願い: 説明文に「前提 MOD: RamenCore（AIlly / https://github.com/RanshiinSama/JRS_CoreMOD）」と書いてください。
- このリポジトリのソースを**コピー・改変して取り込む場合**は、上記の CC BY-NC 4.0（クレジット表示・非営利）がそのまま適用されます。

UE4SS は別の作者による配布物で、それぞれのライセンスに従います。
