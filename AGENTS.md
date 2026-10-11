# エージェントの作業規約

## このプロジェクト

- 新アプリは `src/SeasoningManager/SeasoningManager.xcodeproj` の SwiftUI / SwiftData アプリ。
- 単体テストは Swift Testing、UI テストは XCTest。スキームは `SeasoningManager`。
- `old/` は移行調査用。新機能の実装先にせず、CocoaPods や旧 UIKit 構成を持ち込まない。
- 目標の仕様は [仕様書一覧](docs/seasoning-management/index.md)。実装済みかはコードとテストで確かめる。
- 対応 OS・Swift モード・actor isolation は Xcode 設定、CI 環境は既存 workflow を確認する。
  ハーネス導入を理由にデプロイメントターゲットを変更しない。

## 着手時に読むもの

次のファイルを実際に開く。`@` import やスキルの自動発見に依存しない。

1. [Swift の書き方と責務](rules/swift.md)
2. [SwiftUI の状態と画面](rules/swiftui.md)
3. [SwiftData と保存境界](rules/swiftdata.md)
4. [テストと検証](rules/testing.md)
5. [.claude/skills/implementation-flow/SKILL.md](.claude/skills/implementation-flow/SKILL.md)

## 作業の単位

- 原則は 1 Issue / 1 PR、実装変更は 1〜2 ファイル程度を目安にする。
- 独立してマージできる変更は分ける。テスト・設定などを同時に変える必要があれば理由を残す。
- 既存 Issue があれば計画・却下した案・理由をそこへ残す。直接の依頼では PR 本文に残せばよく、
  ハーネスのためだけに Issue を増やさない。Issue 対応の PR には `Closes #番号` を書く。
- 既に依頼された実装・検証・PR 作成は進める。通常の実装判断で承認待ちにせず、マージは依頼時に行う。
- GitHub Actions は GitHub 公式のものだけを使い、40 桁のコミット SHA に固定する。

## 検証と記録

- 計画と差分を `.claude/agents/` の観点で検証する。別エージェントが使えるときは読み取り専用で依頼する。
  使えないときは同じ定義を読み、自己検証であることを PR に明記する。
- push 前に `bash harness/githooks/pre-push`。iOS の検証は [検証コマンド](harness/README.md)に従う。
- 実行できなかった検証は未実施として報告する。Linux の配置検査を Swift のビルド成功と扱わない。
- 完了時は [PR の検証結果コメント](harness/README.md#pr-の検証結果コメント)に従い、テスト結果・
  CI のカバレッジ・所要時間・未実施項目を PR コメントへ残す。最新コミットの CI 状態も確認する。
- マージ後の記録依頼では [.claude/skills/harness-record/SKILL.md](.claude/skills/harness-record/SKILL.md)を使う。
  蓄積した記録からの改善は [.claude/skills/harness-growth/SKILL.md](.claude/skills/harness-growth/SKILL.md)で別に行う。
- `rules/` は短い判断基準、`harness/case-law/` は必要時だけ読む実例、`harness/records/` は PR ごとの結果。
  常時読む `AGENTS.md` と `rules/*.md` は合計 200 行以内に保つ。追加前に重複と不要な記述を削る。

構成・検査の限界・参考ナレッジは [harness/README.md](harness/README.md) を参照する。
