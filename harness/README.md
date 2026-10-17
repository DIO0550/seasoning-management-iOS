# エージェントのハーネス

design-composer の「規約・検証・記録・改善」の分担を、SwiftUI / SwiftData 向けに小さく導入する。

| 場所 | 役割 |
| --- | --- |
| `AGENTS.md` / `CLAUDE.md` | 共通の入口 / `AGENTS.md` へのシンボリックリンク |
| `rules/` | 着手時に読む短い規約 |
| `.claude/skills/` | 実装、マージ後の記録、蓄積からの改善を別々に実行 |
| `.claude/agents/` | 計画担当・実装担当と、計画 / Swift 設計 / テストの読み取り専用レビュー |
| `.claude/settings.json` / `.claude/hooks/` | Claude Code で編集後に配置検査の結果を返す |
| `harness/githooks/pre-push` | エージェントに依存しない push 前検査 |
| `harness/records/` / `harness/case-law/` | PR ごとの結果 / 必要時だけ読む判断の実例 |

Codex などのエージェントは `AGENTS.md` からスキル・役割定義を直接読み、委譲時に定義の内容を担当へ渡す。
Claude の `tools` 設定は他環境の権限へ自動適用されないため、親が各環境の機能に合わせて担当範囲を指定する。
Claude 固有の hook が動かない環境でも、下記の検査を直接実行できる。

## 担当と実行順序

| 担当 | 入力と役割 | 親へ返す結果 |
| --- | --- | --- |
| メインエージェント（親） | オーケストレーターとして会話、計画の採用、指示、レビュー判断、差分統合、Git / PR / CI を担当 | ユーザーへ変更と検証結果、未完了事項を報告 |
| [planner](../.claude/agents/planner.md) | 依頼・仕様・既存差分と調査範囲を読み取り専用で調べる | 完了条件、対象外、変更ファイルと理由、方針と根拠、検証、未確定事項 |
| [implementer](../.claude/agents/implementer.md) | 採用済み計画、許可ファイル、検証コマンドに従って実装し、親から受けた指摘を修正 | 変更と完了条件の結果、検証コマンド・環境・終了結果、未実施理由、残る指摘と逸脱 |
| `plan-reviewer` | 親から計画・完了条件・仕様とコードの参照先を受け、読み取り専用で検証 | 根拠のある計画指摘と未確認事項 |
| `swift-reviewer` / `test-reviewer` | 親から最終差分・完了条件・仕様と検証結果を受け、読み取り専用で検証 | 根拠のある差分指摘と未確認事項 |

依頼 → planner → plan-reviewer → implementer → 差分レビュー → 親の pre-push / Git / PR の順に進める。
親が計画指摘の根拠を確認して planner へ差し戻し、解消後に実装へ進む。
差分の指摘は親が根拠を確認して implementer へ渡す。Swift を変えない場合は該当するレビュー観点だけ使う。
実装担当は1人に限定し、親や他の担当は同時に編集しない。前提や許可ファイルの変更は親へ返し、親が計画を見直す。
サブエージェントは再委譲・Git の変更操作・commit / push・PR 作成・外部通信を行わない。
サブエージェントを使えなければ親が定義に従って代行し、委譲できなかった役割と自己レビューを報告して進める。
具体的な受け渡しと差し戻しは [implementation-flow](../.claude/skills/implementation-flow/SKILL.md) に従う。

## 共通の検査

Python 3 と Bash を使う。CI のコメント集計テストには Node.js も使う（GitHub のランナーに同梱）。
追加のパッケージは不要。Node.js がない環境では集計の JavaScript テストを未実施として skip する。

```bash
bash harness/githooks/pre-push
```

