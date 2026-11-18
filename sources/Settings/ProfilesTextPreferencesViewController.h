//
//  ProfilesTextPreferencesViewController.h
//  iTerm
//
//  Created by George Nachman on 4/15/14.
//
//

#import "iTermProfilePreferencesBaseViewController.h"

@interface ProfilesTextPreferencesViewController : iTermProfilePreferencesBaseViewController

@property(nonatomic, readonly) NSMatrix *cursorType;
@property(nonatomic, readonly) NSTextField *cursorTypeLabel;
@property(nonatomic, readonly) NSButton *blinkingCursor;
@property(nonatomic, readonly) NSButton *cursorSmoothBlink;
@property(nonatomic, readonly) NSButton *cursorSmoothBlinkConfigureButton;
@property(nonatomic, readonly) NSButton *cursorSmoothSlide;
@property(nonatomic, readonly) NSButton *shadow;
@property(nonatomic, readonly) NSButton *hideOnLostFocus;
@property(nonatomic, readonly) NSButton *animateMovement;
@property(nonatomic, readonly) NSButton *animateMovementOnlyInInteractiveApps;
@property(nonatomic, readonly) NSView *asciiFontPicker;
@property(nonatomic, readonly) NSTextField *cellMetricsLabel;
@property(nonatomic, readonly) NSView *languageFontRulesEditorView;
@property(nonatomic, readonly) NSButton *asciiAntiAliased;
@property(nonatomic, readonly) NSTextField *normalFontWantsAntialiasing;
@property(nonatomic, readonly) NSButton *asciiLigatures;
@property(nonatomic, readonly) NSTextField *ligatureWarning;
@property(nonatomic, readonly) NSPopUpButton *thinStrokes;
@property(nonatomic, readonly) NSTextField *thinStrokesLabel;
@property(nonatomic, readonly) NSButton *useNonAsciiFont;
@property(nonatomic, readonly) NSView *nonAsciiFontView;
@property(nonatomic, readonly) NSView *nonASCIIFontPicker;
@property(nonatomic, readonly) NSButton *nonasciiAntiAliased;
@property(nonatomic, readonly) NSTextField *nonasciiFontWantsAntialiasing;
@property(nonatomic, readonly) NSButton *nonAsciiLigatures;
@property(nonatomic, readonly) NSTextField *ligatureWarningNonAscii;
@property(nonatomic, readonly) NSButton *useBoldFont;
@property(nonatomic, readonly) NSButton *blinkAllowed;
@property(nonatomic, readonly) NSButton *useItalicFont;
@property(nonatomic, readonly) NSButton *powerline;
@property(nonatomic, readonly) NSPopUpButton *normalization;
@property(nonatomic, readonly) NSTextField *normalizationLabel;
@property(nonatomic, readonly) NSButton *unicodeVersion9;
@property(nonatomic, readonly) NSButton *ambiguousIsDoubleWidth;

@property(nonatomic, strong) IBOutlet NSTextField *asciiFontLabel;
@property(nonatomic, strong) IBOutlet NSTextField *nonAsciiFontLabel;
@property(nonatomic, strong) IBOutlet NSTextField *textRenderingLabel;
@property(nonatomic, strong) IBOutlet NSTextField *unicodeLabel;
@property(nonatomic, strong) IBOutlet NSButton *manageCharacterFontsButton;

@end
