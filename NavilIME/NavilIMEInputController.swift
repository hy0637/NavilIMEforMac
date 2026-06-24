//
//  NavilIMEInputController.swift
//  NavilIME
//
//  Created by Manwoo Yi on 9/4/22.
//  
//  ============================================================
//  Emacs 통합 전략 (2026-06)
//  Emacs 활성화 시 시스템 입력기를 영어(ASCII 호환)로 전환 → NavilIME 완전 비활성화
//  Emacs 내부 한글 입력은 사용자 Emacs 설정에 따름 (예: hy-hangul.el)
//  다른 앱에서는 NavilIME가 한글 입력 담당
//  ============================================================
//
import InputMethodKit

// MARK: - TIS(Text Input Services) Swift 확장
extension TISInputSource {
    var id: String? {
        guard let property = TISGetInputSourceProperty(self, "kTISPropertyInputSourceID" as CFString) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(property).takeUnretainedValue() as String
    }
    
    func select() {
        TISSelectInputSource(self)
    }
}

@objc(NavilIMEInputController)
open class NavilIMEInputController: IMKInputController {
    let _keyCode: String =       "asdfhgzxcv\tbqweryt123465=97-80]ou[ip\tlj'k;\\,/nm.\t `"
    let _shiftKeyCode: String = "ASDFHGZXCV\tBQWERYT!@#$^%+(&_*)}OU{IP\tLJ\"K:|<?NM>\t ~"
    
    var hangul: Hangul!
    
    override open func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        self.hangul = Hangul()
        self.hangul.Start(type: HangulMenu.shared.selected_keyboard)
        
        guard let client = sender as? IMKTextInput else { return }
        
        // Emacs 활성화 시 ASCII 호환 입력기(ABC, Dvorak 등)로 전환 → NavilIME 완전 비활성화
        if let bundleID = client.bundleIdentifier(), bundleID == "org.gnu.Emacs" { //
            if let currentASCIISource = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue() {
                currentASCIISource.select()
            } else {
                let properties = ["kTISPropertyInputSourceID" as CFString: "com.apple.keylayout.ABC" as CFString] as CFDictionary
                if let sourceList = TISCreateInputSourceList(properties, true)?.takeRetainedValue() as? [TISInputSource],
                   let abcSource = sourceList.first {
                    abcSource.select()
                }
            }
            return
        }
        