ハーネス内の Markdown 参照・スキル/エージェント定義の必須メタデータ・hook の参照先・
常時読む規約の行数、検査スクリプトの判定テスト、差分の空白と、変更した Swift の lint を確認する。
planner / implementer を含む5役の定義を必須とし、各定義の frontmatter、名前、説明を検査する。
未コミット差分に加え、ローカルでは `origin/master...HEAD`、PR の CI では base と head の差分を検査する。
この配置検査は、実際の委譲や編集・Git 操作・外部通信の制限を実行時に強制するものではない。
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
1件のコメントを「🧪 テスト結果」「📊 カバレッジ」「⏱️ 実行時間」に分けて表示する。
状態は絵文字、カバレッジは🟢80%以上・🟠80%未満・⚪未取得で示す。末尾の定型説明は付けず、
欠測・収集失敗・省略だけを短く表示する。テスト用コードのカバレッジは含めず、単体・UIの値を合算しない。
テスト工程はビルド込み、ジョブ全体は準備・結果収集込みで、キュー待ち時間やアプリ性能ではない。
結果をジョブ出力で受け渡し、Actions へのファイル添付は行わない。コメントの上部に80%未満のファイルを
低い順に各検証10件、遅いテストを時間の長い順に各検証10件表示する。全ファイルの行カバレッジと
全テストの結果・実行時間は `<details>` に折りたたむ。テスト別時間は xcresult の値で、スキップは未実施とする。
コメントには検証済みの数値を使い、失敗・結果なし・収集失敗も明示する。
ジョブ出力は60,000 ASCII文字以内、詳細表はコメント全体が60,000文字未満に収まる量に制限する。
上限時は低カバレッジ・遅いテストを優先し、省略件数を明示する。長いファイル名・テスト名は省略表示する。
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
xcrun xcresulttool get test-results tests --path /tmp/SeasoningManagerTests.xcresult
xcrun xccov view --report --json /tmp/SeasoningManagerTests.xcresult
```

## 記録からの改善

記録はマージ後に `harness-record`、規約や装置の改善は別の依頼で `harness-growth` を使う。
記録の中で推測した失敗や他リポジトリの判例は作らない。規約を足す前に、再発の根拠と不要な規約を確認する。
Swift 向けの初期判断と参照元は [references.md](references.md) に記載する。

## PR の解説 HTML

[pr-explain](../.claude/skills/pr-explain/SKILL.md) は、人が diff を読む前に変更の全体像をつかめるように、
構造マップ・変更の経緯・テスト・振る舞い・技術の手引きの 5 画面を生成する。
[implementation-flow](../.claude/skills/implementation-flow/SKILL.md) の手順 7 から、PR 作成直後、
振る舞いが変わる push の後、reopen 後に実行する。差分から作る `change-map.json` と、
セッションがソースで主張を確かめて書く `explain.json` を固定 HTML に組み合わせる。
解説は PR ブランチや master にコミットせず、リポジトリの外で作って検査する。

### ローカル生成と表示

Python 3 と Git で生成できる。解説をまだ書いていなくても地図とコミットを表示でき、
未記入の解説を推測で補わない。出力先はリポジトリの外にする。

```bash
python3 .github/scripts/build-pr-explain-local.py \
  --base origin/master --head HEAD --pr 123 \
  --head-branch feature/example --base-branch master \
  --out /tmp/seasoning-pr-123
# 自分で書いた解説を検査して含める場合は --explain /tmp/explain.json を追加
python3 -m http.server 8000 --directory /tmp/seasoning-pr-123
```

`http://localhost:8000/#map` を開き、`#story`・`#test`・`#impact`・`#primer` を切り替える。
`file://` では JSON を読めない。解説を省いた再生成は、出力先に以前の `explain.json` があれば消す。
検査に落ちた解説では既存の出力を更新しない。

### GitHub Pages への公開

初回にリポジトリの **Settings → Pages → Build and deployment → Source: GitHub Actions** を選ぶ。
`github-pages` environment のブランチ制限を設定している場合は、master と gh-pages からのデプロイを許可する。
未設定では生成と gh-pages への配置が成功しても公開は完了しない。成功を確認するのは `PR Explain Deploy` の実行結果と URL。
この機構を初めて入れる PR は、信頼する base に workflow とスクリプトが無いため自動公開されない。
導入後の PR 作成・push・reopen から自動生成する。

