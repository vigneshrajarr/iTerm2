/*
 **  PreferencePanel.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **
 **  Project: iTerm
 **
 **  Description: Implements the model and controller for the preference panel.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

/*
 * Preferences in iTerm2 are complicated, to say the least. Here is how the classes are organized.
 *
 * - PreferencePanel: There are two instances of this class: -sharedInstance and -sessionsInstance.
 *       The sharedInstance is the app settings panel, while sessionsInstance is for editing a
 *       single session (View>Edit Current Session).
 *     - GeneralPreferencesViewController:    View controller for Prefs>General
 *     - AppearancePreferencesViewController: View controller for Prefs>Appearance
 *     - KeysPreferencesViewController:       View controller for Prefs>Keys
 *     - PointerPreferencesViewController:    View controller for Prefs>Pointer
 *     - ProfilePreferencesViewController:    View controller for Prefs>Profiles
 *     - WindowArrangements:                  Owns Prefs>Arrangements
 *     - iTermAdvancedSettingsController:     Owns Prefs>Advanced
 *
 *  View controllers of tabs in PreferencePanel derive from iTermPreferencesBaseViewController.
 *  iTermPreferencesBaseViewController provides a map from NSControl* to PreferenceInfo.
 *  PreferenceInfo stores a pref's type, user defaults key, can constrain its value, and
 *  stores pointers to blocks that are run when a value is changed or a field needs to be updated
 *  for customizing how controls are bound to storage. Each view controller defines these bindings
 *  in its -awakeFromNib method.
 *
 *  User defaults are accessed through iTermPreferences, which assigns string constants to user
 *  defaults keys, defines default values for each key, and provides accessors. It also allows the
 *  exposed values to be computed from underlying values. (Currently, iTermPreferences is not used
 *  by advanced settings, but that should change).
 *
 *  Because per-profile preferences are similar, a parallel class structure exists for them.
 *  The following classes are view controllers for tabs in Prefs>Profiles:
 *
 *  - ProfilesGeneralPreferencesViewController
 *  - ProfilesColorPreferencesViewController
 *  - ProfilesTextPreferencesViewController
 *  - ProfilesWindowPreferencesViewController
 *  - ProfilesTerminalPreferencesViewController
 *  - ProfilesKeysPreferencesViewController
 *  - ProfilesAdvancedPreferencesViewController
 *
 *  These derive from iTermProfilePreferencesBaseViewController, which is just like
 *  iTermPreferencesBaseViewController, but its methods for accessing preference values take an
 *  additional profile: parameter. The analog of iTermPreferences is iTermProfilePreferences.
 *  */
#import "PreferencePanel.h"
#import "AppearancePreferencesViewController.h"
#import "GeneralPreferencesViewController.h"
#import "ITAddressBookMgr.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermAdvancedSettingsViewController.h"
#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermController.h"
#import "iTermKeyBindingMgr.h"
#import "iTermKeyMappingViewController.h"
#import "iTermLaunchServices.h"
#import "iTermPreferences.h"
#import "iTermRemotePreferences.h"
#import "iTermSizeRememberingView.h"
#import "iTermWarning.h"
#import "KeysPreferencesViewController.h"
#import "NSDictionary+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSPopUpButton+iTerm.h"
#import "NSStringITerm.h"
#import "PasteboardHistory.h"
#import "PointerPrefsController.h"
#import "ProfileModel.h"
#import "ProfilePreferencesViewController.h"
#import "ProfilesColorsPreferencesViewController.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "SessionView.h"
#import "WindowArrangements.h"
#include <stdlib.h>

NSString *const kRefreshTerminalNotification = @"kRefreshTerminalNotification";
NSString *const kUpdateLabelsNotification = @"kUpdateLabelsNotification";
NSString *const kKeyBindingsChangedNotification = @"kKeyBindingsChangedNotification";
NSString *const kPreferencePanelDidUpdateProfileFields = @"kPreferencePanelDidUpdateProfileFields";
NSString *const kSessionProfileDidChange = @"kSessionProfileDidChange";
NSString *const kPreferencePanelDidLoadNotification = @"kPreferencePanelDidLoadNotification";
NSString *const kPreferencePanelWillCloseNotification = @"kPreferencePanelWillCloseNotification";

