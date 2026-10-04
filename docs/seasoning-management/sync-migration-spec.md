# iCloud 同期・既存データ移行仕様（端末側の処理）

> [概要](./index.md) / [データモデル](./data-model-spec.md)

## 同期の目的と対象

端末内の SwiftData を編集の起点にして、同じ iCloud アカウントを使う端末間で商品、商品画像、個体、使い切り履歴、削除を同期する。独自サーバーやアプリ専用アカウントは設けない。SwiftData の CloudKit 同期に必要な iCloud・Background Modes の設定と、同期対応スキーマの検証を行う。現在の entitlements は CloudKit コンテナ識別子が空であり、同期は未検証である。

商品名・賞味期限の[OCR](./ocr-spec.md)は端末上で実行する。読み取りに使っただけの画像と未確定候補は保存・同期しない。利用者が確定して保存した商品名・賞味期限だけを通常のデータとして同期する。商品画像として明示的に選んだ画像は従来どおり同期対象とする。

| 状態 | 利用者に見える振る舞い |
|:--|:--|
| 接続中 | ローカルで登録・編集・削除でき、変更を同期する。 |
| オフライン・一時的な同期失敗 | ローカルの操作を継続し、変更を保留して接続後に再試行する。同期中・保留・失敗を区別して表示する。 |
| iCloud 未サインイン・利用不可 | ローカルの操作を継続できる。同期できない理由と、再接続時の扱いを示す。 |
| 別端末から変更 | ローカルの一覧・詳細へ反映する。同じ ID の二重表示を作らない。 |

ローカル保存成功とクラウド反映完了は別の状態として扱う。同期失敗をローカル保存失敗として見せない。

## Product / Item の CloudKit スキーマ検証（Issue #21）

2026-10-03、#20 のマージコミット `05335d09353aae72ea05ac919cb28d73f12e8737` を調査した。マージ先は `issue-19-item-status` であり、同日時点の `master` には Product / 個体 Item は入っていない。本節はその実装ブランチのモデルを対象にする。

**ソースの条件確認と検証テストの追加まで実施。ローカルテスト実行・CloudKit コンテナ起動・実機同期は未実施であり、互換性が実証済みとは判定しない。** この作業環境は Linux で、Swift・Xcode・署名環境・iOS 実機を利用できない。

### ソースから確認した内容

| 観点 | 現在のモデル | 実行時に確認する内容 |
|:--|:--|:--|
| 関係 | `Product.items: [Item]?`、`Item.product: Product?` | 生成された両関係が Optional である。 |
| 逆関係 | `Item.product` に `inverse: \Product.items` を指定 | 両方向の逆関係が一致し、参照先が同じスキーマに存在する。 |
| 必須属性のデフォルト | Product の `id`・`name`・`type`・`updatedAt`、Item の `id`・`statusRawValue`・`updatedAt` に宣言時の値がある。ほかは Optional | 生成された永続化属性に Optional またはデフォルト値がある。イニシャライザーの引数デフォルトだけでは代用しない。 |
| 一意制約 | `.unique` / `#Unique` の指定なし | 生成されたエンティティの一意制約が空である。ID 重複の業務検査は別途行う。 |
| 削除規則 | 双方 `.nullify` | 生成された規則も `.nullifyDeleteRule`。個体がある商品の削除制限はアプリ層の後続実装。 |
| 画像 | `@Attribute(.externalStorage) var image: Data?` | Optional の Binary 属性で外部保存が許可される。画像バイト列と個体関係を再オープン後に復元できる。 |
| モデル構成 | Product / Item を同じ `Schema` に登録 | 両モデルを含むディスク上のコンテナが起動する。 |

現時点でソース上のスキーマ修正は特定していない。これは「修正不要」の実証ではない。生成モデル・CloudKit 起動の検証が失敗した場合は、属性名・エラー全文・OS / Xcode・対象コミットを記録し、モデル修正を別の小さな変更として扱う。

### ローカル検証

[`CloudSchemaTests.swift`](../../src/SeasoningManager/SeasoningManagerTests/CloudSchemaTests.swift) に次のテストを追加した。モデルのコピーは作らず、実際の `Product.self` / `Item.self` から `NSManagedObjectModel.makeManagedObjectModel(for:)` で生成したメタデータを調べる。

