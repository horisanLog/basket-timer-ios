//
//  ContentView.swift
//  Basket Timer
//
//  Created by 堀口剛弘 on 2025/10/04.
//

import SwiftUI
import Combine
import AVFoundation
import AudioToolbox
import UIKit

// ================= ロジック =================
final class Clock: ObservableObject {
    @Published var duration: TimeInterval      // 設定時間
    @Published var remaining: TimeInterval     // 残時間
    @Published var isRunning = false
    
    private var startAt: Date?
    private var pausedRemaining: TimeInterval?
    private var cancellable: AnyCancellable?
    
    init(seconds: TimeInterval) {
        duration = seconds
        remaining = seconds
        startTicker()
    }
    
    private func startTicker() {
        // 20Hzほどで十分（精度と負荷のバランス）
        cancellable = Timer.publish(every: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, isRunning, let startAt else { return }
                let elapsed = Date().timeIntervalSince(startAt)
                remaining = max(0, (pausedRemaining ?? duration) - elapsed)
                if remaining == 0 { isRunning = false }
            }
    }
    
    func start() {
        guard remaining > 0, !isRunning else { return }
        startAt = Date()
        pausedRemaining = remaining
        isRunning = true
    }
    
    func stop() {
        guard isRunning else { return }
        if let startAt {
            let elapsed = Date().timeIntervalSince(startAt)
            remaining = max(0, (pausedRemaining ?? duration) - elapsed)
        }
        isRunning = false
    }
    
    func reset(to seconds: TimeInterval? = nil) {
        stop()
        pausedRemaining = nil
        if let s = seconds {
            duration = s
            remaining = s
        } else {
            remaining = duration
        }
    }
    
    var mmss: String {
        let total = Int(ceil(remaining))
        return String(format: "%02d:%02d", total/60, total%60)
    }
}

final class ShotClock: ObservableObject {
    @Published var duration: TimeInterval
    @Published var remaining: TimeInterval
    @Published var isRunning = false
    
    private var startAt: Date?
    private var pausedRemaining: TimeInterval?
    private var cancellable: AnyCancellable?
    
    init(seconds: TimeInterval = 24) {
        duration = seconds
        remaining = seconds
        startTicker()
    }
    
    private func startTicker() {
        // 50Hz（0.02s刻み）で0.1秒表示をなめらかに
        cancellable = Timer.publish(every: 0.02, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, isRunning, let startAt else { return }
                let elapsed = Date().timeIntervalSince(startAt)
                remaining = max(0, (pausedRemaining ?? duration) - elapsed)
                if remaining == 0 { isRunning = false }
            }
    }
    
    func start() {
        guard remaining > 0, !isRunning else { return }
        startAt = Date()
        pausedRemaining = remaining
        isRunning = true
    }
    
    func stop() {
        guard isRunning else { return }
        if let startAt {
            let elapsed = Date().timeIntervalSince(startAt)
            remaining = max(0, (pausedRemaining ?? duration) - elapsed)
        }
        isRunning = false
    }
    
    func reset(_ seconds: TimeInterval? = nil) {
        stop()
        if let s = seconds {
            duration = s
            remaining = s
        } else {
            remaining = duration
        }
    }
    
    var ss: String {
        let tenth = Int(ceil(remaining * 10))
        return String(format: "%02d.%d", tenth/10, tenth%10)
    }
}

// =============== 低レイテンシ ブザー ===============
final class Sounder {
    private var player: AVAudioPlayer?
    private var systemSoundID: SystemSoundID = 0
    
    init() {
        // SystemSound を先に準備（超低レイテンシ）
        if let url = Bundle.main.url(forResource: "buzzer", withExtension: "wav") {
            let cfurl = url as CFURL
            AudioServicesCreateSystemSoundID(cfurl, &systemSoundID)
        }
        // フォールバック用にAVAudioSessionを用意
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        if let url = Bundle.main.url(forResource: "buzzer", withExtension: "wav") {
            player = try? AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay() // 事前デコード
        }
    }
    
    deinit {
        if systemSoundID != 0 {
            AudioServicesDisposeSystemSoundID(systemSoundID)
        }
    }
    
    func playBuzzer() {
        if systemSoundID != 0 {
            AudioServicesPlaySystemSound(systemSoundID) // 最速
            return
        }
        player?.stop()
        player?.currentTime = 0
        player?.play()
    }
}

