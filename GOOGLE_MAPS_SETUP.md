# Google Maps 統合セットアップガイド

このドキュメントはアプリにGoogle Mapsを統合するためのセットアップ手順を説明します。

## 機能概要

- 会場登録時にマップで位置情報を選択
- 会場詳細画面にマップを表示
- Geolocatorで現在地情報を取得

## 必要な手順

### 1. Google Cloud Console でAPI キーを生成

1. [Google Cloud Console](https://console.cloud.google.com/) にアクセス
2. プロジェクトを作成または選択
3. APIs & Services → Library で以下を有効化：
   - Google Maps Platform
   - Maps SDK for Android
   - Maps SDK for iOS
4. APIs & Services → Credentials で API キーを作成

### 2. Android設定

**ファイル:** `android/app/src/main/AndroidManifest.xml`

```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="YOUR_ANDROID_MAPS_API_KEY_HERE" />
```

`YOUR_ANDROID_MAPS_API_KEY_HERE` を、Google Cloud Console で生成した API キーに置き換えてください。

### 3. iOS設定

**ファイル:** `ios/Runner/Info.plist`

iOS用の設定は既に追加されています。別途iOS用のAPI キーが必要な場合は、Google Cloud Consoleで生成してください。

### 4. Web設定

**ファイル:** `web/index.html`

```html
<script src="https://maps.googleapis.com/maps/api/js?key=YOUR_WEB_MAPS_API_KEY_HERE"></script>
```

`YOUR_WEB_MAPS_API_KEY_HERE` を、Google Cloud Console で生成した Web用の API キーに置き換えてください。

## 依存パッケージ

以下のパッケージをインストール済みです：

- **google_maps_flutter: ^2.7.7** - Google Maps の Flutter ウィジェット
- **geolocator: ^12.0.1** - 位置情報取得

`flutter pub get` を実行して依存パッケージをインストールしてください。

## 使用方法

### 会場登録時

1. 「会場を追加」ボタンを押す
2. 会場情報を入力
3. 「マップから選択」ボタンを押す
4. マップ上をタップして位置を選択
5. 「この位置を選択」ボタンを押す

### 会場詳細表示時

- 会場詳細シートに緯度経度が設定されている場合、マップが表示されます
- マップにマーカーが表示され、会場の位置を確認できます

## トラブルシューティング

### マップが表示されない

1. API キーが正しく設定されているか確認
2. API キーが有効になっているか Google Cloud Console で確認
3. `flutter clean` を実行してビルドキャッシュをクリア
4. 再度 `flutter pub get` と `flutter run` を実行

### 位置情報が取得できない

1. アプリの位置情報パーミッションが有効になっているか確認
2. iOS: Info.plist に位置情報許可の説明文を追加済み
3. Android: AndroidManifest.xml にパーミッション宣言を追加済み

## サーバータイムスタンプについて

会場情報を保存する際、Firestore に `updatedAt` サーバータイムスタンプが自動的に記録されます。

## 参考リンク

- [Google Maps Platform Documentation](https://developers.google.com/maps/documentation)
- [google_maps_flutter Plugin](https://pub.dev/packages/google_maps_flutter)
- [geolocator Plugin](https://pub.dev/packages/geolocator)
