---
name: pr-explain
description: "PR ごとの解説ページ(構造マップ・変更の経緯・テスト・振る舞い・技術の手引きの 5 画面)の材料になる解説 explain.json を書き、検査して gh-pages の pr-explain/pr-N/ へ置く。implementation-flow のフェーズ 7 で PR を出した直後と、振る舞いが変わる push の後に使用する。「PR の解説を書いて」「解説ページを更新して」といった依頼でも使用する。変更の地図(変更ファイル・依存・テスト名の増減・コミットと差分)とページの枠は Actions が置くので書かない。"
---

# PR の解説ページ

レビュアー(人間)が PR を開いたときに、**この PR がどこをどうつなぎ替えたか・どの順で何を変えたか・
テストが何を守っているか・使う人から見て何が変わったか・この PR を読むのに要る技術**を読めるようにする。
diff と Issue だけでは、長いセッションで何を使い、なぜその形にしたかが掴みにくいため。

## 5 画面と材料

ページは 1 枚で、`#map` / `#story` / `#test` / `#impact` / `#primer` で画面を切り替える。どの画面も、Actions が git の差分から
作る**変更の地図**(`change-map.json`)と、セッションが書く**解説**(`explain.json`)を合わせて組む。

| 画面 | 見るもの | 地図から | 解説から |
| --- | --- | --- | --- |
| 構造マップ(`#map`) | 左に変更ファイルと concepts の木。中に、それを層(または機能)ごとの組にまとめた箱の図と、やりとり(または依存)の線。組は抽象度で畳む・開く。右に概要(highlights・組ごとの変更・やりとり一覧)か、選んだ箱・線・やりとりの詳細(要するに・受け取るもの / 送り出すもの・使っている / 使われている)と、やりとりの流れ(シーケンス図) | `groups`・`dependencies` | `overview.highlights`・`features`・`layerRoles`・`concepts`・`messages`・`flows` |
| 変更の経緯(`#story`) | コミットを新しい順に並べた一覧と、ブランチ全体の流れ(題・要約・これまで / このブランチのあと・変更の順番・レビューポイント)、コミットごとの説明(なぜ・影響する操作・レビューで見るところ・振る舞いの前後)と差分・行への注釈 | `commits`(件名・本文・作者・日時・ファイルごとの差分) | `overview`・`commitStories`(操作の名前は `flows`、ファイルの呼び名は `concepts`) |
| テスト(`#test`) | suite ごとのテストの一覧と、構造マップと同じ組・箱の図の上で、テストが確かめている箱・やりとりと、その抜け。テストごとの前提 / 操作 / 期待・値の表・確かめているやりとり・この状況を確かめている(振る舞いの節)・テストコード・追加したコミット | `tests.added` / `tests.removed`・テスト名を調べたファイル(`tests.files`)・テストファイルの対象(`target`) | `suites`・`tests`(線は `messages`。無ければ依存) |
| 振る舞い(`#impact`) | 使う人から見て何が変わったかを、コードの名前を出さずに 1 画面で。左に節の目次(変わった節に印)、中に題・要約と、変わったこと(これまで / これから)・状況の表(行 × 列のマス。変わったマスに印。最初の変わったマスを選んだ状態で始まる)・増えた状況・変わらないこと(テストで守っているか)の節、右に今の節の根拠(確かめているテスト・無いテスト・仕組みのやりとり)。右の欄は本文のスクロールに合わせて今の節に切り替わり、幅が狭いと各節の中に畳んで出る | テストの追加 / 既存の判定(テスト画面と同じ)・やりとりの両端が図の箱か | `impact`(根拠は `tests`・`messages`) |
| 技術の手引き(`#primer`) | この PR を読むのに要る技術を、出てくる場所と一緒に。上にタブ(言語・フレームワーク / この PR の実装)、左に目次(REFERENCE の後に用語集)、中に節(要するに → 本文の段を書いた順)、右に今の節の出てくる場所(差分で見る。届かないときは、コミットを見る / ブランチ全体の流れを見る)・確かめているテスト / 無いテスト・構造マップで見る・関連・用語。点線の語に乗ると、右の欄の同じ語が光る。幅が狭いと各節に畳み(光るのは畳んだ欄の同じ語)、760px 以下ではタブの並びが上に残る | コミットの変更ファイル(差分で見るがファイル・行へ届くか)・テストの判定 | `primers`・`terms`(根拠は `tests`・`flows`) |