`PR Explain` は同じリポジトリの PR だけを対象とし、fork / Dependabot を除く。
`pull_request_target` で **base SHA のコードだけ**を checkout し、PR の head は Git object として fetch して読む。
head のスクリプト・hook・アプリ・テストを実行せず、型検査や iOS 実行も行わない。
古い PR イベントは現在の状態と head を照合して除く。変更ごとに `index.html` と `change-map.json` を
`gh-pages/pr-explain/pr-N/` へ配置し、専用の固定 PR コメントへ URL を載せる。
PR を閉じるとそのフォルダを削除し、reopen では地図の再生成後に解説を置き直す。

セッションが書いた解説は次のコマンドで検査して公開する。sha は push 済みのものを使う。

```bash
bash .github/scripts/pr-explain-pages.sh put-explain 123 /tmp/explain.json
```

`put-explain` は解説の形・参照・抜粋を検査し、追跡ブランチに無い sha や地図の無い公開先には置かない。
終了コード 3 は地図未配置または削除済み。開いた PR の `PR Explain` が成功しているか確かめて再試行する。
公開器は対象 PR の 3 ファイルだけを更新し、他の PR・他の公開コンテンツを保持する。push の競合は取り直して再試行する。

`PR Explain Deploy` は gh-pages の push、`PR Explain` 成功後の `workflow_run`、手動実行でサイト全体を公開する。
`GITHUB_TOKEN` での push は別の push workflow を起動しないため、`workflow_run` も必要。
デプロイはサイト共通の concurrency で直列化し、ロック取得後に最新 gh-pages を checkout する。
セッションによる gh-pages への push で workflow が起動しない認証を使う場合は、手動で deploy を実行する。
workflow で使う Actions は GitHub 公式だけを 40 桁 SHA で固定している。

### 検査するものと限界

地図は Models・Domain・Data・画面と起動・単体テスト・UI テスト・Xcode 設定・仕様・ハーネス・旧コードを分ける。
Swift Testing の `@Test` 表示名(無ければ関数名、複数行の arguments に対応)、XCTest の test 関数、
harness の Python unittest 宣言を前後で比較する。rename だけで宣言の追加・削除にせず、コメント・
文字列内の偽宣言は除く。宣言名の一覧はテストの実行件数や合格結果ではない。
マクロ展開、条件コンパイル、動的な表示名、型解決、Swift の呼び出し関係を網羅するものでもない。

Swift の `import` は同一モジュール内のファイル依存へ変換しない。テストの対象はファイル名から
一意に対応するときだけ添える。不明な関係は `messages` と `tests.targets` に根拠を確かめて書く。
自動依存は Python import と明示されたファイルパスに限り、文字列内のパスが説明か実行かまでは区別できない。
Markdown・バイナリ・長いファイルは依存解析から除く。地図にしか無い参照の誤りは表示で印を出すものもあり、
validator 成功だけで説明内容やリンク先の正しさを保証しない。

HTML は JSON の文字列を `textContent` で描き、HTML へ変換する危険な API と CSP の逸脱を検査する。
外部フォント・外部スクリプトは使わず、固定スクリプト 1 本をハッシュで許可する。
CSP は説明内容の正確性や、公開すべきでないデータが入っていないことまでは判定しない。

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s harness/tests -p test_pr_explain.py -v
```

既存の pre-push と `Agent harness` CI の unittest discover からも実行する。
Swift 宣言抽出と実 Git 差分、解説 validator、CSP の通る例・止める例、renderer core、
ローカル bare remote での配置・更新・削除・競合時の再試行・他 PR 保持を検証する。
Node.js が無い環境では renderer core だけを未実施として skip する。ブラウザ表示と iOS 実行は別の確認。

この機構は `DIO0550/design-composer` のコミット `c959c1f7d0` の pr-explain を参考に移植した。
元の MIT notice は [pr-explain-LICENSE](pr-explain-LICENSE) に保持する。