        // [개선 포인트 1] 일반 앱 진입 직후, OS 단에서 입력기 자판 소스가 일시적으로 뒤엉키는 것을 차단
        // 깨어나는 순간 클라이언트의 키보드 레이아웃 상태를 명시적으로 재설정합니다.
        self.synchronizeKeyboardLayout(client: client)
    }

    override open func deactivateServer(_ sender: Any!) {
        // [개선 포인트 2] 포커스를 잃고 떠나기 전, 기존 타이핑 상태 마감을 super보다 "먼저" 수행
        if self.hangul != nil {
            self.hangul.Flush()
        }
        self.updateDisplay(client: sender)
        
        // 클라이언트 텍스트 뷰에 빈 마크 문자를 임시 삽입하여 OS 입력 큐에 잔존하는 이벤트를 강제로 밀어내기(Flush) 함
        if let client = sender as? IMKTextInput {
            client.insertText("", replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        }
        
        if self.hangul != nil {
            self.hangul.Stop()
        }
        
        // 모든 잔여 버퍼 청소가 끝난 후 부모 서버 비활성화 호출
        super.deactivateServer(sender)
    }
    
    // macOS가 activateServer 없이 handle을 호출하는 경우 대비
    func ensureHangulReady() {
        if self.hangul == nil {
            self.hangul = Hangul()
        }
        if self.hangul?.automata == nil {
            self.hangul?.Start(type: HangulMenu.shared.selected_keyboard)
        }
    }

    override open func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        self.ensureHangulReady()
        if OptHandler.shared.Is_han_eng_changed(keycode: event.keyCode, modi: event.modifierFlags) {
            self.hangul.ToggleSuspend()
            self.commitComposition(sender)
            return true
        }

        if HanjaController.shared.isVisible {
            switch event.keyCode {
            case 0x7B, 0x7C, 0x7D, 0x7E: // 방향키
                HanjaController.shared.handleKey(event: event)
                return true
            case 0x24, 0x4C: // Enter, Return
                HanjaController.shared.handleKey(event: event)
                return true
            case 0x35: // Escape
                HanjaController.shared.hide()
                return true
            default:
                HanjaController.shared.hide()
                return true
            }
        }
        
        switch event.type {
        case .keyDown:
            let eaten = self.keydownEventHandler(event: event, client: sender)
            if !eaten {
                self.commitComposition(sender)
            }
            return eaten
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            self.commitComposition(sender)
        default:
            break
        }
        return false
    }
    
    func keydownEventHandler(event: NSEvent, client: Any!) -> Bool {
        let keycode = event.keyCode
        let flag = event.modifierFlags
        
        Hotfix.shared.add(keycode)
        let isMatched = Hotfix.shared.check()
        if isMatched {
            return false
        }
        
        if flag.contains(.command) || flag.contains(.option) || flag.contains(.control) {
            return false
        }
        
        let enterReturn = 0x24
        let tab = 0x30
        if Int(keycode) == enterReturn || Int(keycode) == tab {
            self.hangul.Flush()
            self.updateDisplay(client: client)
            return false
        }
        
        let backspace = 0x33
        if Int(keycode) == backspace {
            let remain = self.hangul.Backspace()
            if remain {
                self.updateDisplay(client: client, backspace: true)
            }
            return remain
        }


        // F9 → 한자/기호 변환
        if event.keyCode == 0x65 {
            if !HanjaController.shared.isReady,
               let delegate = NSApp.delegate as? AppDelegate {
                HanjaController.shared.setup(server: delegate.server)
            }
            if HanjaController.shared.isVisible {
                HanjaController.shared.hide()
                return true
            }
            let imkClient = client as! IMKTextInput
            let preeditStr = self.hangul.currentPreedit

            var targetStr: String = ""
            var preeditMode: Bool = true
            var replacementRange = NSRange(location: NSNotFound, length: NSNotFound)

            // Case 1: 현재 글자를 입력 중인 상태 (조합 중 preedit)
            if !preeditStr.isEmpty {
                targetStr = preeditStr
                preeditMode = true
            } 
            // Case 2: [hy-hangul 스타일] 이미 입력이 완료되어 커서 왼쪽에 글자가 있는 경우
            else {
                self.hangul.Flush()
                self.updateDisplay(client: client)
                
                // 현재 텍스트 뷰의 커서 선택 영역을 획득
                let selectedRange = imkClient.selectedRange()
                
                // 커서 바로 앞 1글자의 위치 범위를 계산 (위치가 유효하고 커서가 맨 앞이 아닐 때)
                if selectedRange.location != NSNotFound && selectedRange.location > 0 {
                    let targetRange = NSRange(location: selectedRange.location - 1, length: 1)
                    
                    // 클라이언트 앱으로부터 커서 앞 딱 1글자의 속성 문자열을 가져옴
                    if let attributedStr = imkClient.attributedSubstring(from: targetRange) {
                        targetStr = attributedStr.string
                        preeditMode = false
                        replacementRange = targetRange // 한자 선택 시 덮어쓸 주소 지정
                    }
                }
                
                // 만약 앱에서 문자열 획득을 지원하지 않는 경우, 입력기 내부 버퍼폴백을 사용
                if targetStr.isEmpty {
                    targetStr = self.hangul.lastCommitted
                    preeditMode = false
                }
            }

            guard !targetStr.isEmpty, let scalar = targetStr.unicodeScalars.last else {
                return false
            }
            
            // 보강된 HanjaController로 주소값(replacementRange)과 함께 스칼라 전달
            return HanjaController.shared.handleScalar(
                scalar: scalar,
                preeditMode: preeditMode,
                client: imkClient,
                replacementRange: replacementRange)
        }
	        
        if Int(keycode) >= self._keyCode.count {
            self.hangul.Flush()
            self.updateDisplay(client: client)
            return false
        }
        
        let asciiIdx = self._keyCode.index(self._keyCode.startIndex, offsetBy: Int(keycode))
        var ascii = self._keyCode[asciiIdx]
        let isShift = flag.contains(.shift)
        if isShift {
            ascii = self._shiftKeyCode[asciiIdx]
        }
        
        let isHangul = self.hangul.Process(ascii: String(ascii))
        if !isHangul {
            self.hangul.Flush()
            var extra = String(ascii)
            if let etc = hangul.Additional(ascii: String(ascii)) {
                extra = etc
            }
            self.updateDisplay(client: client, backspace: false, additional: extra)
        } else {
            self.updateDisplay(client: client)
        }
        return true
    }
    
    func updateDisplay(client: Any!, backspace: Bool = false, additional: String = "") {
        let commitUnicode = self.hangul.GetCommit()
        let preeditUnicode = self.hangul.GetPreedit()
        var committed = String(utf16CodeUnits: commitUnicode, count: commitUnicode.count)
        let preediting = String(utf16CodeUnits: preeditUnicode, count: preeditUnicode.count)
        
        guard let disp = client as? IMKTextInput else { return }
        
        committed += additional
        
        if !committed.isEmpty {
            disp.insertText(committed, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        }
        
        if !preediting.isEmpty || backspace {
            let sr = NSRange(location: 0, length: preediting.count)
            let rr = NSRange(location: NSNotFound, length: NSNotFound)
            disp.setMarkedText(preediting, selectionRange: sr, replacementRange: rr)
        }
    }
    
    // 포커스 혹은 상태 태그 변경 시 호출 (기존 구름입력기 방식 핫픽스 유지 + 동기화 일원화)
    override open func setValue(_ value: Any!, forTag tag: Int, client sender: Any!) {
        if let client = sender as? IMKTextInput {
            self.synchronizeKeyboardLayout(client: client)
        }
        super.setValue(value, forTag: tag, client: sender)
    }

    // [개선 포인트 3] 키보드 오버라이드 로직의 안전한 공통 함수화
    // 시스템 런타임에서 유저의 ASCII 자판 상태를 안전하게 추출하여 클라이언트에 덮어씌웁니다.
    private func synchronizeKeyboardLayout(client: IMKTextInput) {
        if let currentASCIISource = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
           let sourceID = currentASCIISource.id {
            client.overrideKeyboard(withKeyboardNamed: sourceID)
        } else {
            client.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")
        }
    }

    override open func commitComposition(_ sender: Any!) {
        self.hangul.Flush()
        self.updateDisplay(client: sender)
    }
    
    override open func recognizedEvents(_ sender: Any!) -> Int {
        return Int(NSEvent.EventTypeMask(arrayLiteral: .keyDown, .flagsChanged,
            .leftMouseUp, .rightMouseUp, .leftMouseDown, .rightMouseDown,
            .leftMouseDragged, .rightMouseDragged,
            .appKitDefined, .applicationDefined, .systemDefined).rawValue)
    }
    
    override open func mouseDown(onCharacterIndex index: Int, coordinate point: NSPoint, withModifier flags: Int, continueTracking keepTracking: UnsafeMutablePointer<ObjCBool>!, client sender: Any!) -> Bool {
        if HanjaController.shared.isVisible {
            HanjaController.shared.hide()
        }
        self.commitComposition(sender)
        return false
    }
    
    override open func menu() -> NSMenu! {
        return HangulMenu.shared.menu
    }
    
    override open func candidates(_ sender: Any!) -> [Any]! {
        let count = HanjaController.shared.candidatesCount()
        return (0..<count).map { HanjaController.shared.candidate(at: $0) }
    }

    override open func candidateSelected(_ candidateString: NSAttributedString!) {
        guard let client = self.client() as? IMKTextInput else { return }
        self.hangul.clearState()
        HanjaController.shared.select(candidate: candidateString.string, client: client)
    }

    override open func candidateSelectionChanged(_ candidateString: NSAttributedString!) {}

    @objc func select_menu(_ sender: Any?) {
        guard let menuitem = sender as? Dictionary<String, Any> else { return }
        if let kbd = menuitem["IMKCommandMenuItem"] as? NSMenuItem {
            if kbd.tag == OptHandler.shared.opt_menu_tag {
                self.hangul.Flush()
                OptHandler.shared.Open_opt_window(sender)
                return
            }
            HangulMenu.shared.change_selected_keyboard(id: kbd.tag)
            for mi in HangulMenu.shared.menu.items {
                mi.state = .off
            }
            kbd.state = .on
            self.hangul.Flush()
            self.hangul.Stop()
            self.hangul.Start(type: HangulMenu.shared.selected_keyboard)
        }
    }
}