画面をまたいで移れる。変更の経緯の「影響する操作」を押すと構造マップでその流れを選んだ状態に、テストの
「追加したコミット」を押すと変更の経緯でそのコミットを開いた状態になる。振る舞いの「テストで見る」はテストの
画面でそのテストを選んだ状態に(観点の絞り込みは解く)、仕組みのチップは構造マップでそのやりとりを選んだ状態に
(表示範囲の絞り込みは外す。両端が図の箱でないやりとりは押せず「図に無い」)、テストの「この状況を確かめている」
は振る舞いのその節(表ならそのマスを選んだ状態)になる。技術の手引きでは、出てくる場所の「差分で見る」が変更の経緯の
そのコミットのそのファイル(カードを開いて送る)に、テストがテストの画面に、構造マップで見るが流れに、関連がもう一方の
タブの節になる。

- 行が光るのは、そのコミットが解説の sha までにそのファイルを最後に変えていて、あいだにマージコミットが無いときだけ
- そのコミットがそのファイルを変えていない・マージコミットなら、印を出してコミットの先頭を開く
- 地図に無い sha なら、印を出してブランチ全体の流れを開く

gh-pages の `pr-explain/pr-<番号>/` に置くのは次の 3 つだけ。

| ファイル | 置くもの | いつ |
| --- | --- | --- |
| `index.html` | ページの枠(`templates/index.html`) | Actions が push のたびに置き直す |
| `change-map.json` | 変更の地図 | Actions が push のたびに置き直す |
| `explain.json` | 解説 | セッションが `put-explain` で置く |

URL は `https://dio0550.github.io/seasoning-management-iOS/pr-explain/pr-<番号>/`。`PR Explain` が専用の固定コメントに載せるので、同じリンクのコメントを増やさない。**解説は PR ブランチにも master にも入れない**(master に溜まり、
Files changed にも混ざるため)。

Pages の公開には Settings → Pages → Source を **GitHub Actions** にする初回設定が必要。
この仕組みを初めて入れる PR は、信頼する base に workflow・スクリプトがまだ無いため自動公開しない。
導入後の PR / reopen で公開する。fork と Dependabot は公開対象外。
未設定でも、次のローカル生成で 5 画面を確認できる。

```bash
python3 .github/scripts/build-pr-explain-local.py --base origin/master --head HEAD --pr 123 \
  --head-branch feature/example --base-branch master --out /tmp/seasoning-pr-123
# 解説を書く場合は --explain /tmp/explain.json も渡す
python3 -m http.server 8000 --directory /tmp/seasoning-pr-123
# http://localhost:8000/#map (#story / #test / #impact / #primer)
```

生成先はリポジトリの外を指定する。`file://` では JSON を読み込めないので HTTP で開く。
地図は機械的な抽出であり、Swift のモジュール内のファイル依存は推測しない。
`@Test` の表示名(無ければ関数名)、XCTest の test 関数、harness の unittest 名を読む。
宣言名の増減はテスト実行の成否ではない。関係は解説の `messages`・`tests.targets` で補う。

## いつ書くか

- **PR を出した直後**(`implementation-flow` フェーズ 7)
- **振る舞いが変わる push をした後**。format・コメントだけの push では書き直さない(ページが
  「解説は ◯ 時点、以降 n コミットは解説なし」と出すので、読み手が判断できる)
- **PR を reopen した後**(閉じたときに Actions がフォルダごと消している)

## 手順

1. **材料を集める**
   - Issue: ゴール・計画・却下した案・計画から外れた点(`implementation-flow` が書いている)
   - 地図: ページと同じものを手元で出せる。コミットの sha・層の名前(`groups[].label`)・パスはここから取る

     ```bash
     python3 .github/scripts/build-pr-change-map.py --base origin/master --head HEAD --pr <番号> --head-branch "$(git branch --show-current)" --base-branch master
     ```

   - 検証エージェントの指摘: とくに `test-reviewer` の「壊して落ちた / 落ちなかった判断」はテストの材料
   - このセッションの記憶: Issue に書くほどではなかった判断・試して捨てた形
