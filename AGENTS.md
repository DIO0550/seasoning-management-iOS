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
- メインエージェントは既に依頼された実装・検証・PR 作成を進める。
  通常の実装判断で承認待ちにせず、マージは依頼時に行う。
- GitHub Actions は GitHub 公式のものだけを使い、40 桁のコミット SHA に固定する。

## 役割分担

- ユーザーの依頼を受けるメインエージェントはオーケストレーターとして、会話・計画の採用・担当への指示・
  レビューの判断・差分統合・Git 操作・PR 作成・CI 確認を担当する。計画作成と実装は各担当へ委譲する。
- サブエージェントにも共通規約を適用するが、担当範囲は親が渡す依頼と各役割定義に限定する。
  [planner](.claude/agents/planner.md) は計画、[implementer](.claude/agents/implementer.md) は指定ファイルの実装と検証を担当する。
  サブエージェントは再委譲・Git の変更操作・外部通信を行わない。3つのレビュー役は読み取り専用を維持する。
- 実装担当は1人に限定し、親や他の担当が同時に編集しない。計画・レビュー結果は親が根拠を確認して次へ渡す。
- Codex 等でも役割定義を直接読み、委譲時に定義の内容と必要な入力を渡す。
  サブエージェントを使えなければメインが各定義に従って代行し、委譲できなかった役割と自己レビューを報告する。

## 検証と記録

- 計画は `plan-reviewer`、差分は `swift-reviewer` と `test-reviewer` の観点で検証する。
  入力・差し戻し・実行順序は [implementation-flow](.claude/skills/implementation-flow/SKILL.md) に従う。
- メインエージェントは push 前に `bash harness/githooks/pre-push` を実行する。
  iOS の検証は [検証コマンド](harness/README.md)に従う。
- 実行できなかった検証は未実施として報告する。Linux の配置検査を Swift のビルド成功と扱わない。
- マージ後の記録依頼では [.claude/skills/harness-record/SKILL.md](.claude/skills/harness-record/SKILL.md)を使う。
  蓄積した記録からの改善は [.claude/skills/harness-growth/SKILL.md](.claude/skills/harness-growth/SKILL.md)で別に行う。
- `rules/` は短い判断基準、`harness/case-law/` は必要時だけ読む実例、`harness/records/` は PR ごとの結果。
  常時読む `AGENTS.md` と `rules/*.md` は合計 200 行以内に保つ。追加前に重複と不要な記述を削る。

構成・検査の限界・参考ナレッジは [harness/README.md](harness/README.md) を参照する。