- `generatedAttributesHaveDefaultsOrAreOptionalAndHaveNoUniqueConstraints`：全エンティティの一意制約、属性の Optional / デフォルト、非対応の Undefined / Object ID 属性の不在。
- `generatedRelationshipsAreOptionalWithNullifyAndReciprocalInverses`：Optional、削除規則、参照先、逆関係、多重度。
- `imageIsOptionalBinaryWithExternalStorage`：画像の型、Optional、外部保存の許可。
- `localStorePreservesImageBytesAndSharedProductAfterReopening`：一時 SQLite ストアへ商品・2個体・256 KiB のバイナリを保存し、コンテナの再生成後に内容と関係を照合。

通常の実行では `cloudKitDatabase: .none` を指定し、CloudKit テストはスキップする。バイナリテストは画像デコード・画像サイズ上限・実際の外部ファイル配置・CloudKit アセット転送を保証しない。

対応する Xcode で `src/SeasoningManager/SeasoningManager.xcodeproj` を開き、SeasoningManager のスキームの Test に SeasoningManagerTests を登録して実行する。この土台ブランチには #80 の共有スキームが未反映なので、未登録なら検証用のローカルスキームに追加する。#80 の取り込み後は共有スキームを利用できる。

### CloudKit の起動確認と実機検証

現在の entitlements のコンテナID配列は空で、Team は未設定。`Info.plist` の `UIBackgroundModes` には `remote-notification` があり、アプリの通常のコンテナ設定は `.none` である。

#36 は #21 を前提にしているが、#21 の実機検証には署名・コンテナ設定が必要になる。検証用の作業コピーで下記の一時設定を行い、結果を本節へ追記する。本番アプリの設定変更は #36、通常起動への同期接続は #71 で扱う。検証用設定を用意できない間は、#21 の実機条件を未完了として残す。

1. 検証専用の Development CloudKit コンテナとテスト用 iCloud アカウントを用意する。Xcode の Signing & Capabilities で有効な Team・CloudKit コンテナ・Push Notifications・Background Modes の Remote notifications を整合させる。Debug の署名済みアプリが Development 環境を使うことを確認する。
2. スキームの Test で環境変数 `SEASONING_RUN_CLOUD_SCHEMA_TEST=1` と `SEASONING_CLOUDKIT_CONTAINER_ID=<実際に設定したコンテナID>` を渡す。対応する実機を選び、`cloudKitConfiguredContainerCanOpen` を実行する。テスト対象は実 Product / Item、一時ディスクストア、`.private(identifier)` である。ID が欠ける場合や起動で例外が発生した場合は失敗させ、`.none` にはフォールバックしない。このテストは Debug のみ有効。
3. このテストの成功はコンテナ生成とローカル fetch の成功を示す。非同期の CloudKit セットアップ・認証・転送完了は保証しない。スキップを成功として扱わず、実機ログのセットアップ結果とエラーも別に記録する。
4. 開発スキーマの初期化は [Apple の手順](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices) に従い、検証用コピーで同じ Product / Item から生成したモデルを使う。Core Data のストアを同期ロードし、エラーを確認してから `initializeCloudKitSchema()` を実行し、ストアをアンロードしてから SwiftData を起動する。これはサーバーの開発スキーマへ書き込む操作であり、今回追加したテストでは自動実行しない。
5. CloudKit Console の Development 環境で両モデルのレコード型・属性・関係を確認する。空のコンテナの起動だけで画像の転送成功を判断しない。別の検証用ストアで商品1件・個体2件・実画像を保存し、別端末の新規ストアへ同じ ID・関係・画像が到着することを確認する。画像は元の `Data` と読み戻した `Data` の一致で確認する。このための通常アプリの同期接続や試験用投入処理は今回の2ファイル変更には含めていない。
6. 同期ログの失敗、参照の到着順、画像の更新・削除も記録する。競合・アカウント切替・オフライン復帰の包括的検証は #25・#78 で扱う。

### 検証結果と残作業

| 検証 | 2026-10-03 の結果 |
|:--|:--|
| 実モデル・設定のソース確認 | 実施済み。上記の宣言と未設定項目を確認。 |
| 生成メタデータのテスト3件 | 追加済み、実行未実施。 |
| SQLite 再オープン・画像バイト列のテスト1件 | 追加済み、実行未実施。 |
| CloudKit 設定のコンテナ起動テスト1件 | 追加済み、実行未実施。通常実行ではスキップ。 |
| 実機のセットアップ・開発スキーマ初期化・別端末への画像転送 | 未実施。署名、開発用コンテナ、アカウント、実機が必要。 |
| 必要なモデル修正 | 未確定。ソース確認では修正を特定せず、実行結果待ち。 |