2. **見本 [`templates/explain.json`](templates/explain.json) をリポジトリの外の作業用ファイルへ写して
   書く**(`mktemp -d` など)。見本は `excerpt` 以外のすべてのキーと、Target の 5 つの kind・primers の
   2 つの kind・Passage の excerpt 以外の 8 つの kind を使っている。要らない任意のキーは消す
3. **下の「explain.json の形」と「書き方」で書く**
4. **事実の主張を確かめる。** 解説は「この関数は◯◯を返す」「この操作で□□になる」の集まりなので、
   対象 sha のソース・テスト・差分を実際に読み、各主張と対応する根拠を確認する。
   テストの宣言とテスト成功は別に記す。Note の行番号は、そのコミット時点のファイルを開いて合わせる
5. **置く**

   ```bash
   bash .github/scripts/pr-explain-pages.sh put-explain <PR 番号> <書いた explain.json>
   ```

   - push の前に `build-pr-explain.py` が検査し、テストの抜粋と、primers の段の抜粋(`excerpt`)に中身(`text`)と、埋め込み
     (script / style 要素・ヒアドキュメント)の中から始まるものには開いた行(`openingLine`)を足す(拡張子と規則は
     `.github/scripts/lib/embedded_regions.py`)。落ちたら報告を読んで直す(報告の分類は `build-pr-explain.py` の冒頭)
   - 解説の `sha` は push してから置く。リモートの追跡ブランチに無い sha の解説は置かない
   - 終了コードの意味は `pr-explain-pages.sh` の冒頭。**3** なら `PR Explain` の run の完了を待って
     からやり直す。閉じた PR には置かない
   - 解説の `sha` が地図の head と違えば、置いたうえで標準エラーに知らせる。push の直後で run が
     終わっていないだけなら置き直さなくてよい(run が終われば地図の head と揃う)
   - **gh-pages へ push してよいのは、このスクリプトで `pr-explain/pr-<番号>/` へ置くときだけ。**
     他のフォルダ・他のブランチは触らない
6. **URL をユーザーに伝える**

## explain.json の形

**共通の規則**

- 文字列は空にしない。説明文(`title`・`lead`・`text`・`why`・`given` / `when` / `then` など。`impact` の中は下の規則)の中の
  `` `…` `` は、ページがコードとして描く。primers の `label`・`gist`・text と注意メモの段の `text`・引数の `text`・
  出てくる場所の `text`・terms の `text` も同じ。名前(`name`・`label`)と `code` は書いたまま出す(例外は primers の
  `label` で、`` `…` `` をコードとして描く。declaration の `code` は書いたまま出す)。HTML は書いても文字のまま出る
