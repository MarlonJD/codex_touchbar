#import "PrivateTouchBar.h"

#import <dlfcn.h>
#import <objc/message.h>

static NSString *const CTBPrivateFrameworkPath = @"/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation";

static void *CTBFrameworkHandle(void) {
    static void *handle = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        handle = dlopen(CTBPrivateFrameworkPath.UTF8String, RTLD_LAZY | RTLD_LOCAL);
    });
    return handle;
}

static SEL CTBPresentSelector(void) {
    SEL modernSelector = NSSelectorFromString(@"presentSystemModalTouchBar:systemTrayItemIdentifier:");
    if ([(id)[NSTouchBar class] respondsToSelector:modernSelector]) {
        return modernSelector;
    }
    return NSSelectorFromString(@"presentSystemModalFunctionBar:systemTrayItemIdentifier:");
}

static SEL CTBDismissSelector(void) {
    SEL modernSelector = NSSelectorFromString(@"dismissSystemModalTouchBar:");
    if ([(id)[NSTouchBar class] respondsToSelector:modernSelector]) {
        return modernSelector;
    }
    return NSSelectorFromString(@"dismissSystemModalFunctionBar:");
}

BOOL CTBPrivateTouchBarIsAvailable(void) {
    SEL selector = CTBPresentSelector();
    return [(id)[NSTouchBar class] respondsToSelector:selector];
}

BOOL CTBPresentSystemModalTouchBar(NSTouchBar *touchBar, NSString *trayIdentifier) {
    SEL selector = CTBPresentSelector();
    Class touchBarClass = [NSTouchBar class];
    if (![(id)touchBarClass respondsToSelector:selector]) {
        return NO;
    }

    typedef void (*PresentMessage)(id, SEL, NSTouchBar *, NSString *);
    ((PresentMessage)objc_msgSend)(touchBarClass, selector, touchBar, trayIdentifier);
    return YES;
}

void CTBDismissSystemModalTouchBar(NSTouchBar *touchBar) {
    SEL selector = CTBDismissSelector();
    Class touchBarClass = [NSTouchBar class];
    if (![(id)touchBarClass respondsToSelector:selector]) {
        return;
    }

    typedef void (*DismissMessage)(id, SEL, NSTouchBar *);
    ((DismissMessage)objc_msgSend)(touchBarClass, selector, touchBar);
}

BOOL CTBAddSystemTrayItem(NSTouchBarItem *item) {
    SEL selector = NSSelectorFromString(@"addSystemTrayItem:");
    Class itemClass = [NSTouchBarItem class];
    if (![(id)itemClass respondsToSelector:selector]) {
        return NO;
    }

    typedef void (*TrayMessage)(id, SEL, NSTouchBarItem *);
    ((TrayMessage)objc_msgSend)(itemClass, selector, item);
    return YES;
}

void CTBRemoveSystemTrayItem(NSTouchBarItem *item) {
    SEL selector = NSSelectorFromString(@"removeSystemTrayItem:");
    Class itemClass = [NSTouchBarItem class];
    if (![(id)itemClass respondsToSelector:selector]) {
        return;
    }

    typedef void (*TrayMessage)(id, SEL, NSTouchBarItem *);
    ((TrayMessage)objc_msgSend)(itemClass, selector, item);
}

void CTBSetControlStripPresence(NSString *identifier, BOOL present) {
    void *handle = CTBFrameworkHandle();
    if (handle == NULL) {
        return;
    }

    typedef void (*PresenceFunction)(CFStringRef, BOOL);
    PresenceFunction function = (PresenceFunction)dlsym(handle, "DFRElementSetControlStripPresenceForIdentifier");
    if (function != NULL) {
        function((__bridge CFStringRef)identifier, present);
    }
}

void CTBSetCloseBoxVisible(BOOL visible) {
    void *handle = CTBFrameworkHandle();
    if (handle == NULL) {
        return;
    }

    typedef void (*CloseBoxFunction)(BOOL);
    CloseBoxFunction function = (CloseBoxFunction)dlsym(handle, "DFRSystemModalShowsCloseBoxWhenFrontMost");
    if (function != NULL) {
        function(visible);
    }
}
