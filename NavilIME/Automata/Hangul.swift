//
//  Hangul.swift
//  automata
//
//  Created by Manwoo Yi on 9/10/22.
//  Modified by HY on 21/4/26

import Foundation

struct Composition {
    var chosung:String = ""
    var jungsung:String = ""
    var jongsung:String = ""
    var done:Bool = false
    
    var Size:UInt {
        return UInt(self.chosung.count + self.jungsung.count + self.jongsung.count)
    }
}

struct Automata {
    var current:[String]
    var keyboard:Keyboard
    
    init(kbd:Keyboard) {
        self.current = []
        self.keyboard = kbd
    }
    
    func chosung(comp: inout Composition, ch:String) {
        if comp.chosung == "" {
            comp.chosung = ch
        } else {
            if comp.jungsung != "" {
                comp.done = true
            } else {
                if self.keyboard.chosung_proc(comp: &comp, ch: ch) {
                    comp.chosung += ch
                } else {
                    comp.done = true
                }
            }
        }
    }

    func jungsung(comp:inout Composition, ch:String) {
        if comp.jungsung == "" {
            comp.jungsung = ch
        } else {
            if self.keyboard.jungsung_proc(comp: &comp, ch: ch) {
                comp.jungsung += ch
            } else {
                comp.done = true
            }
        }
    }

    func jongsung(comp: inout Composition, ch:String) {
        if comp.jongsung == "" {
            comp.jongsung = ch
        } else {
            if self.keyboard.jongsung_proc(comp: &comp, ch: ch) {
                comp.jongsung += ch
            } else {
                comp.done = true
            }
        }
    }

    mutating func consume(comp:Composition) {
        for _ in 0..<comp.Size {
            self.current.removeFirst()
        }
    }

    mutating func run() -> Composition{
        var comp:Composition = Composition()
        
        for ch in self.current {
            if self.keyboard.chosung_proc(comp: &comp, ch: ch) {
                self.chosung(comp: &comp, ch: ch)
            } else if self.keyboard.jungsung_proc(comp: &comp, ch: ch) {
                self.jungsung(comp: &comp, ch: ch)
            } else if self.keyboard.jongsung_proc(comp: &comp, ch: ch) {
                self.jongsung(comp:&comp, ch:ch)
            } else {
                comp.done = true
            }
            if comp.done {
                break
            }
        }
        if comp.done {
            self.consume(comp: comp)
        }
        return comp
    }
}

// 한글 입력 상태
enum HangulState {
    case hangul    // 한글 입력 중
    case english   // 영문 모드
    case sequence  // 멀티키 시퀀스 진행 중 (C-x p p 등)
}

class Hangul {
    var automata:Automata?
    var keyboard:Keyboard?
    var committed:[unichar]
    var preediting:[unichar]
    
    var debug_commit:[String]
    var debug_preedit:[String]
    
    // 입력 상태
    var state: HangulState = .hangul
    var previousState: HangulState = .hangul  // 시퀀스 종료 후 복귀용
    
    init() {
        self.committed  = []
        self.preediting = []
        self.debug_commit  = []
        self.debug_preedit = []
    }

    func set_commit(comp:Composition) {
        if let kbd = self.keyboard {
            self.committed += kbd.normalization(comp: comp, is_commit: true)
            let dbg = kbd.debugout(comp: comp)
            if dbg != "" {
                self.debug_commit.append(dbg)
            }
        }
    }

    func set_preedit(comp:Composition){
        if let kbd = self.keyboard {
            self.preediting += kbd.normalization(comp: comp, is_commit: false)
            currentPreedit = String(utf16CodeUnits: self.preediting, count: self.preediting.count)
            let dbg = kbd.debugout(comp: comp)
            if dbg != "" {
                self.debug_preedit.append(dbg)
            }
        }
    }
    
    func Stop() {
        self.keyboard = nil
        self.automata = nil
    }
    
