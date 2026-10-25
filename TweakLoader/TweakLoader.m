#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <objc/runtime.h>
#import "../LiveContainer/utils.h"

// Set once FlekDeck's own Location Spoofer is loaded, so a copy of it among the
// user's tweaks does not hook everything a second time.
static BOOL locationSpooferLoaded = NO;

static NSString *loadTweakAtURL(NSURL *url) {
    NSString *tweakPath = url.path;
    NSString *tweak = tweakPath.lastPathComponent;
    if (![tweakPath hasSuffix:@".dylib"] && ![tweakPath hasSuffix:@".framework"]) {
        return nil;
    }
    if (locationSpooferLoaded && [tweak isEqualToString:@"LocationSpoofer.dylib"]) {
        NSLog(@"Skipping %@, FlekDeck's own copy is already loaded", tweak);
        return nil;
    }
    if ([tweakPath hasSuffix:@".framework"]) {
        NSURL* infoPlistURL = [url URLByAppendingPathComponent:@"Info.plist"];
        NSDictionary* infoDict = [NSDictionary dictionaryWithContentsOfURL:infoPlistURL];
        NSString* binary = infoDict[@"CFBundleExecutable"];
        if(!binary || ![binary isKindOfClass:NSString.class]) {
            return [NSString stringWithFormat:@"Unable to load %@: Unable to read Info.Plist", tweak];
        }
        tweakPath = [[url URLByAppendingPathComponent:binary] path];
    }
    
    void *handle = dlopen(tweakPath.UTF8String, RTLD_LAZY | RTLD_GLOBAL);
    const char *error = dlerror();
    if (handle) {
        NSLog(@"Loaded tweak %@", tweak);
        return nil;
    } else if (error) {
        NSLog(@"Error: %s", error);
        return @(error);
    } else {
        NSLog(@"Error: dlopen(%@): Unknown error because dlerror() returns NULL", tweak);
        return [NSString stringWithFormat:@"dlopen(%@): unknown error, handle is NULL", tweakPath];
    }
}

static void loadTweaksRecursively(NSURL *folderURL, NSMutableArray *errors) {
    NSArray<NSURL *> *items = [NSFileManager.defaultManager contentsOfDirectoryAtURL:folderURL includingPropertiesForKeys:@[NSURLIsDirectoryKey] options:0 error:nil];
    for (NSURL *fileURL in items) {
        NSString *name = fileURL.lastPathComponent;
        if ([name hasSuffix:@".disabled"]) {
            NSLog(@"Skipping disabled tweak %@", name);
            continue;
        }
        NSNumber *isDirectory = nil;
        [fileURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
        // a .framework is a directory but loads as a single tweak
        if (isDirectory.boolValue && ![name hasSuffix:@".framework"]) {
            loadTweaksRecursively(fileURL, errors);
        } else {
            NSString *error = loadTweakAtURL(fileURL);
            if (error) {
                [errors addObject:error];
            }
        }
    }
}

static void showDlerrAlert(NSString *error) {
    UIWindow *window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Failed to load tweaks" message:error preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
        window.windowScene = nil;
    }];
    [alert addAction:okAction];
    UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {
        UIPasteboard.generalPasteboard.string = error;
        window.windowScene = nil;
    }];
    [alert addAction:cancelAction];
    window.rootViewController = [UIViewController new];
    window.windowLevel = 1000;
    window.windowScene = (id)UIApplication.sharedApplication.connectedScenes.anyObject;
    [window makeKeyAndVisible];
    [window.rootViewController presentViewController:alert animated:YES completion:nil];
    objc_setAssociatedObject(alert, @"window", window, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void showDlerrAlertIfNeeded(NSArray<NSString *> *errors) {
    if (errors.count > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *error = [errors componentsJoinedByString:@"\n"];
            showDlerrAlert(error);
        });
    }
}

