//
//  XcodeColors.m
//  XcodeColors
//
//  Created by Uncle MiF on 9/13/10.
//  Copyright 2010 Deep IT. All rights reserved.
//

#import "XcodeColors.h"
#import <objc/runtime.h>
#import "JRSwizzle.h"

#define XCODE_COLORS "XcodeColors"

// How to apply color formatting to your log statements:
//
// To set the foreground color:
// Insert the ESCAPE_SEQ into your string, followed by "fg124,12,255;" where r=124, g=12, b=255.
//
// To set the background color:
// Insert the ESCAPE_SEQ into your string, followed by "bg12,24,36;" where r=12, g=24, b=36.
//
// To reset the foreground color (to default value):
// Insert the ESCAPE_SEQ into your string, followed by "fg;"
//
// To reset the background color (to default value):
// Insert the ESCAPE_SEQ into your string, followed by "bg;"
//
// To reset the foreground and background color (to default values) in one operation:
// Insert the ESCAPE_SEQ into your string, followed by ";"
//
//
// Feel free to copy the define statements below into your code.
// <COPY ME>

#define XCODE_COLORS_ESCAPE @"\033["

#define XCODE_COLORS_RESET_FG XCODE_COLORS_ESCAPE @"fg;" // Clear any foreground color
#define XCODE_COLORS_RESET_BG XCODE_COLORS_ESCAPE @"bg;" // Clear any background color
#define XCODE_COLORS_RESET XCODE_COLORS_ESCAPE @";" // Clear any foreground or background color

// </COPY ME>


enum TermAttr {
    TERM_RESET = 0, // "normal" mode
    TERM_BRIGHT = 1, // more luminosity for the foreground
    TERM_DIM = 2, // less luminosity for the foreground
    TERM_UNDERLINE = 4,
    TERM_BLINK = 5, // no difference...
    TERM_REVERSE = 7, // reverse front and back color
};

typedef enum TermColor {
    TERM_BLACK = 0,
    TERM_RED,
    TERM_GREEN,
    TERM_YELLOW,
    TERM_BLUE,
    TERM_MAGENTA,
    TERM_CYAN,
    TERM_WHITE,
    TERM_NONE // not really standard, but it works with xterm...^^
} TermColor;

NSColor *rgbFromANSI(TermColor c) {
    switch(c) {
        case TERM_RED:
            return [NSColor redColor];
        case TERM_BLUE:
            return [NSColor blueColor];
        case TERM_GREEN:
            return [NSColor greenColor];
        case TERM_YELLOW:
            return [NSColor orangeColor];
        case TERM_MAGENTA:
            return [NSColor magentaColor];
        case TERM_CYAN:
            return [NSColor cyanColor];
        case TERM_WHITE:
            return [NSColor whiteColor];
        case TERM_NONE:
        case TERM_BLACK:
        default:
            return [NSColor blackColor];
    }
}

@implementation NSTextStorage (XcodeColors)

