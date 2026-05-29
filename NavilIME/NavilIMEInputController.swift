//
//  NavilIMEInputController.swift
//  NavilIME
//
//  Created by Manwoo Yi on 9/4/22.
//

import InputMethodKit

@objc(NavilIMEInputController)
open class NavilIMEInputController: IMKInputController {
    let key_code:String =       "asdfhgzxcv\tbqweryt123465=97-80]ou[ip\tlj'k;\\,/nm.\t `"
    let shift_key_code:String = "ASDFHGZXCV\tBQWERYT!@#$^%+(&_*)}OU{IP\tLJ\"K:|<?NM>\t ~"
    
    var hangul:Hangul!
    // 멀티키 시퀀스 감지 카운터 (C-x p p 등 처리)
    var commandKeyCount: Int = 0
    
    override open func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        commandKeyCount = 0
        self.hangul = Hangul()
        self.hangul.Start(type: HangulMenu.shared.selected_keyboard)
        

    }

    override open func deactivateServer(_ sender: Any!) {
        super.deactivateServer(sender)
        self.hangul.Flush()
        self.update_display(client: sender)
        self.hangul.Stop()
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
            commandKeyCount = 0
            self.hangul.ToggleSuspend()
            self.commitComposition(sender)
            return true
        }

        if HanjaController.shared.isVisible {
            switch event.keyCode {
            case 0x7B, 0x7C, 0x7D, 0x7E:
                HanjaController.shared.handleKey(event: event)
                return true
            case 0x24, 0x4C:
                HanjaController.shared.handleKey(event: event)
                return true
            case 0x35:
                HanjaController.shared.hide()
                return true
            default:
                HanjaController.shared.hide()
                return true
            }
        }
        
        switch event.type {
        case .keyDown:
            let eaten = self.keydown_event_handler(event: event, client: sender)
            if eaten == false {
                self.commitComposition(sender)
            }
            return eaten
        case .flagsChanged:
            // 수식키(Ctrl, Cmd, Option) 눌릴 때 멀티키 시퀀스 카운트 증가
            if let client = sender as? IMKTextInput,
               let bundleID = client.bundleIdentifier(),
               bundleID == "org.gnu.Emacs" {
                let flag = event.modifierFlags
                if flag.contains(.control) || flag.contains(.command) || flag.contains(.option) {
                    if commandKeyCount == 0 {
                        // 처음 수식키 누를 때 조합 중인 글자 확정
                        self.hangul.Flush()
                        self.update_display(client: sender)
                    }
                    commandKeyCount += 1
                }
            }
            return false
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            commandKeyCount = 0
            self.commitComposition(sender)
        default:
            break
        }
        return false
    }
    
    func keydown_event_handler(event:NSEvent, client:Any!) -> Bool {
        let keycode = event.keyCode
        let flag = event.modifierFlags
        
        Hotfix.shared.add(keycode)
        let is_matched = Hotfix.shared.check()
        if is_matched == true {
            return false
        }
        
        if flag.contains(.command) || flag.contains(.option) || flag.contains(.control) {
            if let client = client as? IMKTextInput,
               let bundleID = client.bundleIdentifier(),
               bundleID == "org.gnu.Emacs" {
                if commandKeyCount == 0 {
                    self.hangul.Flush()
                    self.update_display(client: client)
                }
                commandKeyCount += 1
            }
            return false
        }
        
        // commandKeyCount > 0 이면 멀티키 시퀀스 진행 중 → 한글 처리 안 함
        if commandKeyCount > 0 {
            if let client = client as? IMKTextInput,
               let bundleID = client.bundleIdentifier(),
               bundleID == "org.gnu.Emacs" {
                commandKeyCount += 1
                return false
            } else {
                commandKeyCount = 0
            }
        }
        
        let enter_return = 0x24
        let tab = 0x30
        if keycode == enter_return || keycode == tab {
            self.hangul.Flush()
            self.update_display(client: client)
            return false
        }
        
        let backspace = 0x33
        if keycode == backspace {
            let remain = self.hangul.Backspace()
            if remain == true {
                self.update_display(client: client, backspace: true)
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

            let targetStr: String
            let preeditMode: Bool
            if !preeditStr.isEmpty {
                targetStr = preeditStr
                preeditMode = true
            } else {
                self.hangul.Flush()
                self.update_display(client: client)
                targetStr = self.hangul.lastCommitted
                preeditMode = false
            }

            guard !targetStr.isEmpty, let scalar = targetStr.unicodeScalars.last else {
                return false
            }
            return HanjaController.shared.handleScalar(
                scalar: scalar,
                preeditMode: preeditMode,
                client: imkClient)
        }
        
        if keycode >= self.key_code.count {
            self.hangul.Flush()
            self.update_display(client: client)
            return false
        }
        
        let ascii_idx = self.key_code.index(self.key_code.startIndex, offsetBy: Int(keycode))
        var ascii = self.key_code[ascii_idx]
        let shift:Bool = flag.contains(.shift)
        if shift == true {
            ascii = self.shift_key_code[ascii_idx]
        }
        
        commandKeyCount = 0
        let is_hangul:Bool = self.hangul.Process(ascii: String(ascii))
        if is_hangul == false {
            self.hangul.Flush()
            var extra:String = String(ascii)
            if let etc = hangul.Additional(ascii: String(ascii)) {
                extra = etc
            }
            self.update_display(client: client, backspace: false, additional: extra)
        } else {
            self.update_display(client: client)
        }
        return true
    }
    
    func update_display(client:Any!, backspace:Bool = false, additional:String = "") {
        let commit_unicode:[unichar] = self.hangul.GetCommit()
        let preedit_unicode:[unichar] = self.hangul.GetPreedit()
        var commited:String = String(utf16CodeUnits:commit_unicode, count: commit_unicode.count)
        let preediting:String = String(utf16CodeUnits: preedit_unicode, count: preedit_unicode.count)
        
        guard let disp = client as? IMKTextInput else { return }
        
        commited += additional
        
        if commited.count != 0 {
            disp.insertText(commited, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        }
        
        if (preediting.count != 0) || (backspace == true) {
            let sr = NSRange(location: 0, length: preediting.count)
            let rr = NSRange(location: NSNotFound, length: NSNotFound)
            disp.setMarkedText(preediting, selectionRange: sr, replacementRange: rr)
        }
    }
    
    override open func commitComposition(_ sender: Any!) {
        self.hangul.Flush()
        self.update_display(client: sender)
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

    @objc func select_menu(_ sender:Any?) {
        guard let menuitem = sender as? Dictionary<String, Any> else { return }
        if let kbd:NSMenuItem = menuitem["IMKCommandMenuItem"] as? NSMenuItem {
            if kbd.tag == OptHandler.shared.opt_menu_tag {
                self.hangul.Flush()
                OptHandler.shared.Open_opt_window(sender)
                return
            }
            HangulMenu.shared.change_selected_keyboard(id: kbd.tag)
            for mi in HangulMenu.shared.menu.items {
                mi.state = NSControl.StateValue.off
            }
            kbd.state = NSControl.StateValue.on
            self.hangul.Flush()
            self.hangul.Stop()
            self.hangul.Start(type: HangulMenu.shared.selected_keyboard)
        }
    }
}