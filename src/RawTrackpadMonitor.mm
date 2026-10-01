// In-process macOS scroll / mouse event monitor. See RawTrackpadMonitor.hpp.
//
// This is the only Objective-C++ translation unit in the injected library. It
// forwards every precise-scroll event (delta X and Y, phase, momentum phase)
// to bg3cam::RawTrackpadScroll, and right-button drag / up events (mapped 
// to middle-button handlers) to bg3cam::MouseMiddleDragged / MouseMiddleUp.

#import <AppKit/AppKit.h>
#import <dispatch/dispatch.h>

#include <atomic>

#include "RawTrackpadMonitor.hpp"

namespace {

// Strong reference to the opaque monitor object AppKit hands back. Touched
// only on the main thread.
id gRawTrackpadMonitorToken = nil;

// Guards against a second Start / a Stop that races an un-run Start.
std::atomic<bool> gRawTrackpadStartRequested{false};

}  // namespace

namespace bg3cam {

void StartRawTrackpadMonitor() {
    if (gRawTrackpadStartRequested.exchange(true, std::memory_order_acq_rel)) {
        return;
    }

    // addLocalMonitorForEventsMatchingMask: must run on the main thread.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gRawTrackpadMonitorToken != nil) {
            return;
        }

        const NSEventMask mask =
            NSEventMaskScrollWheel |
            NSEventMaskRightMouseDragged |
            NSEventMaskRightMouseUp;
        gRawTrackpadMonitorToken = [NSEvent
            addLocalMonitorForEventsMatchingMask:mask
                                        handler:^NSEvent *(NSEvent *event) {
            // The event is never modified and is always returned so UI
            // interaction and BG3's own handling remain untouched.
            switch (event.type) {
            case NSEventTypeScrollWheel:
                if (event.hasPreciseScrollingDeltas) {
                    bg3cam::RawTrackpadScroll(
                        static_cast<double>(event.scrollingDeltaX),
                        static_cast<double>(event.scrollingDeltaY),
                        static_cast<unsigned long>(event.phase),
                        static_cast<unsigned long>(event.momentumPhase));
                }
                break;
            case NSEventTypeRightMouseDragged:
                bg3cam::MouseMiddleDragged(
                    static_cast<double>(event.deltaX),
                    static_cast<double>(event.deltaY));
                break;
            case NSEventTypeRightMouseUp:
                bg3cam::MouseMiddleUp();
                break;
            default:
                break;
            }
            return event;
        }];

        bg3cam::SetRawTrackpadMonitorActive(true);
    });
}

void StopRawTrackpadMonitor() {
    if (!gRawTrackpadStartRequested.exchange(false, std::memory_order_acq_rel)) {
        return;
    }

    bg3cam::SetRawTrackpadMonitorActive(false);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (gRawTrackpadMonitorToken != nil) {
            [NSEvent removeMonitor:gRawTrackpadMonitorToken];
            gRawTrackpadMonitorToken = nil;
        }
    });
}

}  // namespace bg3cam
