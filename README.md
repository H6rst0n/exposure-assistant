# iOS 版本

新增原生 SwiftUI iOS / iPadOS 16+ 版本，保留既有 Android。建置、模擬器測試、簽章限制及平台差異請見 [ios/README.md](ios/README.md)。iOS 模擬器或未簽署產物不是可直接安裝到 iPhone 的 IPA。

## 1.0.1 流暢度修正版

使用 release 最佳化建置（關閉偵錯、R8 程式最佳化、移除未使用資源）。
倒數數字獨立更新，每個顯示秒數變更才更新，計時到期處理保持在捲動列表之外。
亮度滑桿調整時不再反覆還原系統預設亮度。

直接安裝 `exposure-assistant-1.0.1-release.apk` 覆蓋原版，無需移除；沿用套件名稱、測試簽章及本機設定格式。
若 Play Protect 再度提示，可展開「更多詳情」查看該 APK 的安裝選項，不必關閉整體防護。
本版不宣稱 Pixel 8a 的實測 FPS。請比較上下滑動與常用值選單的流暢度。

# 曝光助手 / Exposure Assistant

繁體中文、原生 Android、完全離線的攝影曝光換算工具。Android 8.0（API 26）以上。

## 安裝與第一次使用

將交付的 `exposure-assistant-1.0.1-release.apk` 傳到 Android 手機並開啟。依 Android 提示，允許目前開啟 APK 的檔案管理工具安裝此應用程式。這是自行安裝的測試版，不是 Google Play 商店版本。

1. **曝光換算**：輸入亮度已滿意的參考光圈、快門、ISO。
2. 在目標卡片選「求快門／求光圈／求 ISO／求 ND」，再輸入其餘設定。
3. 下方顯示理論值、常用設定與採用常用設定的亮暗差；底部保留結果摘要。
4. 「載入範例」會明確填入 f/2、2 秒、ISO 6400，方便熟悉操作；它不是場景測光。初始參考欄位留空，不猜測現場亮度。

### 數值與 ND

- 快門一律以秒輸入：`1/125`、`0.5`、`120` 均可。
- 光圈填數字，例如 `2.8`；ISO 可用常用值或自訂正數。
- 曝光補償 `+1` 代表比參考亮一檔，`-1` 代表暗一檔。
- 點開各組參數的「減光鏡 ND」。多片以 `+` 分隔：`3 + 6` 檔，或 `8 + 64` 倍率，皆等於 9 檔。
- **倍率模式的 + 代表多片疊加，不是算術相加**。ND8 與 ND64 疊加為 512 倍。
- 無濾鏡：0 檔、1 倍或密度 0。倍率 1000 依真實數值算成約 9.9658 檔，不強制當作 10 檔。
- 需要增加曝光時，ND 反算可能為負；此時 App 提示調整參數，不推薦負檔濾鏡。
- 以使用者輸入的實際數字計算；例如 f/2.8 不暗中改為精確的 √8。

### 底片長曝光補償

開啟目標設定內的底片模式，選擇底片型號。目標 ISO／EI 保持可輸入，但不提供「求 ISO」，避免把已裝底片當作數碼相機調整感光度。

內建 ILFORD/HARMAN 2023-12 文件列出的 11 款：SFX 200、Pan F Plus、DELTA 100／400／3200、FP4 Plus、HP5 Plus、XP2 Super、ORTHO Plus、Kentmere 100／400。

- 先完成等效曝光、ND、曝光補償，再以**未取整的理論秒數**計算底片補償。
- 理論時間 ≤1 秒：不補償。>1 秒：`corrected = seconds ^ P`。
- 同時顯示理論時間與補償後時間；預設倒數使用補償後時間。
- 求光圈或 ND 時只提供理論反算，不反推非線性的底片補償。
- 「其他底片」只換算理論曝光，不借用別的底片係數。
- 計算不處理推拉沖洗、彩色長曝色偏或不同鏡頭透光率；跨器材換算仍需試拍確認。

### 星空攝影

此頁專供數碼相機、固定腳架使用，可求快門或 ISO。與曝光換算頁分開保存參數，不使用底片補償或隱藏的 ND 值。

首次進入顯示 500 法則；可選擇不再自動顯示，之後仍能點「500 法則」查看。

`曝光秒數 ≈ 500 ÷ 全片幅等效焦距（mm）`

全片幅 50 mm 約 10 秒；1.5× APS-C 的 50 mm 約 6.7 秒。這是經驗估算，不是防拖線保證。高像素與放大檢視通常需要更短時間。App **不要求器材資料、不使用 NPF、不自動限制快門**。