// Strong references to the two preference panels.
static PreferencePanel *gSharedPreferencePanel;
static PreferencePanel *gSessionsPreferencePanel;

@interface PreferencePanel() <NSTabViewDelegate>

@end
@implementation PreferencePanel {
    ProfileModel *_profileModel;
    BOOL _editCurrentSessionMode;
    __weak IBOutlet GeneralPreferencesViewController *_generalPreferencesViewController;
    __weak IBOutlet AppearancePreferencesViewController *_appearancePreferencesViewController;
    __weak IBOutlet KeysPreferencesViewController *_keysViewController;
    __weak IBOutlet ProfilePreferencesViewController *_profilesViewController;
    __weak IBOutlet PointerPreferencesViewController *_pointerViewController;
    __weak IBOutlet iTermAdvancedSettingsViewController *_advancedViewController;

    __weak IBOutlet NSToolbar *_toolbar;
    __weak IBOutlet NSTabView *_tabView;
    __weak IBOutlet NSToolbarItem *_globalToolbarItem;
    __weak IBOutlet NSTabViewItem *_globalTabViewItem;
    __weak IBOutlet NSToolbarItem *_appearanceToolbarItem;
    __weak IBOutlet NSTabViewItem *_appearanceTabViewItem;
    __weak IBOutlet NSToolbarItem *_keyboardToolbarItem;
    __weak IBOutlet NSToolbarItem *_arrangementsToolbarItem;
    __weak IBOutlet NSTabViewItem *_keyboardTabViewItem;
    __weak IBOutlet NSTabViewItem *_arrangementsTabViewItem;
    __weak IBOutlet NSToolbarItem *_bookmarksToolbarItem;
    __weak IBOutlet NSTabViewItem *_bookmarksTabViewItem;
    __weak IBOutlet NSToolbarItem *_mouseToolbarItem;
    __weak IBOutlet NSTabViewItem *_mouseTabViewItem;
    __weak IBOutlet NSToolbarItem *_advancedToolbarItem;
    __weak IBOutlet NSTabViewItem *_advancedTabViewItem;

    // This class is not well named. It is a view controller for the window
    // arrangements tab. It's also a singleton :(
    __weak IBOutlet WindowArrangements *arrangements_;
    NSSize _standardSize;
}

+ (instancetype)sharedInstance {
    if (!gSharedPreferencePanel) {
        gSharedPreferencePanel = [[PreferencePanel alloc] initWithProfileModel:[ProfileModel sharedInstance]
                                                        editCurrentSessionMode:NO];
    }
    return gSharedPreferencePanel;
}

+ (instancetype)sessionsInstance {
    if (!gSessionsPreferencePanel) {
        gSessionsPreferencePanel = [[PreferencePanel alloc] initWithProfileModel:[ProfileModel sessionsInstance]
                                                          editCurrentSessionMode:YES];
    }
    return gSessionsPreferencePanel;
}

- (instancetype)initWithProfileModel:(ProfileModel*)model
              editCurrentSessionMode:(BOOL)editCurrentSessionMode {
    self = [super initWithWindowNibName:@"PreferencePanel"];
    if (self) {
        _profileModel = model;

        [_toolbar setSelectedItemIdentifier:[_globalToolbarItem itemIdentifier]];

        _editCurrentSessionMode = editCurrentSessionMode;
    }
    return self;
}

- (BOOL)autoHidesHotKeyWindow {
    return NO;
}

#pragma mark - View layout

- (void)awakeFromNib {
    NSAssert(self.isWindowLoaded, @"window not loaded in %@", NSStringFromSelector(_cmd));
    [self.window setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];
    [_toolbar setSelectedItemIdentifier:[_globalToolbarItem itemIdentifier]];

    _globalTabViewItem.view = _generalPreferencesViewController.view;
    _appearanceTabViewItem.view = _appearancePreferencesViewController.view;
    _keyboardTabViewItem.view = _keysViewController.view;
    _arrangementsTabViewItem.view = arrangements_.view;
    _mouseTabViewItem.view = _pointerViewController.view;
    _advancedTabViewItem.view = _advancedViewController.view;

    _generalPreferencesViewController.preferencePanel = self;
    _appearancePreferencesViewController.preferencePanel = self;
    _keysViewController.preferencePanel = self;
    _profilesViewController.preferencePanel = self;
    _pointerViewController.preferencePanel = self;

    if (_editCurrentSessionMode) {
        [self layoutSubviewsForEditCurrentSessionMode];
    } else {
        [self resizeWindowForTabViewItem:_globalTabViewItem];
    }
}

