// In-process macOS scroll / mouse event monitor. See RawTrackpadMonitor.hpp.
//
// This is the only Objective-C++ translation unit in the injected library. It
// forwards every precise-scroll event (delta X and Y, phase, momentum phase)
// to bg3cam::RawTrackpadScroll, and middle-button drag / up events to
// bg3cam::MouseMiddleDragged / MouseMiddleUp. All scaling, the gesture
// lifecycle, the axis lock and the telemetry live in CameraHooks.cpp.

#import <AppKit/AppKit.h>
#import <dispatch/dispatch.h>

#include <atomic>

#include "RawTrackpadMonitor.hpp"

namespace {

id gRawTrackpadMonitorToken = nil;
std::atomic<bool> gRawTrackpadStartRequested{false};

}  // namespace

namespace bg3cam {

void StartRawTrackpadMonitor() {
    if (gRawTrackpadStartRequested.exchange(true, std::memory_order_acq_rel)) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (gRawTrackpadMonitorToken != nil) {
            return;
        }

        // 1. Update the mask to include Right Mouse Dragged and Up events
        const NSEventMask mask =
            NSEventMaskScrollWheel |
            NSEventMaskRightMouseDragged |
            NSEventMaskRightMouseUp;
            
        gRawTrackpadMonitorToken = [NSEvent
            addLocalMonitorForEventsMatchingMask:mask
                                        handler:^NSEvent *(NSEvent *event) {
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
            // 2. Change from OtherMouseDragged (Middle) to RightMouseDragged (Right)
            case NSEventTypeRightMouseDragged:
                // Right mouse button number is 1 in AppKit
                if (event.buttonNumber == 1) {
                    bg3cam::MouseMiddleDragged(
                        static_cast<double>(event.deltaX),
                        static_cast<double>(event.deltaY));
                }
                break;
            // 3. Change from OtherMouseUp to RightMouseUp
            case NSEventTypeRightMouseUp:
                if (event.buttonNumber == 1) {
                    bg3cam::MouseMiddleUp();
                }
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
