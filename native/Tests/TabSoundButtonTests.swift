// SPDX-License-Identifier: MPL-2.0
import AppKit

@main
enum TabSoundButtonTests {
    static func main() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:160,height:48),styleMask:[],backing:.buffered,defer:false)
        let button = TabSoundButton()
        window.contentView?.addSubview(button)
        func show(_ id:String, _ state:TabSoundState, language:String = "fr") {
            button.configure(id:id,sound:state,ink:.white,language:language)
        }
        func advance(_ seconds:TimeInterval) { RunLoop.main.run(until:Date(timeIntervalSinceNow:seconds)) }
        show("a", .silent)
        precondition(button.isHidden && button.titleInset == 0)
        show("a", .playing)
        advance(0.045)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            precondition(button.titleInset > 0 && button.titleInset < 25)
        }
        show("a", .silent); show("a", .playing)
        advance(0.4)
        precondition(!button.isHidden && button.titleInset == 25)
        precondition(button.accessibilityLabel() == "Couper le son de l’onglet")
        show("a", .muted, language:"en")
        advance(0.4)
        precondition(button.titleInset == 21 && button.accessibilityLabel() == "Unmute tab")
        show("a", .playing)
        // During the reversal, AppKit rebinds the row to a silent tab.
        show("b", .silent); advance(0.4)
        precondition(button.isHidden && button.titleInset == 0)
        show("c", .muted)
        precondition(!button.isHidden && button.titleInset == 21)
        print("PASS: tab audio appearance, reversal, row reuse and localized actions")
    }
}