- (void)layoutSubviewsForEditCurrentSessionMode {
    [self selectProfilesTab];
    [_profilesViewController layoutSubviewsForEditCurrentSessionMode];
    [_toolbar setVisible:NO];

    [_profilesViewController resizeWindowForCurrentTab];

}

#pragma mark - API

- (void)configureHotkeyForProfile:(Profile *)profile {
    [self window];
    [self selectProfilesTab];
    [self run];
    [_profilesViewController openToProfileWithGuidAndEditHotKey:profile[KEY_GUID]];
}

- (void)selectProfilesTab {
    [_tabView selectTabViewItem:_bookmarksTabViewItem];
    [_toolbar setSelectedItemIdentifier:[_bookmarksToolbarItem itemIdentifier]];
}

// NOTE: Callers should invoke makeKeyAndOrderFront if they are so inclined.
- (void)openToProfileWithGuid:(NSString*)guid selectGeneralTab:(BOOL)selectGeneralTab {
    [self window];
    [self selectProfilesTab];
    [self run];
    [_profilesViewController openToProfileWithGuid:guid selectGeneralTab:selectGeneralTab];
}

- (NSWindow *)window {
    BOOL shouldPostWindowLoadNotification = !self.windowLoaded;
    NSWindow *window = [super window];
    if (shouldPostWindowLoadNotification) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kPreferencePanelDidLoadNotification
                                                            object:self];
    }
    return window;
}

- (NSWindow *)windowIfLoaded {
    if (self.isWindowLoaded) {
        return self.window;
    } else {
        return nil;
    }
}

- (WindowArrangements *)arrangements {
    return arrangements_;
}

- (void)run {
    [self window];
    [_generalPreferencesViewController updateEnabledState];
    [_profilesViewController selectFirstProfileIfNecessary];
    if (!self.window.isVisible) {
        [self showWindow:self];
    }
}

// Update the values in form fields to reflect the bookmark's state
- (void)underlyingBookmarkDidChange {
    [_profilesViewController refresh];
}

- (NSString *)nameForFrame {
    return [NSString stringWithFormat:@"%@Preferences", _profileModel.modelName];
}

#pragma mark - NSWindowController

- (void)windowWillLoad {
    DLog(@"Will load prefs panel from %@", [NSThread callStackSymbols]);
    // We finally set our autosave window frame name and restore the one from the user's defaults.
    [self setShouldCascadeWindows:NO];
}

- (void)windowDidLoad {
    // We shouldn't use setFrameAutosaveName: because this window controller controls two windows
    // with different frames (besides, I tried it and it doesn't work here for some reason).
    [self.window setFrameUsingName:self.nameForFrame force:NO];
}

#pragma mark - NSWindowDelegate

- (void)windowDidMove:(NSNotification *)notification {
    [self.window saveFrameUsingName:self.nameForFrame];
}

- (void)windowWillClose:(NSNotification *)aNotification {
    [self.window saveFrameUsingName:self.nameForFrame];

    [[self retain] autorelease];

    if (self == gSharedPreferencePanel) {
        [gSharedPreferencePanel autorelease];
        gSharedPreferencePanel = nil;
    } else if (self == gSessionsPreferencePanel) {
        [gSessionsPreferencePanel autorelease];
        gSessionsPreferencePanel = nil;
    }

    [self postWillCloseNotification];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)windowDidBecomeKey:(NSNotification *)aNotification {
    [[NSNotificationCenter defaultCenter] postNotificationName:kNonTerminalWindowBecameKeyNotification
                                                        object:nil
                                                      userInfo:nil];
}

- (void)postWillCloseNotification {
    [[NSNotificationCenter defaultCenter] postNotificationName:kPreferencePanelWillCloseNotification
                                                        object:self];
}

#pragma mark - Handle calls to current first responder

// Shell>Close
- (void)closeCurrentSession:(id)sender {
    [self close];
}

// Shell>Close Terminal Window
- (void)closeWindow:(id)sender {
    [self close];
}

- (void)close {
    [self postWillCloseNotification];
    [super close];
}