追試時は対象コミット、Xcode / OS、実行テスト名、成功・失敗・スキップ件数、Development コンテナID、セットアップ結果、別端末での商品・個体件数と画像照合結果を追記する。個人の Apple ID や署名情報は記録しない。すべての完了条件を満たすまで #21 をクローズしない。

参照：[Apple: Syncing model data across a person’s devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)、[Apple: Creating a Core Data Model for CloudKit](https://developer.apple.com/documentation/coredata/creating-a-core-data-model-for-cloudkit)。

## 競合と削除

CloudKit 同期ではリレーションの Optional 化が必要で、永続化層の一意制約と `.deny` 削除規則に依存できない。商品の削除制限や個体の参照整合性はアプリ層で検証し、別端末からの同期後にも再検査する。

- 同じ商品または個体を複数端末で変更した場合、そのレコード単位で更新日時の新しい変更を採用することを初版の利用者向けルールとする。競合が発生しても古い内容に黙って戻さない。
- 時刻ずれや同期順序がこのルールを壊さないようにする具体的な方式は実装設計と複数端末テストで確定する。単純な端末時計比較を実装要件とはしない。
- 削除と編集が競合する場合は削除を優先し、削除済み ID を再生成しない。削除の伝播中にも参照切れの個体を表示しない。
- 商品削除の「個体0件」の判定は、同期で別端末から個体が到着する場合も整合性を保つ。競合する場合は商品削除を確定せず、利用者へ説明する。

## 旧 Core Data アプリの保存データ移行

`old/src/SeasoningManager` の旧アプリが保存した `Seasoning` を、新しい SwiftUI / SwiftData アプリへの更新後も失わない。既存アプリとして更新できる識別子・署名・保存領域を維持し、旧 Core Data モデルで旧ストアを読み取ってから SwiftData の新ストアへ変換する。SwiftData の新モデルで旧ストアを直接開けると仮定しない。新しいXcodeひな形の `Item(timestamp)` は移行先ではない。

| 旧モデルの値 | 移行先とルール |
|:--|:--|
| 1件の `Seasoning` | 1件の Product と1件の Item に変換する。同名でも勝手に統合しない。 |
| `identifier` | 有効なら Item ID に引き継ぐ。欠ける・重複する場合は新しい一意な ID を割り当てる。 |
| `name`, `type`, `image` | Product へ引き継ぐ。名前・種類が欠損したレコードは元の値を端末内に保全して「修正が必要」に分け、修正後に Product / Item として取り込む。欠損の仮値を実データとして同期しない。 |
| `expirationDate` | Item へ引き継ぐ。 |
| `openingDate` あり | 日付を保持し、状態を `inUse` とする。 |
| `openingDate` なし | 状態を `unopened` とする。 |

既存データの移行は一度だけ、途中で失敗した場合は再実行しても個体を重複させない。移行前の保存データを破壊せず、移行完了を確認してから SwiftData の同期を開始する。新旧ストアの場所を分け、旧ストアを新しいひな形のコンテナで上書きしない。移行直後に商品が1件ずつ分かれていてもよい。商品統合は初版の自動処理に含めない。

移行テストでは旧版で保存した実データを用い、新版を上書きインストールして件数・画像・日付を確認する。新規インストールだけの動作確認では移行完了とみなさない。

修正が必要なレコードの件数と元の値を利用者に示し、名前・種類を補って取り込めるようにする。この処理が終わるまで、該当レコードだけを同期対象から外し、ほかの正常なデータの利用は妨げない。

`old/src/old` は別の試作コードであり、その保存領域の存在や旧 `SeasoningManager` アプリへの継承は確認できていない。この別試作アプリからの自動移行は別途調査する。

### 更新インストールの前提調査（Issue #15）

2026-10-01、`master` の `832ea0286b30bce5a116210c2a7e6c3371a78371` を調査した。以下はリポジトリの設定とコードからの確認結果であり、配布済みバイナリの署名や実機での更新成功を確認したものではない。**Bundle ID は一致するが、新アプリの Team は未設定で、更新可否は未検証**である。

| 項目 | 旧 UIKit アプリ | 新 SwiftUI アプリ | 判定 |
|:--|:--|:--|:--|
| 対象 | `old/src/SeasoningManager` | `src/SeasoningManager` | `old/src/old` の試作は対象外。 |
| App の Bundle ID（Debug / Release） | `DIO0550.SeasoningManager` | `DIO0550.SeasoningManager` | 設定値は一致。 |
| 署名方式（Debug / Release） | `CODE_SIGN_STYLE = Automatic` | `CODE_SIGN_STYLE = Automatic` | 自動署名の指定だけでは更新可能とは判断しない。 |
| Team（Debug / Release） | `DEVELOPMENT_TEAM = RMVJT9K8W3` | `DEVELOPMENT_TEAM` の指定なし | 旧配布物の Team を確認して新アプリに設定する必要がある。 |
| 署名済み `application-identifier` / 証明書 / Profile | リポジトリ内に確認資料なし | リポジトリ内に確認資料なし | 実物を比較する。App ID Prefix を Team ID と同一と推定しない。 |
| バージョン / ビルド | `Info.plist` で `1.0` / `1` | `MARKETING_VERSION = 1.0` / `CURRENT_PROJECT_VERSION = 1` | 配布済みの値は不明。配布経路の更新要件に合わせて更新する。 |
| 最低 iOS | App ターゲットで `12.0`（プロジェクトは `13.0`） | `27.0` | 新版に対応する OS・端末で更新検証する。旧版の実際の対応範囲は配布物で確認する。 |
| App Groups | 共有コンテナの設定・参照なし | entitlements に App Groups なし | 別アプリの保存領域を共有する仕組みはない。 |

根拠ファイル：

- [旧 project.pbxproj](../../old/src/SeasoningManager/SeasoningManager.xcodeproj/project.pbxproj)、[旧 Info.plist](../../old/src/SeasoningManager/SeasoningManager/Info.plist)
- [新 project.pbxproj](../../src/SeasoningManager/SeasoningManager.xcodeproj/project.pbxproj)、[新 entitlements](../../src/SeasoningManager/SeasoningManager/SeasoningManager.entitlements)
- [旧 AppDelegate.swift](../../old/src/SeasoningManager/SeasoningManager/AppDelegate.swift)、[旧 Core Data モデル](../../old/src/SeasoningManager/SeasoningManager/SeasoningManager.xcdatamodeld/SeasoningManager.xcdatamodel/contents)、[新 SeasoningManagerApp.swift](../../src/SeasoningManager/SeasoningManager/SeasoningManagerApp.swift)

### 保存場所と読み取り条件

旧アプリは `NSPersistentContainer(name: "SeasoningManager")` を作り、保存 URL を変更せずに `loadPersistentStores` している。既定の保存先から推定される旧ストアは **`<アプリのデータコンテナ>/Library/Application Support/SeasoningManager.sqlite`** である。実端末の URL は未取得のため、旧版の `persistentStoreCoordinator.persistentStores` の各 `url` と実ファイルを照合して確定する。データコンテナの UUID を含む絶対パスは固定せず、更新後のコンテナ内で保存先を解決する。

Issue #15 の調査時点では新アプリはひな形の `Item(timestamp)` を使っていた。#20 反映後の対象ブランチは Product / 個体 Item と `cloudKitDatabase: .none` を使うが、保存 URL は依然として既定値で、旧ストアの読み取りは未実装である。移行実装時には新しい `ModelConfiguration.url` を記録し、旧ストアと異なる URL を明示する。既定のファイル名だけを根拠に安全と判断しない。

- 旧ストアが存在することを確認してから、旧 `SeasoningManager` モデルで読み取る。読み取り失敗時に空ストアを作って「移行成功」と扱わない。
- バックアップは書き込みを停止した整合的な状態で取得する。SQLite 本体だけでなく、存在する `SeasoningManager.sqlite-wal` / `SeasoningManager.sqlite-shm` と関連ファイルも保全する。稼働中に本体だけコピーしない。
- 更新でデータコンテナへアクセスできることと、旧モデルのレコードを読み取れること、新モデルへ変換できることは別々に検証する。

### 更新として配布する条件と自動移行できないケース

通常の更新では同じ Bundle ID を維持し、旧配布元の Team・App ID に対応する有効な署名を使用する。新旧の署名済み `application-identifier`（App ID Prefix を含む）と Profile の権限を照合する。Team 移管や Prefix 変更がある場合は Apple の移管手順を別途確認し、Bundle ID の一致だけで上書きできると判断しない。CloudKit・Push の権限も新しい Profile と整合させる。

App Store 配布済みなら同じ App Store Connect のアプリレコードへの更新とし、受理されるバージョン・ビルド番号を設定する。開発・Ad Hoc 配布なら対応する署名と端末登録などを確認する。実際の旧配布経路は未確認であり、その経路に合わせた更新を検証する。

| 条件 | 扱い |
|:--|:--|
| 同じアプリとして削除せず上書きし、旧データが残っている | 自動移行の候補。署名・旧ストア読み取り・変換の検証が必要。 |
| Bundle ID を変更して別アプリとして配布する | 別サンドボックスになる。現在の構成では旧コンテナを直接読めず、自動移行できない。同じ Team や同じ iCloud アカウントでも解決しない。 |
| 署名不整合で更新が拒否される | 署名を修正する。旧アプリを削除してインストールし直す方法を移行手順にしない。 |
| 旧アプリをデータごと削除済み、または別端末へ新規インストールする | 旧ストアがないためローカル自動移行はできない。復元可能なバックアップ等があれば別途扱う。 |
| 端末が新アプリの最低 iOS を満たさない | その端末では更新・移行を実行できない。 |

別アプリ配布を選ぶ場合は、旧アプリ側のエクスポートと新版側のインポートなど、利用者がデータを受け渡せる経路が別途必要になる。後から新アプリだけに App Groups を追加しても、旧アプリの私有ストアが共有領域へ移るわけではない。

### 実機検証手順と未確認事項

1. 旧配布物、配布経路、端末 OS、新旧ビルドのコミットと Xcode バージョンを記録する。旧版で実データを保存し、件数・識別子・画像・開封日・賞味期限を記録してバックアップを取得する。
2. Mac 上で新旧の署名済み `.app` を調べる。`codesign -d --entitlements :- /path/to/SeasoningManager.app` と `codesign -dv --verbose=4 /path/to/SeasoningManager.app` で `application-identifier`、Team、署名を確認する。埋め込み Profile がある配布物では `security cms -D -i /path/to/SeasoningManager.app/embedded.mobileprovision` も照合する。Profile の全文や端末識別子をリポジトリへ保存しない。
3. 旧版のロード済みストア URL とバックアップ内のファイルを照合する。新版の保存 URL が別であることも確認する。
4. 移行処理を実装した新版を、旧版を削除せず同じテスト端末へ更新インストールする。旧ストアを開けること、データ変換後の件数・画像・日付、旧データの保全、再起動しても重複しないことを確認する。空データでの新規インストールやシミュレータのみの検証で署名検証を代替しない。
5. インストール結果、署名の比較結果、コンテナ内の相対パス、移行前後の件数と未解決事項をこの節へ追記する。

| 検証 | 2026-10-01 の結果 |
|:--|:--|
| 新旧プロジェクト・モデル・初期化コードの静的照合 | 実施済み。上記の設定値と保存先を確認（実パスは推定）。 |
| 署名済み配布物・Profile の比較 | 未実施。配布物と署名環境が必要。 |
| Xcode ビルド・実機への更新インストール | 未実施。この作業環境は Linux で `xcodebuild` と iOS 実機を利用できない。 |
| 実ストアの読み取り・SwiftData 変換・再起動 | 未実施。旧実データと移行処理の実装が必要。 |

Issue #15 のビルドまたは動作確認条件は未達であり、本調査だけで旧アプリから安全に更新できるとは判定しない。

参照：[Apple: NSPersistentContainer.defaultDirectoryURL](https://developer.apple.com/documentation/coredata/nspersistentcontainer/defaultdirectoryurl())、[Apple TN2415: Entitlements Troubleshooting](https://developer.apple.com/library/archive/technotes/tn2415/_index.html)、[Apple TN2319: Installation Failure Troubleshooting for iOS](https://developer.apple.com/library/archive/technotes/tn2319/_index.html)。TN2319 は開発・ベータ版のインストール診断資料であり、App Store 配布の実機確認を代替しない。

## 確認条件

| 場面 | 期待する結果 |
|:--|:--|
| 同じ商品に2本登録 | 両端末で同じ商品と2つの個体を確認できる。 |
| 写真を登録・変更 | 別端末にも対応する商品画像が反映される。 |
| オフラインで開封・削除 | 端末内の結果をすぐ確認でき、再接続後に他端末にも反映される。 |
| 同じ個体を双方で編集 | 新しい更新が採用され、重複や状態矛盾が起きない。 |
| 更新前データを保持して起動 | 件数と元の値が保たれ、二度起動しても複製されない。 |
| iCloud 未サインイン | 端末内で使え、同期不可が分かる。 |

## 実装前に検証する点

iCloud の容量や画像サイズの上限、アカウント切替時の端末内データとクラウドデータの境界、SwiftData / CloudKit での同期競合・削除制限の実現方式、旧 Core Data からの移行手順は別の技術設計で決める。これらの検証が終わるまで、同期完了時期の保証は置かない。