### 計時與夜間介面

- 點結果的曝光倒數，可確認或修改時間再開始。支援 0.1 秒至 7 天；極短曝光請以相機本身的快門控制。
- 已有計時時，必須先取消才能開始另一個，避免意外覆蓋。
- 背景計時需要通知及精確鬧鐘權限，僅在需要時引導授權。系統通知圖示可能顯示已排程的鬧鐘。
- 未就緒時可明確選「前景計時」：App 保持螢幕亮起，切換 App 或鎖屏後不保證準時提醒。
- 計時以單調時鐘計算剩餘時間；背景系統鬧鐘在裝置時間更改後重新排程。
- 切頁／旋轉不重設倒數；修改拍攝參數不改動已啟動計時。裝置重啟後標示中斷，不自動補做。
- 提醒不會控制相機。請手動開關快門；系統音量、勿擾、通知頻道及廠商省電限制仍會影響聲音與通知。強制停止 App 會取消系統鬧鐘。
- 右上角設定提供紅色介面、僅調整 App 視窗的亮度，以及下一次計時的聲音／震動選項。

## 建置

已固定工具版本：JDK 17、Gradle 8.9、Android Gradle Plugin 8.7.3、Kotlin 2.0.21、Compose BOM 2024.12.01、compile/target SDK 35。選擇一組相容版本以便重現，不依賴機器上其他研究軟體。

安裝 JDK 17 與 Android SDK（平台 35、build-tools 34.0.0、platform-tools）。在專案根目錄建立不提交的 `local.properties`：

```properties
sdk.dir=/你的/Android/Sdk
```

Windows 可使用正斜線路徑，例如 `sdk.dir=C:/Users/你的帳號/AppData/Local/Android/Sdk`。

```bash
./gradlew assembleRelease testReleaseUnitTest lintRelease
./gradlew assembleDebug assembleDebugAndroidTest  # 僅供開發及儀器測試
./gradlew connectedDebugAndroidTest  # 有可用模擬器或 USB 偵錯裝置時
```

Windows 對應命令為 `gradlew.bat`。首次建置需下載依賴，App 本身運作不需要網路。最佳化 APK 位於 `app/build/outputs/apk/release/app-release.apk`。

GitHub 原始碼不包含簽章金鑰。若專案根目錄有本機 `debug.keystore`，建置會沿用它；若沒有，則使用 Android 工具自動產生的預設 debug 金鑰。`release` 建置同樣使用這組本機測試金鑰，供自行安裝測試；它代表關閉偵錯並啟用 R8／資源縮減，不代表商店驗證或正式開發者身分。

自行建置的 APK 若使用不同金鑰，無法直接覆蓋維護者提供的 APK。維護者需備份並保留原金鑰，才能持續更新已安裝的版本；金鑰不可提交至 Git，也不要附在 Release 的原始碼壓縮檔中。正式發布需另行規劃簽章金鑰。

`outputs/`（APK 與測試報告）、`work/`（建置與開發紀錄）、`local.properties` 和金鑰均由 `.gitignore` 排除。APK 應另外放到 GitHub Releases，不直接提交至原始碼儲存庫。

## 程式結構

- `ExposureMath.kt`：純 Kotlin 曝光公式、四種求解、ND 轉換、常用值與底片資料。
- `AppState.kt`：輸入模型、計算組合、DataStore、ViewModel。
- `MainActivity.kt`：Compose 中文雙頁介面、500 法則、設定與倒數操作。
- `Timer.kt`：單次系統鬧鐘、通知、前景提醒及重啟中斷處理。
- `app/src/test`：數值、輸入、補償與隨機交叉驗證。
- `app/src/androidTest`：介面、資料保存、計時與鎖屏測試。

公式統一使用 `log2(t) + log2(ISO) - 2 log2(N) - ND` 作為等效亮度指標，再套用相對檔數；不是用照片內容測光，也不表示 ISO 會增加實際進光量。

## 資料來源

- [ILFORD Film Reciprocity Failure Compensation，Dec 2023](https://www.ilfordphoto.com/amfile/file/download/file/1964/product/698/)
- [Canon Academy：Astrophotography／500 法則](https://www.academy.canon.co.za/en/hacks-tips-tricks/astrophotography)
- [Android 精確鬧鐘官方說明](https://developer.android.com/develop/background-work/services/alarms)

依賴第三方開源 Android／Kotlin 函式庫，相關授權隨上游套件。介面與程式獨立實作，未複製參考 App 的程式或視覺素材。