// FlekDeck's own Location Spoofer, turned on per app in its settings. It only
// swizzles Objective-C methods, so unlike tweaks in general it still works when
// TweakLoader comes in after the app's initializers.
static NSString *loadLocationSpooferIfOn(void) {
    if (![NSUserDefaults.guestAppInfo[@"spoofLocation"] boolValue]) {
        return nil;
    }
    NSString *lcMainBundlePath = NSUserDefaults.lcMainBundle.bundlePath;
    if (NSUserDefaults.isLiveProcess) {
        lcMainBundlePath = lcMainBundlePath.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent;
    }
    NSURL *url = [NSURL fileURLWithPath:[lcMainBundlePath stringByAppendingPathComponent:@"Frameworks/LocationSpoofer.dylib"]];
    if (![NSFileManager.defaultManager fileExistsAtPath:url.path]) {
        // A build without it has no toggle to turn it off with, so an alert on
        // every launch would have no way out.
        NSLog(@"Location Spoofer is on but missing from this build");
        return nil;
    }
    // A Premium feature, as FlekJIT is (enableJITWithStikJIT in LCBootstrap.m):
    // FlekDeck says how long Premium lasts, or that it has just confirmed it
    // for this launch. Not every launch starts in FlekDeck, where it is asked
    // first: a link opened in another app leads straight here.
    NSUserDefaults *shared = NSUserDefaults.lcSharedDefaults;
    NSTimeInterval clock = NSDate.date.timeIntervalSince1970;
    // The latest the clock has been seen at stands in for one wound back.
    NSTimeInterval now = MAX(clock, [shared doubleForKey:@"FSAccessClockHighWaterMark"]);
    BOOL justConfirmed = fabs(clock - [shared doubleForKey:@"FlekPremiumConfirmedAt"]) < 60;
    if (!justConfirmed && [shared doubleForKey:@"FlekPremiumUntil"] <= now) {
        return @"Location Spoofer needs Premium, so this app sees its real location. Open FlekDeck to renew Premium, or turn Location Spoofer off in the app's settings.";
    }
    NSString *error = loadTweakAtURL(url);
    locationSpooferLoaded = error == nil;
    return error;
}

 __attribute__((constructor))
static void TweakLoaderConstructor() {
    const char *tweakFolderC = getenv("LC_GLOBAL_TWEAKS_FOLDER");
    NSString *globalTweakFolder = @(tweakFolderC);
    unsetenv("LC_GLOBAL_TWEAKS_FOLDER");
    
    NSMutableArray *errors = [NSMutableArray new];
    NSString *locationSpooferError = loadLocationSpooferIfOn();
    if (locationSpooferError) {
        [errors addObject:locationSpooferError];
    }
    
    if([NSUserDefaults.guestAppInfo[@"dontInjectTweakLoader"] boolValue]) {
        // don't load any tweak since tweakloader is loaded after all initializers
        NSLog(@"Skip loading tweaks");
        showDlerrAlertIfNeeded(errors);
        return;
    }
    
    NSArray<NSURL *> *globalTweaks = [NSFileManager.defaultManager contentsOfDirectoryAtURL:[NSURL fileURLWithPath:globalTweakFolder]
    includingPropertiesForKeys:@[] options:0 error:nil];
    NSString *tweakFolderName = NSUserDefaults.guestAppInfo[@"LCTweakFolder"];
    
    if([globalTweaks count] <= 1 && tweakFolderName.length == 0) {
        // nothing to load
        showDlerrAlertIfNeeded(errors);
        return;
    }

    // Load CydiaSubstrate
    const char *lcMainBundlePath;
    if(NSUserDefaults.isLiveProcess) {
        lcMainBundlePath = NSUserDefaults.lcMainBundle.bundlePath.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent.fileSystemRepresentation;
    } else {
        lcMainBundlePath = NSUserDefaults.lcMainBundle.bundlePath.fileSystemRepresentation;
    }
    char substratePath[PATH_MAX];
    snprintf(substratePath, sizeof(substratePath), "%s/Frameworks/CydiaSubstrate.framework/CydiaSubstrate", lcMainBundlePath);
    dlopen(substratePath, RTLD_LAZY | RTLD_GLOBAL);
    const char *substrateError = dlerror();
    if (substrateError) {
        [errors addObject:@(substrateError)];
    }

    // Load global tweaks
    NSLog(@"Loading tweaks from the global folder");

    for (NSURL *fileURL in globalTweaks) {
        NSString *name = fileURL.lastPathComponent;
        if ([name isEqualToString:@"TweakLoader.dylib"]) {
            // skip loading myself
            continue;
        }
        if ([name hasSuffix:@".disabled"]) {
            NSLog(@"Skipping disabled global tweak %@", name);
            continue;
        }
        NSString *error = loadTweakAtURL(fileURL);
        if (error) {
            [errors addObject:error];
        }
    }

    // Load selected tweak folder, recursively
    if (tweakFolderName.length > 0) {
        NSLog(@"Loading tweaks from the selected folder");
        NSString *tweakFolder = [globalTweakFolder stringByAppendingPathComponent:tweakFolderName];
        loadTweaksRecursively([NSURL fileURLWithPath:tweakFolder], errors);
    }

    showDlerrAlertIfNeeded(errors);
}
