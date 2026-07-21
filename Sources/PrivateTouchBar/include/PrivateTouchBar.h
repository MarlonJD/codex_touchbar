#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT BOOL CTBPrivateTouchBarIsAvailable(void);
FOUNDATION_EXPORT BOOL CTBPresentSystemModalTouchBar(NSTouchBar *touchBar, NSString *trayIdentifier);
FOUNDATION_EXPORT void CTBDismissSystemModalTouchBar(NSTouchBar *touchBar);
FOUNDATION_EXPORT BOOL CTBAddSystemTrayItem(NSTouchBarItem *item);
FOUNDATION_EXPORT void CTBRemoveSystemTrayItem(NSTouchBarItem *item);
FOUNDATION_EXPORT void CTBSetControlStripPresence(NSString *identifier, BOOL present);
FOUNDATION_EXPORT void CTBSetCloseBoxVisible(BOOL visible);

NS_ASSUME_NONNULL_END
