//
//  HanjaController.swift
//  NavilIME
//

import InputMethodKit
import Foundation

class HanjaController {
    static let shared = HanjaController()

    private var candidates: IMKCandidates?
    private var currentCandidates: [HanjaCandidate] = []
    private var isPreeditMode: Bool = false
    private var currentPage: Int = 0
    
    // [보강] 이미 입력된 글자를 변환할 때 해당 글자의 정확한 앱 내 위치 범위를 기억하기 위한 프로퍼티
    private var targetRange: NSRange = NSRange(location: NSNotFound, length: NSNotFound)

    // 3분 후 메모리 해제 타이머
    private var releaseTimer: Timer?
    private let releaseDelay: TimeInterval = 180

    private init() {}

    var isReady: Bool = false

    func setup(server: IMKServer) {
        if isReady {
            // 이미 초기화됨 - 타이머만 리셋
            resetReleaseTimer()
            return
        }
        self.candidates = IMKCandidates(server: server,
                                        panelType: kIMKSingleColumnScrollingCandidatePanel)
        self.candidates?.setDismissesAutomatically(true)
        isReady = true
        resetReleaseTimer()
        PrintLog.shared.Log(log: "HanjaController: setup done (lazy)")
    }

    private func resetReleaseTimer() {
        releaseTimer?.invalidate()
        releaseTimer = Timer.scheduledTimer(withTimeInterval: releaseDelay, repeats: false) { [weak self] _ in
            self?.releaseFromMemory()
        }
        PrintLog.shared.Log(log: "HanjaController: release timer reset (3min)")
    }

    private func releaseFromMemory() {
        candidates?.hide()
        candidates = nil
        currentCandidates = []
        isPreeditMode = false
        currentPage = 0
        isReady = false
        releaseTimer = nil
        targetRange = NSRange(location: NSNotFound, length: NSNotFound)
        PrintLog.shared.Log(log: "HanjaController: released from memory after 3min")
    }

    func hide() {
        candidates?.hide()
        currentCandidates = []
        isPreeditMode = false
        currentPage = 0
        targetRange = NSRange(location: NSNotFound, length: NSNotFound)
        PrintLog.shared.Log(log: "HanjaController: hidden")
    }

    var isVisible: Bool {
        return !currentCandidates.isEmpty
    }

    func handleKey(event: NSEvent) {
        if event.keyCode == 0x7D {
            let maxPage = (currentCandidates.count - 1) / 10
            if currentPage < maxPage { currentPage += 1 }
        } else if event.keyCode == 0x7E {
            if currentPage > 0 { currentPage -= 1 }
        }
        PrintLog.shared.Log(log: "HanjaController: handleKey keycode=\(event.keyCode) currentPage=\(currentPage)")
        candidates?.interpretKeyEvents([event])
    }

    // [보강] replacementRange 매개변수를 추가하여 커서 앞 글자 범위를 입력받을 수 있도록 확장
    func handleScalar(scalar: Unicode.Scalar, preeditMode: Bool, client: IMKTextInput, replacementRange: NSRange = NSRange(location: NSNotFound, length: NSNotFound)) -> Bool {
        self.isPreeditMode = preeditMode
        self.currentPage = 0
        self.targetRange = replacementRange // 전달받은 범위를 저장
        PrintLog.shared.Log(log: "HanjaController: handleScalar U+\(String(format: "%04X", scalar.value)) preeditMode=\(preeditMode) range=\(replacementRange)")

        let found = HanjaTable.shared.candidates(for: scalar)
        PrintLog.shared.Log(log: "HanjaController: candidates count = \(found.count)")
        guard !found.isEmpty else { return false }

        self.currentCandidates = found
        candidates?.update()
        candidates?.show(kIMKLocateCandidatesAboveHint)
        PrintLog.shared.Log(log: "HanjaController: candidates shown")
        return true
    }

    func candidatesCount() -> Int { return currentCandidates.count }

    func candidate(at index: Int) -> String {
        guard index < currentCandidates.count else { return "" }
        let c = currentCandidates[index]
        let ch = String(c.char)
        if c.meaning.isEmpty { return ch }
        return "\(ch)  \(c.meaning)"
    }

    func select(candidate: String, client: IMKTextInput) {
        guard let first = candidate.unicodeScalars.first else { return }
        let hanja = String(first)

        if isPreeditMode {
            // 글자를 타이핑 도중 변환하는 경우 (기존 유지)
            let emptyRange = NSRange(location: NSNotFound, length: NSNotFound)
            client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: emptyRange)
            client.insertText(hanja, replacementRange: emptyRange)
        } else {
            // [hy-hangul 스타일 변환] 이미 입력 완료된 커서 왼쪽 글자를 덮어쓰는 경우
            if self.targetRange.location != NSNotFound {
                // 저장해둔 정확한 1글자 범위를 지정하여 한자로 완전히 대체합니다.
                client.insertText(hanja, replacementRange: self.targetRange)
            } else {
                // 폴백 안전장치
                let range = client.selectedRange()
                if range.location != NSNotFound && range.location > 0 {
                    client.insertText(hanja, replacementRange: NSRange(location: range.location - 1, length: 1))
                } else {
                    client.insertText(hanja, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                }
            }
        }

        currentCandidates = []
        isPreeditMode = false
        currentPage = 0
        targetRange = NSRange(location: NSNotFound, length: NSNotFound)
        candidates?.hide()
        PrintLog.shared.Log(log: "HanjaController: selected \(hanja)")
    }
}