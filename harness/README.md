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

Python 3 と Bash を使う。追加のパッケージは不要。

```bash
bash harness/githooks/pre-push
```

ハーネス内の Markdown 参照・スキル/レビュー定義の必須メタデータ・hook の参照先・
常時読む規約の行数、検査スクリプトの判定テスト、差分の空白を確認する。
未コミット差分に加え、ローカルでは `origin/master...HEAD`、PR の CI では base と head の差分を検査する。
Swift の構文・actor isolation・業務設計はこの検査で判定しない。
Swift の整形は下記の公式 `swift-format` を別に実行する。正規表現で Swift lint を自作せず、SwiftLint の依存は追加しない。

ローカル Git に自動実行を設定する場合は、既存の `core.hooksPath` を確認してから実行する。
既存の hook がある場合は統合を検討し、上書きしない。

```bash
git config --get core.hooksPath
git config --local core.hooksPath harness/githooks
```

CI の `Agent harness` も同じ入口を実行する。Claude の編集後 hook は配置検査だけで、push の検査は Git hook / CI が担う。
Git hook が未設定の場合や GitHub API 経由の更新ではローカルの自動検査は走らないので、直接実行と CI 結果を確認する。

## Swift の整形とlint

公式の Swift ツールチェーンに同梱された `swift format` を使う。専用 CI と同じ Xcode 16.4 を選択する。
アプリのビルドと iOS テストが使う Xcode 27 とは別の検証で、Linux の pre-push へ Swift の必須依存は追加しない。

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
実ツールの fixture 検証は、lint 成功 → 整形違反で lint 失敗 → format → lint 成功を確認する。
Swift のないローカル環境ではこの実ケースを未実施として skip する。
専用 CI は `swift format --version` と `HARNESS_REQUIRE_SWIFT_FORMAT=1` により、実ケースを必須とし skip で成功させない。
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

## 記録からの改善

記録はマージ後に `harness-record`、規約や装置の改善は別の依頼で `harness-growth` を使う。
記録の中で推測した失敗や他リポジトリの判例は作らない。規約を足す前に、再発の根拠と不要な規約を確認する。
Swift 向けの初期判断と参照元は [references.md](references.md) に記載する。
