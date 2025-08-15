#import <React/RCTViewManager.h>
#import <React/RCTUIManager.h>

@interface RCT_EXTERN_MODULE(GodotViewManager, RCTViewManager)
RCT_EXPORT_VIEW_PROPERTY(projectPath, NSString)
RCT_EXPORT_VIEW_PROPERTY(mainScene, NSString)
RCT_EXPORT_VIEW_PROPERTY(symbolPrefix, NSString)
RCT_EXPORT_VIEW_PROPERTY(symbolPrefixes, NSString) // NOWY
RCT_EXPORT_VIEW_PROPERTY(suppressStubLogs, NSNumber)
RCT_EXPORT_VIEW_PROPERTY(autoStart, NSNumber)
RCT_EXTERN_METHOD(sendEventToGodot:(nonnull NSNumber *)reactTag event:(NSString *))
RCT_EXTERN_METHOD(ensureEngine:(nonnull NSNumber *)reactTag)
RCT_EXTERN_METHOD(diagnoseStub:(nonnull NSNumber *)reactTag)
RCT_EXTERN_METHOD(setScene:(nonnull NSNumber *)reactTag scene:(NSString *))   // dodane
RCT_EXTERN_METHOD(forceAttachRenderView:(nonnull NSNumber *)reactTag) // NOWE
@end