// ================= UI 共通パーツ =================
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, danger }
    var kind: Kind = .primary
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(background)
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(configuration.isPressed ? 0.05 : 0.15),
                    radius: configuration.isPressed ? 2 : 8, y: configuration.isPressed ? 1 : 4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
    private var background: some ShapeStyle {
        switch kind {
        case .primary:   LinearGradient(colors: [.accentColor, .accentColor.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .secondary: LinearGradient(colors: [.gray, .gray.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .danger:    LinearGradient(colors: [.red, .red.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

struct Card<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.subheadline).bold().foregroundStyle(.secondary)
            content
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.06)))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }
}

@ViewBuilder
func SmallChip(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title).font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 6)
    }
    .background(Color.gray.opacity(0.15), in: Capsule())
}

// 視認性の高いカウンター
struct BoldCounter: View {
    let title: String
    let tint: Color
    @Binding var value: Int
    let max: Int
    
    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                CircleButton(symbol: "minus", tint: .gray) {
                    if value > 0 { value -= 1 }
                }
                Text("\(value)")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 50, minHeight: 40)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.08)))
                CircleButton(symbol: "plus", tint: tint) {
                    if value < max { value += 1 }
                }
            }
        }
    }
}

struct CircleButton: View {
    let symbol: String
    let tint: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .frame(width: 36, height: 36)
        }
        .background(tint.gradient, in: Circle())
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }
}

struct TeamControlView: View {
    let name: String
    let color: Color
    @Binding var fouls: Int
    @Binding var timeouts: Int
    
    var body: some View {
        VStack(spacing: 8) {
            Text(name).font(.subheadline.bold()).foregroundStyle(color)
            BoldCounter(title: "ファウル", tint: .red, value: $fouls, max: 5)
            BoldCounter(title: "タイムアウト", tint: .blue, value: $timeouts, max: 6)
        }
        .frame(maxWidth: .infinity)
    }
}

// Binding<[T]> の index を安全に取り出すヘルパー
func binding<T>(_ array: Binding<[T]>, _ index: Int, default def: T) -> Binding<T> {
    Binding<T>(
        get: {
            if index < array.wrappedValue.count { return array.wrappedValue[index] }
            return def
        },
        set: { newVal in
            if index >= array.wrappedValue.count {
                array.wrappedValue.append(contentsOf: Array(repeating: def, count: index - array.wrappedValue.count + 1))
            }
            array.wrappedValue[index] = newVal
        }
    )
}

// ゲームモード設定
enum GameMode: String, CaseIterable {
    case miniBasket = "ミニバス"
    case juniorHigh = "中学生"
    case pro = "プロ"
    
    var quarterMinutes: Int {
        switch self {
        case .miniBasket: return 6
        case .juniorHigh: return 8
        case .pro: return 10
        }
    }
    
    var overtimeMinutes: Int {
        switch self {
        case .miniBasket: return 3
        case .juniorHigh: return 4
        case .pro: return 5
        }
    }
}

// ================ 画面本体（はみ出し対策つき） ================
struct ContentView: View {
    // ゲームモード
    @State private var gameMode: GameMode = .pro
    
    // タイマー
    @StateObject private var game = Clock(seconds: 10 * 60)
    @StateObject private var shot = ShotClock(seconds: 24)
    @State private var keepAwake = true
    private let sounder = Sounder()
    
    // Q管理（0-based）
    @State private var currentQ = 0
    @State private var foulsHome: [Int] = Array(repeating: 0, count: 4)
    @State private var foulsAway: [Int] = Array(repeating: 0, count: 4)
    @State private var toHome:    [Int] = Array(repeating: 0, count: 4)
    @State private var toAway:    [Int] = Array(repeating: 0, count: 4)
    
    // 編集シート
    enum EditorMode { case gameClock, shotClock }
    @State private var showEditor = false
    @State private var editorMode: EditorMode = .gameClock
    @State private var editMinutes = 10
    @State private var editSeconds = 0
    @State private var editShotSeconds = 24
    
    // リセット確認アラート
    @State private var showResetAlert = false
    
