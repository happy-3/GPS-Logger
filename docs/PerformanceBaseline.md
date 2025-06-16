# パフォーマンスベースライン計測手順

Xcode Instruments を使い、FPS とメモリ使用量を記録します。

1. Xcode で本プロジェクトを開き、メニューから **Product ▶ Profile** を選択します。
2. Instruments が起動したら **Time Profiler** と **Core Animation FPS** を追加します。
3. アプリを通常通り操作し、30 秒ほど記録します。
4. 記録が終了したら `File ▶ Save` で `.trace` ファイルを保存しておきます。
5. コード変更後も同じ手順で計測し、前回の `.trace` と比較してください。

これによりパフォーマンス回帰を早期に検知できます。
