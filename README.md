# seasoning-management-iOS

調味料の在庫・使用中・賞味期限を管理する iOS アプリ。機能の目標は[仕様書](docs/seasoning-management/index.md)を参照してください。

## 現在の構成

- `src/SeasoningManager/SeasoningManager.xcodeproj`: SwiftUI / SwiftData の新しい iOS App。現時点では Xcode のひな形で、調味料の機能は未実装です。
- `src/SeasoningManager/SeasoningManagerTests`: Swift Testing の単体テスト。
- `src/SeasoningManager/SeasoningManagerUITests`: XCTest の UI テスト。
- `old/src/SeasoningManager`: 旧 UIKit / Core Data アプリ。既存データ移行の参考として保持します。
- `old/src/old/SeasoningManagement`: さらに古い試作コード。

## エージェントでの開発

共通の作業規約は [AGENTS.md](AGENTS.md)、Swift のルールと検査・記録の使い方は
[エージェントのハーネス](harness/README.md)を参照してください。Claude Code は `CLAUDE.md` から同じ規約を読み込みます。

## 開き方

`src/SeasoningManager/SeasoningManager.xcodeproj` を Xcode で開いてください。新アプリは CocoaPods を使用しないため、`pod install` や独立した `.xcworkspace` の作成は不要です。同じ `.xcodeproj` にフレームワークのターゲットを追加する場合も、このプロジェクトからビルドできます。

現在のデプロイメントターゲットは iOS 27.0、Bundle ID は `DIO0550.SeasoningManager` です。CloudKit のコンテナ識別子はまだ設定されていません。iCloud 同期と旧 Core Data から SwiftData への移行は未実装です。旧アプリのデータがある端末へ更新としてインストールする前に、移行を実装して検証してください。

## UIモックアップ

画面構成や操作の検討用に、[単体HTMLのUIモックアップ](docs/seasoning-management/mockups/seasoning-management-mockup.html)を置いています。在庫・テンプレート・設定の画面を試せます。

リポジトリをクローンするかリンク先のHTMLをダウンロードして、手元のブラウザーで開いてください。GitHub上ではHTMLのソースが表示されます。CSS・JavaScriptは内蔵しているため、サーバー起動や依存パッケージのインストールは不要です。

架空のデータを使うデザイン・操作確認用のモックです。変更はメモリ内だけに保存され、再読み込みすると初期状態に戻ります。
