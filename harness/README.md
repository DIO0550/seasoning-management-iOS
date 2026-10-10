# エージェントのハーネス

design-composer の「規約・検証・記録・改善」の分担を、SwiftUI / SwiftData 向けに小さく導入する。

| 場所 | 役割 |
| --- | --- |
| `AGENTS.md` / `CLAUDE.md` | 共通の入口 / `AGENTS.md` へのシンボリックリンク |
| `rules/` | 着手時に読む短い規約 |
| `.claude/skills/` | 実装、マージ後の記録、蓄積からの改善を別々に実行 |
| `.claude/agents/` | 計画、Swift 設計、テストの読み取り専用レビュー |
| `.claude/settings.json` / `.claude/hooks/` | Claude Code で編集後に配置検査の結果を返す |
| `harness/githooks/pre-push` | エージェントに依存しない push 前検査 |
| `harness/records/` / `harness/case-law/` | PR ごとの結果 / 必要時だけ読む判断の実例 |

Codex などのエージェントは `AGENTS.md` からスキル・レビュー定義を直接読む。
Claude 固有の hook が動かない環境でも、下記の検査を直接実行できる。

## 共通の検査

Python 3 と Bash を使う。CI のコメント集計テストには Node.js も使う（GitHub のランナーに同梱）。
追加のパッケージは不要。Node.js がない環境では集計の JavaScript テストを未実施として skip する。

```bash
bash harness/githooks/pre-push
```

ハーネス内の Markdown 参照・スキル/レビュー定義の必須メタデータ・hook の参照先・
常時読む規約の行数、検査スクリプトの判定テスト、差分の空白と、変更した Swift の lint を確認する。
未コミット差分に加え、ローカルでは `origin/master...HEAD`、PR の CI では base と head の差分を検査する。
配置検査自体は Swift の構文・actor isolation・業務設計を判定しない。
整形は下記の公式 `swift-format` で検査する。正規表現で Swift lint を自作せず、SwiftLint の依存は追加しない。

ローカル Git に自動実行を設定する場合は、既存の `core.hooksPath` を確認してから実行する。
既存の hook がある場合は統合を検討し、上書きしない。

```bash
git config --get core.hooksPath
git config --local core.hooksPath harness/githooks
```

通常の pre-push は lint を必須で実行し、対象があるのにツールがなければ失敗する。
Git が渡す remote 名・URL の2引数にも対応し、Git の標準入力は formatter に渡さない。
Linux の `Agent harness` CI は `bash harness/githooks/pre-push --configuration-only` を明示して、配置と回帰テストだけを検査する。
このモードは「配置検査のみ・Swift lint 未実施」と表示し、実ツールの成功として扱わない。未知のオプションは失敗する。
Swift の lint は push 前と Mac の `Swift format` CI で実行する。編集後の hook は配置検査だけを行う。
Git hook が未設定の場合や GitHub API 経由の更新ではローカルの自動検査は走らないので、直接実行と CI 結果を確認する。

## Swift の整形とlint

公式の Swift ツールチェーンに同梱された `swift format` を使う。専用 CI と同じ Xcode 16.4 を選択する。
アプリのビルドと iOS テストが使う Xcode 27 とは別の検証。Linux CI の配置検査だけは明示的に lint を省く。

```bash
export DEVELOPER_DIR=/Applications/Xcode_16.4.app/Contents/Developer
swift --version
swift format --version
python3 harness/swift-format.py lint
python3 harness/swift-format.py format
```

`.swift-format` は4スペース、120文字、空行は最大1行とし、既存の改行を尊重する。
formatter は構文上の整形とスタイルを検査し、SOLID・保存境界・actor 設計などのレビューを代替しない。
段階的に導入するため、対象は `src/` 内で変更した既存の `.swift` ファイル。
通常は `origin/master...HEAD` のコミット差分と staged / unstaged / untracked の変更を合わせる。
`old/`、削除済みのファイル、他の拡張子、シンボリックリンクとリンク配下のファイルは除外する。
リポジトリ全体の一括整形は別の作業とする。

リポジトリのルートを基準にファイルを明示指定することもできる。範囲外や存在しないファイルの指定は失敗する。
別のディレクトリからスクリプトを起動しても、設定と実行場所はこのリポジトリのルートを使う。

```bash
python3 harness/swift-format.py lint src/SeasoningManager/SeasoningManager/ContentView.swift
python3 harness/swift-format.py format src/SeasoningManager/SeasoningManager/ContentView.swift
```

`Swift format` CI は `macos-15` と Xcode 16.4 を使い、PR の head を checkout する。
`HARNESS_FORMAT_BASE` と `HARNESS_FORMAT_HEAD` を両方渡し、検証した参照の merge-base から対象を選ぶ。
この参照を指定した場合はそのコミット差分だけを検査し、ローカルの staged / unstaged / untracked は合算しない。
push の初回で base がゼロ SHA の場合は head の `src/` 内のファイルを対象とする。不正な参照や片方だけの指定は失敗する。
対象が0件なら「対象なし・実ツール未実行」として終了し、対象があるのに Swift がない場合は終了コード2を返す。
整形ツールと Git の失敗は成功扱いせず終了コードを返す。lint は `--strict`、format は `--in-place` で実行する。