- **用語の印 `[[表示|用語の id]]`** を書けるのは、primers の `gist`・text と注意メモの段の `text`・引数の `text` だけ。
  印の表示には `` `…` `` を書ける。`` `…` `` の中に印の形は書けない。`` `…` `` の外に、印でない `[[` / `]]` は書けない。
  対になった `` `…` `` の中の、印でない `[[` / `]]` は書ける(閉じていない `` ` `` の後ろはコードにならない)。
  理由は `build-pr-explain.py` の冒頭
- **見出しは概念の名前(docs の語彙)で書く。** 見出しは図・一覧の見出しになる文字列で、検査の対象は
  `build-pr-explain.py` の `Heading` を使うキー(名前のうち `tests[].name` を除いたものと、highlights の
  `title`。例外は `impact` の中の名前(`label`)で、見出しではなく下の `UserText`。primers の `label`・terms の `label`・
  引数の `name` は技術の名前なので `Text`(識別子を書いてよい))。小文字と大文字の継ぎ目が
  ある複合語(docs に出る語を除く)があれば落ちる。大文字だけの略語(SwiftUI・SwiftData)はこのリポジトリの語彙なので
  書いてよい。1 語の識別子(`Result`・`Item`)・ファイル名・snake_case は検査しないが、見出しには書かない。
  理由は `build-pr-explain.py` の冒頭
- **振る舞い(`impact`)の文字列は、すべて使う人の言葉で書き、コードの名前(関数・型・ファイル名・snake_case も)を
  書かない。** `` `…` `` で囲んで書くこともできない(振る舞いの画面は文を書いたまま出す)。検査(`UserText`)が
  捕まえるのは、見出しと同じ継ぎ目のある複合語(docs に出る語を除く)と `` ` `` だけで、1 語の識別子・ファイル名・
  snake_case は書く側で避ける。検査が何を守るか(根拠に出るテスト名・やりとりの名前は対象外)は `build-pr-explain.py` の冒頭
- id は `^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$`、sha は小文字 40 桁
- 知らないキーと重複したキーは、入れ子を含めて落ちる
- 任意の配列は、省けば `[]` と同じ

**トップ**

| キー | 必須 | 意味 |
| --- | --- | --- |
| `version` | 必須 | `1` |
| `pr` | 必須 | 公開先の PR 番号 |
| `sha` | 必須 | 解説を書いた時点の head(`git rev-parse HEAD`。push 済みのもの)。抜粋はここから読む |
| `issue` | 任意 | 材料の Issue 番号 |
| `overview` | 必須 | Overview |
| `features` | 任意 | Feature[]。空ならページは「機能」でまとめられない(層だけ) |
| `layerRoles` / `concepts` / `messages` / `flows` / `commitStories` / `suites` / `tests` | 任意 | 下の型の配列 |
| `impact` | 任意 | Impact。無ければ振る舞いの画面は「書かれていない」と出す |
| `primers` | 任意 | Primer[]。無いか空なら、技術の手引きは「書かれていない」と出す |
| `terms` | 任意 | Term[] |

**型**(`?` は任意)

| 型 | キー |
| --- | --- |
| Overview | `title` `lead` `before: Behavior[]`(0 件でよい)`after: Behavior[]`(1 件以上)`highlights?: Highlight[]` |
| Behavior | `text` `message?`(messages の id) |
| Highlight | `title` `text` `go: Target`(押したときに移る先) |
| Target | `{kind: "feature", id}` / `{kind: "layer", layer}`(地図の `groups[].label` と同じ綴り)/ `{kind: "file", path}` / `{kind: "message", id}` / `{kind: "flow", id}`。kind ごとのキーが欠けるのも、他の kind のキーが混ざるのも不可 |
| Feature | `id` `label` `role` |
| LayerRole | `layer`(一意。地図の `groups[].label`)`role` |
| Concept | `path`(一意)`name` `role` `feature?`(features の id)`change?` `graph?`(既定 true) |
| Message | `id` `from` `to`(concepts の path)`kind`: `cmd` \| `qry` \| `evt` `name` `code` `via`: `call` \| `http` \| `state` \| `log` \| `exec` \| `file` `payload?` `returns?` `status?`: `added` \| `changed` \| `removed`(省けば前からあって変えていない) |
| Flow | `id` `label` `steps[]`(messages の id。1 件以上) |
| CommitStory | `sha`(一意)`phase`: `prep` \| `core` \| `hard` \| `revise` \| `fin` `role` `why` `flows?`(flows の id)`review?: string[]` `before?: Behavior[]` `after?: Behavior[]` `notes?: Note[]` |
| Note | `path` `side?`: `new` \| `old`(既定 new)`start`(1 以上)`end`(start 以上)`text`。行番号はそのコミット時点 |
| Suite | `id` `label` `file` |
| Test | `id` `suite`(suites の id)`name` `techniques[]`: `boundary` \| `equivalence` \| `error` \| `state` \| `regression` \| `idempotence` \| `type`(1 件以上・重複なし)`why` `given` `when` `then` `todo?: true` `commit?`(sha)`excerpt?: Excerpt` `values?: Values` `targets?`(concepts の path)`covers?`(messages の id) |
| Excerpt | tests と primers の段の抜粋。`path` `start` `end`(80 行まで)`emphasis?: LineRange[]`(強調する行。ファイルの行番号で、start〜end の中)。`text` は検査が足す出力だけのキーで、入力に書くと落ちる。`openingLine` も検査が足す出力だけのキーで、入力に書くと落ちる |
| Values | `columns[]`(1 件以上)`rows: [{cells: string[], boundary?}]`(cells は列と同数) |
| Impact | `title` `lead` `changed?: ImpactChange` `tables?: SituationTable[]` `added?: AddedSituation[]` `kept?: KeptLine[]` |
| ImpactChange | `before: ImpactLine[]`(0 件でよい)`after: ImpactLine[]`(1 件以上)`text?`。前後の文の並びがまったく同じなら落ちる(一部の行が同じなのはよい) |
| ImpactLine | `text` `message?`(messages の id。仕組みのチップになる) |
| SituationTable | `label` `gist?`(要するに)`text?` `rowHeads: SituationRowHead[]`(1 件以上)`columnHeads: SituationColumnHead[]`(1 件以上)`outcomes: SituationOutcome[]`。マスは行の見出し × 列の見出しの組み合わせをちょうど 1 つずつ(欠け・重複・見出しに無い id は落ちる) |
| SituationRowHead | `id`(行の見出しの中で一意)`label` `note?`(Note(行への注釈)とは別の 1 行の注。マスの状況に「行 · 列(注)」と添える) |
| SituationColumnHead | `id`(列の見出しの中で一意。行の見出しと同じ id は書ける)`label` |
| SituationOutcome | `rowHead` `columnHead`(見出しの id)`result` `was?`(これまで。書いたマスが「変わった」になる。`result` と同じなら落ちる)`situation?`(マスの状況の文。書かなければ見出しから「行 · 列(行の注)」と組む)`note?`(Note(行への注釈)とは別の、マスへの 1 行の注)`tests?`(tests の id。重複なし) |
| AddedSituation | `label` `before: ImpactLine[]`(0 件でよい)`after: ImpactLine[]`(1 件以上)`text?` `tests?`(tests の id。重複なし)。前後の規則は ImpactChange と同じ |
| KeptLine | `text` `tests?`(tests の id。重複なし) |
| Primer | `id` `kind`: `language` \| `codebase` `category` `label` `gist`(印を書ける)`passages?: Passage[]`(書いた順に描く)`occurrences: Occurrence[]`(1 件以上)`seeAlso?`(primers の id。重複なし。kind をまたいでよい)。codebase だけ `status?`: `added` \| `changed` `tests?` / `flows?`(id。重複なし) |
| Passage | kind ごとに `text {text}` / `declaration {code}` / `parameters {parameters: Parameter[] 1 件以上}` / `excerpt {excerpt: Excerpt}` / `caution` \| `memo` \| `rule` \| `spec` \| `history` `{text}` |
| Parameter | `name` `type` `text`(印を書ける)`note?` |
| Occurrence | `path` `lineRange?: LineRange`(解説の sha の行番号)`text` `shas?`(sha。重複なし。地図と照合しない) |
| LineRange | `start`(1 以上)`end`(start 以上) |
| Term | `id` `label`(一意)`text`。どれかの印から指す |

id・sha・path・layer は一覧の中で一意にする(features / messages / flows / suites / tests の id、
commitStories の sha、concepts の path、layerRoles の layer、primers の id(kind をまたいで)、terms の id と label)。
todo のテストは commit も excerpt も持たない。

**解説の中の参照**は満たさなければ置けない(message の from / to、flow の steps、commitStory の flows、
Behavior の message、test の suite / covers / targets、concept の feature、Target の feature / message /
flow、ImpactLine の message、SituationOutcome・AddedSituation・KeptLine の tests、primers の seeAlso / tests / flows、
用語の印 → terms。terms はどれかの印から指す)。**地図を指す参照**(commitStory の sha・Note のパスと行・Target の
layer / file・LayerRole の layer・concept のパス・出てくる場所の `path`・`lineRange`・`shas`)は検査せず、外れたものは
ページが「地図に無い」と出す(理由は `build-pr-explain.py` の冒頭)。

## 書き方

読み手は、このリポジトリの規約は知っているが、**この PR で使った技術やこのセッションの経緯は
知らない人**とする。専門用語は出たその場で一言で説明する。ただし `primers` の中だけは、技術は `primers` に、用語は
`terms` に 1 回だけ書き、本文の語に印を付けて指す(印を書けるキーでは、地の文に名前だけを出す)。印はほかのキー
(`commitStories`・`tests`・`impact` など)では読まれず、`[[…|…]]` の文字のまま出る。

| キー | 書くこと | 書かないこと |
| --- | --- | --- |
| `overview` | `title` は PR の題、`lead` は何ができるようになったかの 1〜2 文。`before` / `after` は操作・状況ごとの振る舞いを 1 つ 1 行で(空・エラー・境界の状況も)。関わるやりとりがあれば `message` で指す。読み手はレビュアーで、`` `…` `` で実装の名前を指してよい | 実装の手順 |
| `impact` | 使う人(アプリを操作する人・ハーネスなら使うセッション)から見て変わったことを、操作と画面の言葉だけで。`changed` は変わったことの前後、`tables` は結果が 2 つの軸(例: タブがあるか × 開く操作の進み具合)で決まるときの行 × 列の表(変わったマスにだけ `was`)、`added` はこの PR で初めて起きうるようになった状況、`kept` は巻き込まれそうで変わらないこと。根拠は `tests` で指す。`overview` が「何を変えたか」をレビュアーに向けて書くのに対し、ここは「使う人に何が起きるか」を書く | コードの名前(共通の規則) |
| `overview.highlights` | 特に見てほしい箇所(自信のない判断・未決のまま入れたもの・目で見ないと分からない表示)と、押したときに図のどこへ移るか(`go`) | 「全体を見てください」 |
| `features` / `layerRoles` | 機能・層がこの PR で担う役割を 1 文。`layerRoles` の `layer` の綴りは地図の `groups[].label` に揃える | |
| `concepts` | 箱にしたいファイルと、その短い名前(`name`。概念の名前(docs の語彙)で、図の表示名になる)・役割・何を変えたか(`change`)。変更していないファイルも名指しすると箱になる。図に出さず木にだけ出すなら `graph: false` | 変更ファイルの列挙だけ(箱は地図からも出る) |
| `messages` / `flows` | 箱どうしのやりとり。`kind` は変える(`cmd`)/ 問い合わせる(`qry`)/ 知らせる(`evt`)、`code` は実際の呼び出しの綴り。このブランチで足した・変えた・消したものは `status` を `added` / `changed` / `removed` にする(テストの抜けは `added` と `changed` で数える)。`flows` は操作・イベントごとのやりとりの順で、2〜4 本 | 1 つの関数の中の手順 |
| `commitStories` | コミットごとに、`role`(何をするコミットか 1 行)・`why`(なぜこの順でこうしたか)・`review`(レビューで見てほしい点を 1 点 1 文)・振る舞いの前後・行への注釈(`notes`)。`phase` は下ごしらえ(`prep`)/ 本体(`core`)/ 安定化(`hard`)/ 指摘の反映(`revise`)/ 仕上げ(`fin`) | 件名・本文の写し(地図から出る) |
| `suites` / `tests` | テストごとに、守る振る舞い(`why`)・前提 / 操作 / 期待・使った技法・境界の値の表(`values`)・確かめているやりとり(`covers`)と箱(`targets`)。テストコードは `excerpt` で範囲を指す | テストコードの写し |
| `primers` | この PR を読むのに要る技術。language は差分に出てくる順、codebase は全体の流れから部品へ。`occurrences` は 1 件以上で、行は解説の `sha` の時点、`shas` はその箇所を足した・変えたコミット。PR ごとに書く(共有の仕組みは無い) | コード例の写し(`excerpt` で実物の行範囲を指す) |
| `terms` | 1 語 1 回。意味は 1〜2 文 | |

- **説明文でも、識別子を地の文の主語にしない。** 実装の名前とファイル名を指すときは `` `…` `` で囲む
- **`review` の文は、確認の印の鍵になる。** 読み手のブラウザは「コミットの sha + 文」で確認済みを
  覚えるので、文を書き直すとその点の印は外れる(別の点へ移らない)
- **`tests[].name` はテスト名そのままで書く。** ページは、地図がテスト名を調べたファイル(`tests.files`。
  Swift Testing / XCTest / harness のテストファイル)なら `suite.file` と `name` を `tests.added` と突き合わせて「追加 / 既存」を
  出す。綴りを変えると既存のテストに見える。それ以外のファイルのテストは、このブランチで足したファイルなら
  「追加」、ほかは「判定なし」
- 未実装のテスト(守れていない振る舞い)は `todo: true` で書く。ページはテストの画面で破線で、振る舞いの画面の
  根拠で「無いテスト」として出す(本文には件数だけを出す)。技術の手引きの「この PR の実装」の節の右の欄でも「無いテスト」として出す
- Note の `start` / `end` は、そのコミットで `side` の側(既定は変更後)のファイルの行番号。差分の
  hunk に入らない行への注釈は「差分に出ていない行への注釈」として別に出る

## 解説が無いとき・古いとき

ページは地図だけでも 5 画面を出す(振る舞いと技術の手引きは解説が要るので「解説なし」とだけ出す)。解説の状態は上の帯で知らせる。

| 状態 | ページの出方 |
| --- | --- |
| 解説が無い | 地図だけで組む。まとめ方は層、表示名はファイル名、構造マップの線は依存だけ(やりとりの流れは出ない)、テストは地図の追加・削除と対象 |
| 解説が読めない(JSON でない・`version` が 1 でない・`pr` が違う・形が想定外(型の違い・必須の欠け)) | 「解説なし」とその理由。`impact`・`primers`・`terms`・`tests[].excerpt.emphasis` の型が想定外か、`primers`・`terms` の必須の文かオブジェクト(kind ごとに必須のものを含む。抜粋の段の `excerpt` など)が欠けていれば、崩れた道筋(`impact.tables[].outcomes` など。2 か所以上なら外側)を出す |
| 解説に `impact` が無い | 振る舞いの画面に「書かれていない」と出す。ほかの画面には影響しない |
| 解説に `primers` が無い(空も) | 技術の手引きに「書かれていない」と出す。ほかの画面には影響しない |
| 解説の sha が地図の head より前 | 「解説は ◯ 時点、以降 n コミットは解説なし」。以降のコミットには「解説なし」の札 |
| 解説の sha が地図のコミットに無い | 「解説の sha が地図に無い」(force push などで履歴が変わったとき) |
| commitStories の sha が地図に無い | 「地図に無い解説 n 件」。別の一覧に出す |
| 地図の version が 2 でない | 画面を組まず、「変更の地図を読めません」と version を出す |

## 参照ファイル

| ファイル | 内容 |
| --- | --- |
| [`templates/index.html`](templates/index.html) | ページの枠(CSS・固定スクリプト・CSP)。固定スクリプトを変えたら CSP の `sha256-` も直す(`check-pr-explain-template.py` が突き合わせる) |
| [`templates/explain.json`](templates/explain.json) | `excerpt` 以外のすべてのキーと、Target の 5 つの kind・primers の 2 つの kind・Passage の excerpt 以外の 8 つの kind を使う解説の見本 |
| `.github/scripts/build-pr-explain.py` | 解説の検査と、抜粋の中身の書き足し |
| `.github/scripts/lib/embedded_regions.py` | 抜粋・差分の hunk の始まりの行で効いている埋め込み(script / style 要素・ヒアドキュメント)を開いた行。検査と地図が使う |
| `.github/scripts/check-pr-explain-template.py` | 枠の CSP と、固定スクリプトが HTML として解釈させる API を使っていないかの検査 |
| `.github/scripts/pr-explain-pages.sh` | gh-pages の `pr-explain/pr-<番号>/` の書き換え(`put-explain` / `put-map` / `remove`) |
| `.github/scripts/build-pr-change-map.py` | 変更の地図(Actions が呼ぶ) |
| `.github/workflows/pr-explain.yml` | 枠と地図の配置と、PR が閉じたときの削除 |