void ApplyANSIColors(NSTextStorage *textStorage, NSRange textStorageRange, NSString *escapeSeq) {
    NSRange range = [[textStorage string] rangeOfString:escapeSeq options:0 range:textStorageRange];
    if(range.location == NSNotFound) {
        // No escape sequence(s) in the string.
        return;
    }

    NSString *affectedString = [[textStorage string] substringWithRange:textStorageRange];

    // Split the string into components separated by the given escape sequence.

    NSArray *components = [affectedString componentsSeparatedByString:escapeSeq];

    NSRange componentRange = textStorageRange;
    componentRange.length = 0;

    BOOL firstPass = YES;

    NSMutableArray *seqRanges = [NSMutableArray arrayWithCapacity:[components count]];
    NSMutableDictionary *attrs = [NSMutableDictionary dictionaryWithCapacity:2];

    for(NSString *component in components) {
        NSString *c = component;
        if(firstPass) {
            // The first component in the array won't need processing.
            // If there was an escape sequence at the very beginning of the string,
            // then the first component in the array will be an empty string.
            // Otherwise the first component is everything before the first escape sequence.
        } else {
            // componentSeqRange : Range of escape sequence within component, e.g. "fg124,12,12;"

            NSUInteger colorCodeSeqLength = 0;


            NSArray *a = [c componentsSeparatedByString:@";"];
            if([a count] > 2) {
                if(([a[2] length] >= 1 && [a[2] characterAtIndex:0] == 'm') ||
                   ([a[2] length] >= 2 && [a[2] characterAtIndex:1] == 'm') ||
                   ([a[2] length] >= 3 && [a[2] characterAtIndex:2] == 'm')) {
                    int attr = [a[0] intValue];
                    int front = [a[1] intValue] - 30;
                    int back = [a[2] intValue] - 40;

                    NSColor *frontColor = rgbFromANSI(front);
                    NSColor *backColor = rgbFromANSI(back);

                    colorCodeSeqLength = [a[0] length] + 1 + [a[1] length] + 1 +
                                         ([a[2] characterAtIndex:0] == 'm' ? 1 : [a[2] characterAtIndex:1] == 'm' ? 2 : 3);

                    if(attr == TERM_RESET) {
                        [attrs removeObjectForKey:NSForegroundColorAttributeName];
                        [attrs removeObjectForKey:NSBackgroundColorAttributeName];

                        // Mark the range of the sequence (escape sequence + reset color sequence).
                        NSRange seqRange = (NSRange){
                            .location = componentRange.location - [escapeSeq length], .length = colorCodeSeqLength + [escapeSeq length],
                        };
                        [seqRanges addObject:[NSValue valueWithRange:seqRange]];
                    } else {
                        [attrs setObject:frontColor forKey:NSForegroundColorAttributeName];
                        [attrs setObject:backColor forKey:NSBackgroundColorAttributeName];

                        // NSString *realString = [component substringFromIndex:colorCodeSeqLength];
                        // Mark the range of the entire sequence (escape sequence + color code sequence).
                        NSRange seqRange = (NSRange){
                            .location = componentRange.location - [escapeSeq length], .length = colorCodeSeqLength + [escapeSeq length],
                        };
                        [seqRanges addObject:[NSValue valueWithRange:seqRange]];
                        // NSLog(@"%@", [component substringWithRange:seqRange]);
                        // range_value.location = range_search.location;
                        // range_value.length = range_separator.location - range_search.location;

                        // str_b = [component substringWithRange:range_value];

                        // Mark the length of the entire color code sequence.
                    }
                }
            }
        }

        componentRange.length = [component length];

        [textStorage addAttributes:attrs range:componentRange];

        componentRange.location += componentRange.length + [escapeSeq length];
        firstPass = NO;

    } // END: for (NSString *component in components)


    // Now loop over all the discovered sequences, and apply "invisible" attributes to them.

    if([seqRanges count] > 0) {
        NSDictionary *clearAttrs =
            [NSDictionary dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:0.001], NSFontAttributeName, [NSColor clearColor], NSForegroundColorAttributeName, nil];

        for(NSValue *seqRangeValue in seqRanges) {
            NSRange seqRange = [seqRangeValue rangeValue];
            [textStorage addAttributes:clearAttrs range:seqRange];
        }
    }
}

- (void)xc_fixAttributesInRange:(NSRange)aRange {
    // This method "overrides" the method within NSTextStorage.

    // First we invoke the actual NSTextStorage method.
    // This allows it to do any normal processing.

    // Swizzling makes this look like a recursive call but it's not -- it calls the original!
    [self xc_fixAttributesInRange:aRange];

    // Then we scan for our special escape sequences, and apply desired color attributes.

    char *xcode_colors = getenv(XCODE_COLORS);
    if(xcode_colors && (strcmp(xcode_colors, "YES") == 0)) {
        ApplyANSIColors(self, aRange, XCODE_COLORS_ESCAPE);
    }
}

@end


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


@implementation XcodeColors

+ (void)load {
    //	NSLog(@"XcodeColors: %@", NSStringFromSelector(_cmd));

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken,
                  ^{
                    char *xcode_colors = getenv(XCODE_COLORS);
                    if(xcode_colors && (strcmp(xcode_colors, "YES") != 0))
                        return;

                    SEL origSel = @selector(fixAttributesInRange:);
                    SEL altSel = @selector(xc_fixAttributesInRange:);
                    NSError *error = nil;

                    if(![NSTextStorage jr_swizzleMethod:origSel withMethod:altSel error:&error]) {
                        NSLog(@"XcodeColors: Error swizzling methods: %@", error);
                        return;
                    }

                    setenv(XCODE_COLORS, "YES", 0);
                  });
}

+ (void)pluginDidLoad:(id)xcodeDirectCompatibility {
}

- (void)registerLaunchSystemDescriptions {
}


@end