- (void)changeFont:(id)fontManager {
    [_profilesViewController changeFont:fontManager];
}

#pragma mark - IBActions

- (IBAction)showGlobalTabView:(id)sender {
    [_tabView selectTabViewItem:_globalTabViewItem];
}

- (IBAction)showAppearanceTabView:(id)sender {
    [_tabView selectTabViewItem:_appearanceTabViewItem];
}

- (IBAction)showBookmarksTabView:(id)sender {
    [_tabView selectTabViewItem:_bookmarksTabViewItem];
}

- (IBAction)showKeyboardTabView:(id)sender {
    [_tabView selectTabViewItem:_keyboardTabViewItem];
}

- (IBAction)showArrangementsTabView:(id)sender {
    [_tabView selectTabViewItem:_arrangementsTabViewItem];
}

- (IBAction)showMouseTabView:(id)sender {
    [_tabView selectTabViewItem:_mouseTabViewItem];
}

- (IBAction)showAdvancedTabView:(id)sender {
    [_tabView selectTabViewItem:_advancedTabViewItem];
}

#pragma mark - NSToolbarDelegate and ToolbarItemValidation

- (BOOL)validateToolbarItem:(NSToolbarItem *)theItem {
    return TRUE;
}

- (NSArray *)orderedToolbarIdentifiers {
    if (!_globalToolbarItem) {
        return @[];
    }
    return @[ [_globalToolbarItem itemIdentifier],
              [_appearanceToolbarItem itemIdentifier],
              [_bookmarksToolbarItem itemIdentifier],
              [_keyboardToolbarItem itemIdentifier],
              [_arrangementsToolbarItem itemIdentifier],
              [_mouseToolbarItem itemIdentifier],
              [_advancedToolbarItem itemIdentifier] ];
}

- (NSDictionary *)toolbarIdentifierToItemDictionary {
    if (!_globalToolbarItem) {
        return @{};
    }
    return @{ [_globalToolbarItem itemIdentifier]: _globalToolbarItem,
              [_appearanceToolbarItem itemIdentifier]: _appearanceToolbarItem,
              [_bookmarksToolbarItem itemIdentifier]: _bookmarksToolbarItem,
              [_keyboardToolbarItem itemIdentifier]: _keyboardToolbarItem,
              [_arrangementsToolbarItem itemIdentifier]: _arrangementsToolbarItem,
              [_mouseToolbarItem itemIdentifier]: _mouseToolbarItem,
              [_advancedToolbarItem itemIdentifier]: _advancedToolbarItem };
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSString *)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag {
    if (!flag) {
        return nil;
    }
    NSDictionary *theDict = [self toolbarIdentifierToItemDictionary];
    return theDict[itemIdentifier];
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return [self orderedToolbarIdentifiers];
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return [self orderedToolbarIdentifiers];
}

- (NSArray *)toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar {
    return [self orderedToolbarIdentifiers];
}

#pragma mark - Hotkey Window

// This is used by iTermHotKeyController to not activate the hotkey while the field for typing
// the hotkey into is the first responder.
- (NSTextField*)hotkeyField {
    return _keysViewController.hotkeyField;
}

#pragma mark - Accessors

- (NSString *)currentProfileGuid {
    return [_profilesViewController selectedProfile][KEY_GUID];
}

#pragma mark - ProfilePreferencesViewControllerDelegate

- (ProfileModel *)profilePreferencesModel {
    return _profileModel;
}

#pragma mark - NSTabViewDelegate

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    if (tabViewItem == _bookmarksTabViewItem) {
        [_profilesViewController resizeWindowForCurrentTab];
    } else {
        [self resizeWindowForTabViewItem:tabViewItem];
    }
}

- (void)resizeWindowForTabViewItem:(NSTabViewItem *)tabViewItem {
    iTermSizeRememberingView *theView = (iTermSizeRememberingView *)tabViewItem.view;
    [theView resetToOriginalSize];
    NSRect rect = self.window.frame;
    NSPoint topLeft = rect.origin;
    topLeft.y += rect.size.height;
    NSSize size = [tabViewItem.view frame].size;
    rect.size = size;
    rect.size.height += 87;
    rect.size.width += 26;
    rect.origin = topLeft;
    rect.origin.y -= rect.size.height;
    [[self window] setFrame:rect display:YES animate:YES];
}

@end

