import SwiftUI
import ExposureCore
import TimerSupport

struct ContentView: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var timer: TimerController
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showStars = false
    @State private var showHelp = false
    @State private var showTimer = false
    @State private var timerText = ""
    @State private var timerError: String?
    @State private var useBackground = true
    private var astro: Bool { store.settings.page == 1 }
    private var form: Binding<FormState> {
        Binding(get: { astro ? store.settings.astro : store.settings.exposure }, set: {
            if astro { store.settings.astro = $0 } else { store.settings.exposure = $0 }
        })
    }
    private var result: Result<Calculation, Error> { Result { try calculate(form.wrappedValue, astro: astro) } }
    private var color: Color { store.settings.red ? .red : Color(red: 0.70, green: 0.87, blue: 0.76) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("拍攝模式", selection: $store.settings.page) {
                        Text("曝光換算").tag(0); Text("星空攝影").tag(1)
                    }.pickerStyle(.segmented).accessibilityIdentifier("page_picker")
                    if timer.state.status != .idle { timerCard }
                    Text(astro ? "固定腳架的數碼曝光換算；不自動限制快門。" : "先試拍確認亮度，再換算拍攝參數。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("載入範例") {
                        form.wrappedValue.reference = Inputs(aperture: "2", shutter: "2", iso: "6400")
                    }.accessibilityIdentifier("load_example")
                    inputCard(title: "01 ／ 參考設定", inputs: form.reference, prefix: "reference", solve: nil)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("02 ／ 目標設定").font(.headline)
                        Picker("求解", selection: form.solve) {
                            ForEach(Solve.allCases.filter { (!astro || $0 == .shutter || $0 == .iso) && !(form.wrappedValue.filmMode && !astro && $0 == .iso) }) { item in
                                Text("求\(item.label)").tag(item)
                            }
                        }.pickerStyle(.menu).accessibilityIdentifier("solve_picker")
                        parameterFields(inputs: form.target, prefix: "target", solve: form.wrappedValue.solve)
                        if !astro && form.wrappedValue.solve != .nd { ndFields(inputs: form.target, prefix: "target") }
                        field("曝光補償（檔）", text: form.compensation, id: "compensation")
                        if !astro {
                            Toggle("底片長曝光補償", isOn: form.filmMode).accessibilityIdentifier("film_toggle")
                            if form.wrappedValue.filmMode {
                                Picker("底片", selection: form.filmId) {
                                    ForEach(Films.all, id: \.id) { film in Text(film.name).tag(film.id) }
                                    Text("其他底片（無補償資料）").tag("unknown")
                                }.accessibilityIdentifier("film_picker")
                                Text("ISO／EI 不會改變已裝底片的感光能力；只在求快門時補償。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.panel()
                    switch result {
                    case .success(let calculation): resultCard(calculation)
                    case .failure(let error): Text(error.localizedDescription).foregroundStyle(.orange).accessibilityIdentifier("input_error").panel()
                    }
                    if astro { Button("500 法則") { showStars = true } }
                    Text("完全離線 · 不測光、不讀取照片、不控制相機").font(.caption).foregroundStyle(.secondary)
                }.padding()
            }
            .navigationTitle("曝光助手")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showHelp = true } label: { Image(systemName: "questionmark.circle") }.accessibilityLabel("使用說明")
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("設定").accessibilityIdentifier("settings")
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } }
            }
            .colorMultiply(store.settings.red ? .red : .white)
            .tint(color)
            .foregroundStyle(store.settings.red ? Color.red : Color.primary)
            .sheet(isPresented: $showSettings) { settingsSheet.colorMultiply(store.settings.red ? .red : .white) }
            .sheet(isPresented: $showTimer, onDismiss: { if timer.isStarting { timer.cancel() } }) { timerSheet.colorMultiply(store.settings.red ? .red : .white) }
            .sheet(isPresented: $showStars) { starsSheet.colorMultiply(store.settings.red ? .red : .white) }
            .sheet(isPresented: $showHelp) { helpSheet.colorMultiply(store.settings.red ? .red : .white) }
            .onChange(of: store.settings.page) { _ in
                if astro && !store.settings.hideStars { showStars = true }
            }
            .onChange(of: store.settings.exposure.filmMode) { value in
                if value && store.settings.exposure.solve == .iso { store.settings.exposure.solve = .shutter }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .background { timer.sceneBackgrounded() }
                timer.sceneChanged(active: phase == .active)
            }
            .onAppear { timer.sceneChanged(active: scenePhase == .active) }
            .alert("提醒", isPresented: Binding(get: { timer.message != nil || store.saveError != nil }, set: { if !$0 { timer.message = nil; store.saveError = nil } })) {
                Button("好") { timer.message = nil; store.saveError = nil }
            } message: { Text(timer.message ?? store.saveError ?? "") }
            // A content-only overlay avoids changing the system-wide display brightness.
            .overlay {
                if store.settings.dim {
                    Color.black.opacity(1 - Double(store.settings.brightness)).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption)
            TextField("輸入", text: text).textFieldStyle(.roundedBorder).keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityLabel((id.hasPrefix("reference_") ? "參考 " : (id.hasPrefix("target_") ? "目標 " : "")) + title).accessibilityIdentifier(id)
        }
    }
    private func inputCard(title: String, inputs: Binding<Inputs>, prefix: String, solve: Solve?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            parameterFields(inputs: inputs, prefix: prefix, solve: solve)
            if !astro { ndFields(inputs: inputs, prefix: prefix) }
        }.panel()
    }
    private func parameterFields(inputs: Binding<Inputs>, prefix: String, solve: Solve?) -> some View {
        VStack(spacing: 12) {
            parameter("光圈 f/", text: inputs.aperture, type: .aperture, prefix: prefix, solved: solve == .aperture)
            parameter("快門（秒）", text: inputs.shutter, type: .shutter, prefix: prefix, solved: solve == .shutter)
            parameter("ISO / EI", text: inputs.iso, type: .iso, prefix: prefix, solved: solve == .iso)
        }
    }
    private func parameter(_ title: String, text: Binding<String>, type: Solve, prefix: String, solved: Bool) -> some View {
        HStack(alignment: .bottom) {
            if solved {
                VStack(alignment: .leading) { Text(title).font(.caption); Text("自動計算，見下方結果").foregroundStyle(color) }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                field(title, text: text, id: "\(prefix)_\(type.rawValue)")
                Menu("常用值") {
                    ForEach(presets(type), id: \.self) { value in
                        Button(valueLabel(value, solve: type)) { text.wrappedValue = type == .shutter && value < 0.5 ? "1/\(number(1 / value))" : number(value) }
                    }
                }.accessibilityLabel("\(prefix == "reference" ? "參考" : "目標")\(type.label)常用值")
            }
        }
    }
    private func presets(_ type: Solve) -> [Double] {
        switch type { case .aperture: return ExposureMath.apertures; case .iso: return ExposureMath.isos; default: return ExposureMath.shutters }
    }
    private func ndFields(inputs: Binding<Inputs>, prefix: String) -> some View {
        DisclosureGroup("減光鏡 ND") {
            Picker("ND 單位", selection: Binding(get: { inputs.wrappedValue.unit }, set: { unit in
                if let stops = try? ExposureMath.nd(inputs.wrappedValue.nd, unit: inputs.wrappedValue.unit) {
                    let value: Double = unit == .stops ? stops : (unit == .factor ? pow(2, stops) : stops * log10(2))
                    inputs.wrappedValue.nd = String(value)
                }
                inputs.wrappedValue.unit = unit
            })) { ForEach(NdUnit.allCases) { Text($0.label).tag($0) } }
            field("ND（多片用 + 疊加）", text: inputs.nd, id: "\(prefix)_nd")
            Text("倍率的 + 代表疊加：8 + 64 = 512 倍；無濾鏡填 0 檔、1 倍或密度 0。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func resultCard(_ calculation: Calculation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("03 ／ 換算結果").font(.headline)
            Text(valueLabel(calculation.exact, solve: form.wrappedValue.solve)).font(.largeTitle.monospacedDigit()).accessibilityIdentifier("exact_result")
            if form.wrappedValue.solve == .nd && calculation.exact < 0 {
                Text("需要增加曝光；沒有負檔減光鏡。請移除 ND 或調整其他參數。")
            }
            if let common = calculation.common, let diff = calculation.difference {
                Text("常用設定：\(valueLabel(common, solve: form.wrappedValue.solve))")
                Text(abs(diff) < 0.00005 ? "與理論值相同" : "\(diff > 0 ? "亮" : "暗") \(number(abs(diff))) 檔")
            }
            if let corrected = calculation.corrected {
                Text("\(calculation.film?.name ?? "") 補償後：\(secondsLabel(corrected))").accessibilityIdentifier("corrected_result")
                Text("以未取整的理論秒數計算，只補償一次。≤1 秒不補償。").font(.caption)
            } else if form.wrappedValue.filmMode && !astro {
                Text("目前僅理論換算；未知底片不借用其他係數，非求快門不做反向補償。").font(.caption)
            }
            let duration = calculation.corrected ?? calculation.targetSeconds
            Button("曝光倒數 · \(secondsLabel(duration))") { timerText = number(duration); timerError = nil; showTimer = true }
                .buttonStyle(.borderedProminent).disabled(!(0.1...604800).contains(duration)).accessibilityIdentifier("open_timer")
            if form.wrappedValue.solve == .shutter, calculation.corrected == nil, let common = calculation.common, abs(common-calculation.exact) > 0.00001 {
                Button("以常用時間計時：\(secondsLabel(common))") { timerText = number(common); timerError = nil; showTimer = true }.disabled(!(0.1...604800).contains(common))
            }
        }.panel()
    }
    private var timerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(timer.isRunning ? "曝光倒數中" : (timer.state.status == .completed ? "曝光時間已到" : "計時已中斷")).font(.headline)
            if timer.isRunning {
                Text(durationLabel(Int64(ceil(timer.remaining)))).font(.largeTitle.monospacedDigit()).accessibilityIdentifier("countdown")
                Text(timer.state.background ? "本機通知已排程；受系統通知、專注模式及靜音設定影響。" : "僅前景計時：請保持 App 開啟。")
            } else { Text("請確認相機快門；App 不會控制相機。") }
            Button(timer.isRunning ? "取消計時" : "清除提示") { timer.cancel() }.accessibilityIdentifier("cancel_timer")
        }.panel()
    }
    private var timerSheet: some View {
        NavigationStack {
            Form {
                field("計時秒數", text: $timerText, id: "timer_seconds")
                Text("0.1 秒至 7 天，請手動開關相機快門。")
                Toggle("使用背景通知", isOn: $useBackground).accessibilityIdentifier("background_toggle")
                Text("背景模式會詢問通知權限，不能保證精確鬧鐘或聲音。拒絕後可關閉此選項，明確選擇前景計時。前景模式離開 App 會中斷。")
                Text("iOS 背景震動由系統控制；震動開關僅控制 App 前景提示。")
                if timer.isRunning { Text("已有計時，請先取消原計時。").foregroundStyle(.orange) }
                if let error = timerError { Text(error).foregroundStyle(.orange).accessibilityIdentifier("timer_error") }
                Button("開始倒數") {
                    Task {
                        do {
                            let seconds = try ExposureMath.positive(timerText, name: "計時秒數")
                            try await timer.start(seconds: seconds, background: useBackground, sound: store.settings.sound, vibration: store.settings.vibration)
                            showTimer = false
                        } catch { timerError = error.localizedDescription }
                    }
                }.disabled(timer.isRunning || timer.isStarting).accessibilityIdentifier("timer_start")
            }.navigationTitle("曝光倒數").toolbar { Button("取消") { if timer.isStarting { timer.cancel() }; showTimer = false } }
        }
    }
    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Toggle("夜間紅色介面", isOn: $store.settings.red).accessibilityIdentifier("red_toggle")
                Toggle("調暗 App 內容", isOn: $store.settings.dim)
                if store.settings.dim { Slider(value: $store.settings.brightness, in: 0.1...1).accessibilityLabel("內容亮度").accessibilityValue("\(Int(store.settings.brightness * 100)) 百分比"); Text("不改動系統亮度；系統鍵盤與提示不受影響。") }
                Toggle("下次計時聲音", isOn: $store.settings.sound)
                Toggle("下次前景震動", isOn: $store.settings.vibration)
                Toggle("不自動顯示 500 法則", isOn: $store.settings.hideStars)
                Text("設定僅儲存在這部裝置。背景通知聲音與震動仍由 iOS 通知及專注模式控制。")
            }.navigationTitle("現場設定").toolbar { Button("完成") { showSettings = false }.accessibilityIdentifier("settings_done") }
        }
    }
    private var starsSheet: some View {
        NavigationStack { ScrollView { VStack(spacing: 20) { Text(STAR_NOTICE); Toggle("不再自動顯示", isOn: $store.settings.hideStars) }.padding() }.navigationTitle("500 法則").toolbar { Button("我知道了") { showStars = false }.accessibilityIdentifier("stars_dismiss") } }
    }
    private var helpSheet: some View {
        NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 16) {
            Text("先試拍確認亮度，輸入參考參數，再選擇目標求解項目。快門以秒輸入，例如 1/125、0.5 或 120。")
            Text("這不是現場測光。HDR、夜景合成、鏡頭透光率與沖洗差異都可能影響結果。")
            Text("底片補償來源：\(Films.VERSION)")
            Link("ILFORD 原廠補償文件", destination: URL(string: Films.SOURCE)!)
            Text("App 離線計算、不讀取照片、不控制相機。外部資料連結才需要網路。")
        }.padding() }.navigationTitle("使用說明").toolbar { Button("關閉") { showHelp = false } } }
    }
}

private extension View {
    func panel() -> some View { padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 18)) }
}
