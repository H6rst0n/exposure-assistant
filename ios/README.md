# iOS 曝光助手

原生 SwiftUI，iOS / iPadOS 16.0 以上。Android 原始碼與設定格式不變。

## 功能

- 與 Android 同一套對數曝光公式：求快門、光圈、ISO、ND，實際 f/2.8 不替換成 √8。
- 分數快門、三種 ND 單位與多片疊加、常用值與取整亮暗差。
- 11 款 ILFORD/HARMAN 底片補償；未知底片不套係數；底片模式不求 ISO。
- 獨立儲存的星空換算與 500 法則提醒；忽略隱藏 ND 和底片選擇，不做 NPF 或測光。
- 離線本機設定、夜間紅色介面、內容調暗、單次曝光倒數。
- 不讀取相機、照片、定位或帳號；不控制相機快門。

## 與 Android 的平台差異

iOS 本機通知不是 Android 精確鬧鐘。聲音、到達時間、背景震動受到 iOS 通知權限、靜音及專注模式影響，不能保證準時發聲。第一次主動使用背景通知計時才詢問權限。通知被拒時可以明確選擇前景模式；前景模式離開 App 會中斷，不假稱背景可靠。

震動開關僅控制前景震動，無法獨立覆寫 iOS 背景通知的震動設定。內容調暗使用 App 覆蓋層，不更改整個裝置的系統亮度；鍵盤、系統提示與部分 sheet 不會變暗。

請用相機本身控制極短曝光。計時範圍 0.1 秒至 7 天；同時只能存在一個計時，參數修改不會改動已啟動的計時。跨程序／重開機復原策略見 TimerSupport 測試與 TimerController；任何中斷提示都需自行確認快門狀態。

## 在 Mac 建置與測試

需要 Xcode 16 或更新版本，首次開啟需安裝 iOS simulator runtime。使用官方 Homebrew 的 XcodeGen 產生工程：

```sh
brew install xcodegen
cd ios
swift test --package-path ExposureCore
swift test --package-path TimerSupport
xcodegen generate
open ExposureAssistant.xcodeproj
```

在 Xcode 選 ExposureAssistant scheme 與已安裝的 iPhone 模擬器，按 Run。執行 Product → Test 跑 UI 測試。CLI：

```sh
xcodebuild test -project ExposureAssistant.xcodeproj -scheme ExposureAssistant \
  -destination 'platform=iOS Simulator,name=<你的模擬器名稱>' CODE_SIGNING_ALLOWED=NO
```

CI 會動態選擇可用 iPhone simulator，不硬編碼裝置名稱。`project.yml` 是工程來源，產生的 `.xcodeproj` 不需提交。

## 安裝與簽章限制

模擬器 `.app` **不能裝到 iPhone**，未簽署的裝置建置也不能直接安裝。實機安裝需 Mac/Xcode 與 Apple 帳號設定簽章；TestFlight / App Store 發佈還需合適的 Apple Developer Program 權限與發佈流程。本次不建立憑證、不購買會員、不上架，也不把未簽署建置稱為可安裝 IPA。

## 測試與誠實範圍

- `ExposureCore`：數值、無效輸入、ND、底片、取整、模式限制與資料編碼。
- `TimerSupport`：純時間狀態與中斷／復原邏輯。
- `ExposureAssistantUITests`：範例、錯誤輸入、設定重啟保存、分頁隔離、底片模式、旋轉、前景倒數完成及取消。
- GitHub Actions：標準 public-repo macOS runner 執行 package tests、Xcode simulator UI tests 和 unsigned device Release build；不使用 larger runners。

成功編譯與模擬器通過不等於實機驗證。鎖屏、長時間背景、重開機、通知音量／專注模式、實際震動、裝置耗電與真實曝光時序仍需 iPhone/iPad 實測。測試結果以特定 commit 的 CI 為準，不因本文件存在就宣稱通過。
