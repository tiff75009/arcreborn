// SPDX-License-Identifier: MPL-2.0
import AppKit
import Sparkle

/// Only the presentation is custom. Sparkle still owns the appcast, signatures,
/// download, authorization, installation, termination and relaunch.
final class SidebarUpdateDriver: NSObject, SPUUserDriver {
    let session: SidebarUpdateSession
    private let standard = SPUStandardUserDriver(hostBundle:.main,delegate:nil)
    private var custom = false
    private var terminationTask: DispatchWorkItem?
    private var received: UInt64 = 0, expected: UInt64 = 0
    var canPresent: () -> Bool = { false }
    init(session: SidebarUpdateSession) { self.session = session; super.init() }

    func show(_ request:SPUUpdatePermissionRequest, reply:@escaping (SUUpdatePermissionResponse)->Void) {
        standard.show(request,reply:reply)
    }
    func showUserInitiatedUpdateCheck(cancellation:@escaping ()->Void) {
        standard.showUserInitiatedUpdateCheck(cancellation:cancellation)
    }
    func showUpdateFound(with appcastItem:SUAppcastItem, state:SPUUserUpdateState, reply:@escaping (SPUUserUpdateChoice)->Void) {
        // Keep Sparkle's explanatory UI for informational/major upgrades and
        // when there is no browser sidebar available (e.g. all windows closed).
        custom = canPresent() && !appcastItem.isInformationOnlyUpdate && !appcastItem.isMajorUpgrade
        guard custom else { standard.showUpdateFound(with:appcastItem,state:state,reply:reply); return }
        standard.dismissUpdateInstallation()
        session.offer(ready:state.stage == .installing) { reply(.install) }
        if state.userInitiated { showUpdateInFocus() }
    }
    func showUpdateReleaseNotes(with downloadData:SPUDownloadData) {
        if !custom { standard.showUpdateReleaseNotes(with:downloadData) }
    }
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error:Error) {
        if !custom { standard.showUpdateReleaseNotesFailedToDownloadWithError(error) }
    }
    func showUpdateNotFoundWithError(_ error:Error, acknowledgement:@escaping ()->Void) {
        session.finish(); standard.showUpdateNotFoundWithError(error,acknowledgement:acknowledgement)
    }
    func showUpdaterError(_ error:Error, acknowledgement:@escaping ()->Void) {
        terminationTask?.cancel(); session.finish(); standard.showUpdaterError(error,acknowledgement:acknowledgement)
    }
    func showDownloadInitiated(cancellation:@escaping ()->Void) {
        received = 0; expected = 0
        if custom { session.downloading() } else { standard.showDownloadInitiated(cancellation:cancellation) }
    }
    func showDownloadDidReceiveExpectedContentLength(_ length:UInt64) {
        expected = length
        if custom { updateProgress() } else { standard.showDownloadDidReceiveExpectedContentLength(length) }
    }
    func showDownloadDidReceiveData(ofLength length:UInt64) {
        received = received.addingReportingOverflow(length).partialValue
        if custom { updateProgress() } else { standard.showDownloadDidReceiveData(ofLength:length) }
    }
    private func updateProgress() { session.downloading(expected > 0 ? Double(received)/Double(expected) : nil) }
    func showDownloadDidStartExtractingUpdate() {
        if custom { session.preparing() } else { standard.showDownloadDidStartExtractingUpdate() }
    }
    func showExtractionReceivedProgress(_ progress:Double) {
        if custom { session.preparing(progress) } else { standard.showExtractionReceivedProgress(progress) }
    }
    func showReady(toInstallAndRelaunch reply:@escaping (SPUUserUpdateChoice)->Void) {
        if custom { session.ready { reply(.install) } } else { standard.showReady(toInstallAndRelaunch:reply) }
    }
    func showInstallingUpdate(withApplicationTerminated terminated:Bool, retryTerminatingApplication retry:@escaping ()->Void) {
        guard custom else { standard.showInstallingUpdate(withApplicationTerminated:terminated,retryTerminatingApplication:retry); return }
        terminationTask?.cancel(); session.installing()
        // A page's beforeunload may cancel/delay termination. Retain Sparkle's
        // retry callback instead of forcing the browser process to quit.
        if !terminated {
            let task = DispatchWorkItem { [weak self] in
                self?.session.awaitingTermination(retry:retry)
            }
            terminationTask = task
            DispatchQueue.main.asyncAfter(deadline:.now()+3,execute:task)
        }
    }
    func showUpdateInstalledAndRelaunched(_ relaunched:Bool, acknowledgement:@escaping ()->Void) {
        terminationTask?.cancel(); session.finish(); standard.showUpdateInstalledAndRelaunched(relaunched,acknowledgement:acknowledgement)
    }
    func dismissUpdateInstallation() { terminationTask?.cancel(); session.finish(); custom = false; standard.dismissUpdateInstallation() }
    func showUpdateInFocus() {
        if custom { NotificationCenter.default.post(name:SidebarUpdateSession.focus,object:session) }
        else { standard.showUpdateInFocus() }
    }
}