    func ToggleSuspend() {
        if state == .hangul {
            state = .english
            HangulMenu.shared.self_eng_mode = true
            PrintLog.shared.Log(log: "영어")
        } else {
            state = .hangul
            HangulMenu.shared.self_eng_mode = false
            PrintLog.shared.Log(log: "한글")
        }
    }

    // 멀티키 시퀀스 시작 (C-x, C-c 등 수식키 입력 시)
    func EnterSequence() {
        if state != .sequence {
            previousState = state
            state = .sequence
            PrintLog.shared.Log(log: "EnterSequence: previousState=\(previousState)")
        }
    }

    // 멀티키 시퀀스 종료 → 이전 상태로 복귀
    func ExitSequence() {
        if state == .sequence {
            state = previousState
            // self_eng_mode도 이전 상태에 맞게 복원
            HangulMenu.shared.self_eng_mode = (state == .english)
            PrintLog.shared.Log(log: "ExitSequence: restored to \(state)")
        }
    }

    // 시퀀스 중인지 확인
    var isInSequence: Bool {
        return state == .sequence
    }
    
    static let hangul_keyboard:[Keyboard] = [
        Keyboard002()
    ]
    static func Get_keyboard002() -> Keyboard002? {
        return Hangul.hangul_keyboard[0] as? Keyboard002
    }
    
    func Start(type:Int) {
        self.keyboard = Hangul.hangul_keyboard[0]
        for k in Hangul.hangul_keyboard {
            if k.id == type {
                self.keyboard = k
            }
        }
        self.automata = Automata(kbd: self.keyboard!)
        self.state = .hangul
        self.previousState = .hangul
        HangulMenu.shared.self_eng_mode = false
    }

    func Process(ascii:String) -> Bool {
        // 영문 모드 또는 시퀀스 중 → 한글 처리 안 함
        if state == .english || state == .sequence {
            return false
        }
        // 한글인지 확인
        if self.keyboard?.is_hangul(ch: ascii) == false {
            return false
        }
        self.keyboard?.update_key_input_time_delta()
        PrintLog.shared.Log(log: "Key time delta \(String(describing: self.keyboard?.input_delta))")
        self.automata!.current.append(ascii)
        var comp:Composition = self.automata!.run()
        while comp.done {
            self.set_commit(comp: comp)
            comp = self.automata!.run()
        }
        self.set_preedit(comp: comp)
        return true
    }
    
    func Additional(ascii:String) -> String? {
        self.keyboard?.etc_layout[ascii]
    }
    
    func Backspace() -> Bool {
        if self.automata!.current.count > 0 {
            self.automata!.current.removeLast()
            let comp:Composition = self.automata!.run()
            self.set_preedit(comp: comp)
            return true
        }
        return false
    }

    func Flush() {
        let comp:Composition = self.automata!.run()
        self.set_commit(comp: comp)
        self.automata!.current = []
        currentPreedit = ""
    }

    var lastCommitted: String = ""
    var currentPreedit: String = ""

    func GetPreedit() -> [unichar] {
        let ret:[unichar] = self.preediting
        currentPreedit = String(utf16CodeUnits: ret, count: ret.count)
        self.preediting = []
        return ret
    }

    func PeekPreedit() -> [unichar] {
        return self.preediting
    }

    func GetCommit() -> [unichar] {
        let ret:[unichar] = self.committed
        lastCommitted = String(utf16CodeUnits: ret, count: ret.count)
        self.committed = []
        return ret
    }

    func clearState() {
        self.automata?.current = []
        self.preediting = []
        self.committed = []
        self.currentPreedit = ""
    }
    
    func GetDebug(t:String) -> [String] {
        let ret:[String]
        if t == "commit" {
            ret = self.debug_commit
        } else if t == "preedit" {
            ret = self.debug_preedit
        } else {
            ret = []
            self.debug_commit = []
            self.debug_preedit = []
        }
        return ret
    }
}