    var body: some View {
        GeometryReader { geo in
            // 横幅に応じて大きさを自動調整
            let w = geo.size.width
            let safePadding: CGFloat = 16
            let availableWidth = max(w - safePadding * 2, 0)
            let preferredWidth = min(w * 0.88, 560)
            let contentWidth = max(min(availableWidth, preferredWidth), 0)
            let baseWidth = max(contentWidth, min(w, 640))
            let gameFont = max(48, min(88, baseWidth * 0.18))      // 画面幅に比例
            let ringSize = max(110, min(160, baseWidth * 0.38))    // はみ出し防止
            let ringInnerWidth = max(ringSize - 36, 72)
            
            ZStack(alignment: .bottomTrailing) {
                Color(UIColor.systemGray6).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 16) {
                        Text("Basket Timer")
                            .font(.title.bold())
                            .padding(.top, 8)
                        
                        // === モード選択 ===
                        Card("試合モード") {
                            Picker("モード", selection: $gameMode) {
                                ForEach(GameMode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .onChange(of: gameMode) { newMode in
                            game.reset(to: TimeInterval(newMode.quarterMinutes * 60))
                        }
                        
                        // === Game Clock ===
                        Card("Game Clock") {
                            VStack(spacing: 10) {
                                // 時間表示：一時停止中のみタップで編集
                                Button {
                                    guard !game.isRunning else { return }
                                    editorMode = .gameClock
                                    // 表示されている「残り時間」から初期値をセット
                                    let total = Int(game.remaining.rounded(.up))
                                    editMinutes = total / 60
                                    editSeconds = total % 60
                                    showEditor = true
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(game.mmss)
                                            .font(.system(size: gameFont, weight: .black, design: .rounded))
                                            .monospacedDigit()
                                            .minimumScaleFactor(0.5)
                                            .foregroundStyle(.primary)
                                        if !game.isRunning {
                                            Text("タップで時間変更（停止中）")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.plain)
                                
                                HStack(spacing: 10) {
                                    Button(game.isRunning ? "一時停止" : "開始") {
                                        if game.isRunning { game.stop(); shot.stop() }
                                        else { game.start() }
                                    }.buttonStyle(PillButtonStyle(kind: .primary))
                                    
                                    Button("リセット") { 
                                        game.reset(to: TimeInterval(gameMode.quarterMinutes * 60))
                                    }
                                    .buttonStyle(PillButtonStyle(kind: .secondary))
                                    
                                    // OTはワンタップ（秒数ボタンは撤去）
                                    SmallChip("+OT \(gameMode.overtimeMinutes):00") { addOvertime() }
                                }
                            }
                        }
                        
                        // === Shot Clock ===
                        Card("Shot Clock") {
                            VStack(spacing: 12) {
                                Button {
                                    guard !shot.isRunning else { return }
                                    editorMode = .shotClock
                                    editShotSeconds = max(1, Int(shot.remaining.rounded(.up))) // 表示から開始
                                    showEditor = true
                                } label: {
                                    ZStack {
                                        // 余白を広げて数字とリングの距離を確保
                                        Circle()
                                            .trim(from: 0, to: CGFloat(max(0, shot.remaining / max(shot.duration, 0.01))))
                                            .stroke(style: StrokeStyle(lineWidth: 12, lineCap: .round))
                                            .foregroundStyle(shot.remaining <= 3 ? Color.red : Color.accentColor)
                                            .rotationEffect(.degrees(-90))
                                            .frame(width: ringSize, height: ringSize)
                                        VStack(spacing: 8) {
                                            Text(shot.ss)
                                                .font(.system(size: max(36, ringSize * 0.36), weight: .heavy, design: .rounded))
                                                .monospacedDigit()
                                                .minimumScaleFactor(0.5)
                                                .lineLimit(1)
                                                .frame(width: ringInnerWidth)
                                                .multilineTextAlignment(.center)
                                                .foregroundStyle(shot.remaining <= 3 ? .red : .primary)
                                            if !shot.isRunning {
                                                Text("タップで秒数変更\n（停止中）")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .frame(width: ringInnerWidth)
                                                    .multilineTextAlignment(.center)
                                            }

                                        }
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 4)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.plain)
                                
                                HStack(spacing: 10) {
                                    Button(shot.isRunning ? "停止" : "開始") {
                                        shot.isRunning ? shot.stop() : shot.start()
                                    }.buttonStyle(PillButtonStyle(kind: .primary))
                                    
                                    Button("24秒") { shot.reset(24) }
                                        .buttonStyle(PillButtonStyle(kind: .secondary))
                                    Button("14秒") { shot.reset(14) }
                                        .buttonStyle(PillButtonStyle(kind: .secondary))
                                }
                            }
                        }
                        
                        // === Game Control（Q別＋合計、見やすい数値） ===
                        Card("Game Control") {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("クォーター:  Q\(currentQ + 1)").font(.headline)
                                    Spacer()
                                    HStack(spacing: 8) {
                                        SmallChip("Prev") { if currentQ > 0 { currentQ -= 1 } }
                                        SmallChip("Next") { nextQuarter() }
                                    }
                                }
                                
                                HStack(spacing: 12) {
                                    TeamControlView(
                                        name: "HOME", color: .red,
                                        fouls: binding($foulsHome, currentQ, default: 0),
                                        timeouts: binding($toHome, currentQ, default: 0)
                                    )
                                    TeamControlView(
                                        name: "AWAY", color: .blue,
                                        fouls: binding($foulsAway, currentQ, default: 0),
                                        timeouts: binding($toAway, currentQ, default: 0)
                                    )
                                }
                            }
                        }
                        
                        // === オプション ===
                        Card("オプション") {
                            VStack(spacing: 12) {
                                Toggle("自動ロックを無効にする", isOn: $keepAwake)
                                    .onChange(of: keepAwake) { on in UIApplication.shared.isIdleTimerDisabled = on }
                                Text("試合中に画面が暗くならない／ロックされないようにします。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                Divider()
                                
                                Button("全体をリセット") {
                                    showResetAlert = true
                                }
                                .buttonStyle(PillButtonStyle(kind: .danger))
                            }
                        }
                        
                        Spacer(minLength: 8)
                    }
                    .frame(maxWidth: contentWidth, alignment: .center)
                    .padding(.horizontal, safePadding)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity)
                }
                
                // フローティングブザーボタン
                Button(action: {
                    sounder.playBuzzer()
                }) {
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 70, height: 70)
                        .background(
                            LinearGradient(
                                colors: [.orange, .red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Circle()
                        )
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
            .onChange(of: game.remaining) { newVal in if newVal == 0 { sounder.playBuzzer() } }
            .onChange(of: shot.remaining) { newVal in if newVal == 0 { sounder.playBuzzer() } }
            .onAppear { UIApplication.shared.isIdleTimerDisabled = keepAwake }
            .alert("全体をリセット", isPresented: $showResetAlert) {
                Button("キャンセル", role: .cancel) { }
                Button("リセット", role: .destructive) {
                    resetAll()
                }
            } message: {
                Text("全ての設定とカウンタをリセットします。よろしいですか？")
            }
            .sheet(isPresented: $showEditor) {
                switch editorMode {
                case .gameClock:
                    VStack(spacing: 16) {
                        Text("試合時間を設定").font(.headline).padding(.top, 16)
                        HStack(spacing: 24) {
                            Picker("分", selection: $editMinutes) {
                                ForEach(0..<20) { Text("\($0) 分") }
                            }
                            Picker("秒", selection: $editSeconds) {
                                ForEach(0..<60) { Text("\($0) 秒") }
                            }
                        }
                        .labelsHidden().pickerStyle(.wheel).frame(height: 160)
                        
                        HStack(spacing: 12) {
                            Button("キャンセル") { showEditor = false }
                                .buttonStyle(PillButtonStyle(kind: .secondary))
                            Button("適用") {
                                let total = editMinutes * 60 + editSeconds
                                game.reset(to: TimeInterval(total))
                                showEditor = false
                            }
                            .buttonStyle(PillButtonStyle(kind: .primary))
                        }
                        .padding(.bottom, 16)
                    }
                    .presentationDetents([.height(320)])
                    .presentationDragIndicator(.visible)
                    
                case .shotClock:
                    VStack(spacing: 16) {
                        Text("ショットクロックを設定").font(.headline).padding(.top, 16)
                        Picker("秒", selection: $editShotSeconds) {
                            ForEach(1...35, id: \.self) { Text("\($0) 秒") }
                        }
                        .labelsHidden()
                        .pickerStyle(.wheel)
                        .frame(height: 160)
                        
                        HStack(spacing: 12) {
                            Button("キャンセル") { showEditor = false }
                                .buttonStyle(PillButtonStyle(kind: .secondary))
                            Button("適用") {
                                shot.reset(TimeInterval(editShotSeconds))
                                showEditor = false
                            }
                            .buttonStyle(PillButtonStyle(kind: .primary))
                        }
                        .padding(.bottom, 16)
                    }
                    .presentationDetents([.height(300)])
                    .presentationDragIndicator(.visible)
                }
            }
        }
    }
    
    // ===== util =====
    private func secondsToMinSec(_ s: Int) -> (Int, Int) { (s/60, s%60) }
    
    private func nextQuarter() {
        currentQ += 1
        let need = currentQ + 1
        if foulsHome.count < need {
            foulsHome.append(0); foulsAway.append(0)
            toHome.append(0);    toAway.append(0)
        }
    }
    
    private func addOvertime() {
        nextQuarter()
        game.reset(to: TimeInterval(gameMode.overtimeMinutes * 60))
    }
    
    private func resetAll() {
        // タイマーを初期状態に
        game.reset(to: TimeInterval(gameMode.quarterMinutes * 60))
        shot.reset(24)
        
        // クォーターとカウンタを初期化
        currentQ = 0
        foulsHome = Array(repeating: 0, count: 4)
        foulsAway = Array(repeating: 0, count: 4)
        toHome = Array(repeating: 0, count: 4)
        toAway = Array(repeating: 0, count: 4)
    }
}

#Preview { ContentView() }
