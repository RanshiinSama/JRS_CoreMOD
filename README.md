# Ramen MODs for Japanese Ramen Simulator

*Japanese Ramen Simulator* 向けの UE4SS Lua MOD 集です。製作: AIlly

| MOD | バージョン | 内容 |
|---|---|---|
| RamenCore | 0.11.0 | 全MOD共通の前提ライブラリ（必須）。MOD登録・設定・ログ・ゲーム状態取得 |
| RamenUI | 0.7.0 | ゲーム内のMOD一覧・設定パネル。有効/無効切替、設定編集、キー割り当て変更、MOD再読込 |
| RamenMoney | 0.5.0 | 所持金の追加（既定 `F7`）と、指定額への変更（既定 `F8`）。0～9999999 |
| RamenOutline | 0.4.0 | アウトラインの色・太さ変更、コップ・ジョッキ・ボトルを個別に選べる常時アウトライン（既定 `F9` でON/OFF） |

## 必要なもの

- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS/releases) 3.0.1（experimental 版）が導入済みであること
- UE4SS 本体は同梱していません。導入方法は [README.txt](README.txt) を参照してください。

## インストール

1. [Releases](../../releases) から最新の zip をダウンロードします。
2. 中の `ue4ss` フォルダの中身を、次の場所へ上書きコピーします。
   ```
   <Steam>\steamapps\common\Japanese Ramen Simulator\RealRamenSimulator\Binaries\Win64\ue4ss\
   ```
3. `ue4ss\Mods\mods.txt` の `Keybinds : 1` の行より前に、次の4行を追加します（RamenCore を先頭に）。
   ```
   RamenCore : 1
   RamenMoney : 1
   RamenOutline : 1
   RamenUI : 1
   ```
4. ゲームを起動し、セーブデータを読み込みます。

## 使い方

`F5`（またはポーズメニューの「MOD」ボタン）で MOD 一覧・設定パネルを開閉します。
詳しい使い方、キー割り当て、既知の制限は [README.txt](README.txt) にまとめています。

## 注意

- 自己責任でご利用ください。ゲームのアップデートで動かなくなる場合があります。
- 所持金の変更は、Steam 実績などに影響する可能性があります。

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