共通 pre-push は偽ツールでファイル選択・引数・終了コードの境界を検証する。
Claude の `PostToolUse` hook は `Edit|Write` の後に配置検査だけを行い、Swift の lint や自動整形は実行しない。
Swift の変更は編集に使ったツールにかかわらず、pre-push の差分 lint で検査する。
指摘を受けたら上記の `python3 harness/swift-format.py format` で手動整形し、lint を再実行する。

実ツールの fixture 検証は、lint 成功 → 整形違反で lint 失敗 → format → lint 成功を確認する。
Swift のないローカル環境ではこの実ケースを未実施として skip する。
専用 CI は `swift format --version` と `HARNESS_REQUIRE_SWIFT_FORMAT=1` により、実ケースを必須とし skip で成功させない。
同じ Mac CI で pre-push の実ツール検証も行い、整形違反を拒否してファイルを変更しないことを確認する。
偽ツールのテスト成功を、Swift の実行・ビルド成功として記録しない。

## iOS の検証（Mac + Xcode）

プロジェクトに対応する Xcode を選び、まず利用可能な destination を確認する。

```bash
xcodebuild -version
xcodebuild -showdestinations -project src/SeasoningManager/SeasoningManager.xcodeproj -scheme SeasoningManager
bash harness/test-ios.sh SeasoningManagerTests 'platform=iOS Simulator,id=<利用可能なUDID>'
bash harness/test-ios.sh SeasoningManagerUITests 'platform=iOS Simulator,id=<利用可能なUDID>'
```

既存の iOS CI もこのスクリプトを呼ぶ。`all` で両ターゲットを実行できる。
Linux や Xcode のない環境では終了コード 2 で未実施を知らせる。対応 OS を下げて検証を通さない。
ハーネスだけの変更でも、iOS CI が環境待ちなら、その状態を Swift の成功と書かない。

## PR の検証結果コメント

完了時は PR 本文に加えて、エージェントが PR へ検証結果のコメントを残す。対象の head SHA、
実行コマンドと環境、成功・失敗・スキップ件数、各 CI の状態と実行リンク、カバレッジと所要時間を記す。
この直接依頼による完了報告は投稿してよい。実行・計測していない項目は未実施・未取得と理由を書く。
キュー待ちの CI がある場合も現状をコメントし、完了済みとは書かない。レビュー修正後は最新コミットに更新する。

`iOS tests` CI は両ターゲットの終了後、単体・UIそれぞれの成功・失敗・スキップ件数、
`SeasoningManager.app` の行カバレッジ（実行された行 / 実行可能な行）、テスト工程とジョブ全体の時間を
1件のコメントへ集約する。テスト用コードのカバレッジは含めず、単体・UIの値を合算しない。
テスト工程はビルド込み、ジョブ全体は準備・結果収集込みで、キュー待ち時間やアプリ性能ではない。
集計用の JSON レポートを14日間保存する。コメントには検証済みの数値を使い、失敗・結果なし・ダウンロード失敗も明示する。
再実行時は bot 自身の専用コメントを更新し、古いコミットや古い実行結果で上書きしない。
今回の attempt の結果だけを集計するため、失敗ジョブだけの再実行では、今回再実行しないターゲットの値が未取得となる場合がある。

コメント権限は集約ジョブだけに付け、PR のコードを checkout / 実行しない。
fork の PR は読み取り専用トークンのため Actions の Summary に表示する。
workflow 全体の取消やランナー待ちでは集約ジョブが実行されないことがあり、その状態はエージェントが完了報告に記す。
自動コメントの対象は iOS CI だけ。`Agent harness` / `Swift format` とローカル検証はエージェントが別途報告する。
自動コメントと完了報告が揃っているか確認し、取得できていない数値を推測で埋めない。

ローカルでも結果を保存してカバレッジを有効にする場合は、新規の出力先を指定する。

```bash
HARNESS_RESULT_BUNDLE=/tmp/SeasoningManagerTests.xcresult \
  bash harness/test-ios.sh SeasoningManagerTests 'platform=iOS Simulator,id=<利用可能なUDID>'
xcrun xcresulttool get test-results summary --path /tmp/SeasoningManagerTests.xcresult
xcrun xccov view --report --json /tmp/SeasoningManagerTests.xcresult
```

## 記録からの改善

記録はマージ後に `harness-record`、規約や装置の改善は別の依頼で `harness-growth` を使う。
記録の中で推測した失敗や他リポジトリの判例は作らない。規約を足す前に、再発の根拠と不要な規約を確認する。
Swift 向けの初期判断と参照元は [references.md](references.md) に記載する。
