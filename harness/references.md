# 初期ルールの参照元

## 構成

[design-composer の AGENTS.md](https://github.com/DIO0550/design-composer/blob/1bfb70e8500e1b62738d44b224cfd954a688fb00/AGENTS.md)
と `.claude/` / `harness/` の分担を参考にした。
TypeScript / React の制約、既存の大量の判例、発火集計の仕組みはそのまま移植していない。

## dev-knowledge の Swift ナレッジ

確認したリビジョン: `c3b257b8c6c98be1fb503fa7f2177f3f9502dfc6`。

| 記事 | このリポジトリでの判断 |
| --- | --- |
| [caseless enum + static と DDD](https://github.com/DIO0550/dev-knowledge/blob/c3b257b8c6c98be1fb503fa7f2177f3f9502dfc6/dev-knowledge/docs/swift/design/caseless-enum-static-and-ddd.md) | 振る舞いの所有者を先に考える。所有者のない純粋関数・定数では static 名前空間を使える |
| [@discardableResult とは何か](https://github.com/DIO0550/dev-knowledge/blob/c3b257b8c6c98be1fb503fa7f2177f3f9502dfc6/dev-knowledge/docs/swift/discardableResultとは何か.md) | 戻り値を捨てても正当な API に限定し、検証・保存結果の見落としを隠さない |

記事内の例を本番の規約として丸ごと取り込まず、強制 unwrap や一行の早期 return はこのプロジェクトの書き方へ合わせる。
static の副作用の差し替えにくさと、依存のない純粋関数のテスト容易性は区別する。

## Swift とプロジェクト固有の判断

[Swift の Attributes](https://github.com/swiftlang/swift-book/blob/main/TSPL.docc/ReferenceManual/Attributes.md) で
`discardableResult` と result builder の制約を確認した。ViewBuilder の表示分岐を早期 return へ書き換えない。

SwiftUI の状態所有と SwiftData の保存境界のルールは、このアプリの初期方針として追加した。
既存の `Product` は永続化の属性を持ち、業務入力の検証は保存操作側へ置く設計である。
caseless enum の記事を理由にすべての入力検証を `@Model` の initializer へ移すことはしない。
根拠は [データモデル仕様](../docs/seasoning-management/data-model-spec.md) と
[同期・移行仕様](../docs/seasoning-management/sync-migration-spec.md)。

導入時の新アプリには商品モデルと状態 enum があるが、CloudKit コンテナ識別子は未設定で、
`cloudKitDatabase: .none`。スキーマの将来互換と同期の稼働確認を分ける。
