
//
//  PPTextRenderer.m
//  PPAsyncDrawingKit
//
//  Created by DSKcpp on 2016/10/14.
//  Copyright © 2016年 DSKcpp. All rights reserved.
//

#import "PPTextRenderer.h"
#import "PPTextLayoutLine.h"
#import "PPTextAttachment.h"
#import "NSAttributedString+PPExtendedAttributedString.h"
#import "PPTextLayout.h"
#import "PPAsyncDrawingView.h"
#import "UIImage+PPAsyncDrawingKit.h"

struct PPTextRendererEventDelegateFlags {
    BOOL didPressHighlightRange;
    BOOL contextViewForTextRenderer;
    BOOL didPressTextBackground;
};
typedef struct PPTextRendererEventDelegateFlags PPTextRendererEventDelegateFlags;

@interface PPTextRenderer ()
{
    CGPoint _touchesBeginPoint;
    PPTextRendererEventDelegateFlags _eventDelegateFlags;
    PPTextHighlightRange *_savedPressingHighlightRange;
}
@end

@implementation PPTextRenderer

+ (PPTextRenderer *)textRendererWithTextLayout:(PPTextLayout *)textLayout
{
    return [[PPTextRenderer alloc] initWithTextLayout:textLayout];
}

- (instancetype)initWithTextLayout:(PPTextLayout *)textLayout
{
    if (self = [super init]) {
        _textLayout = textLayout;
    }
    return self;
}

#pragma mark - Event
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    PPAsyncDrawingView *touchView = self.eventDelegateContextView;
    if (!touchView) {
        return;
    }
    
    NSSet<UITouch *> * _touches = [event touchesForView:touchView];
    UITouch *touch = _touches.anyObject;
    CGPoint point = CGPointZero;
    if (touch) {
        point = [touch locationInView:touchView];
    }
    point = [self convertPointToLayout:point];
    PPTextHighlightRange *range = [self highlightRangeForLayoutLocation:point];
    if (range) {
        self.pressingHighlightRange = range;
        touchView.drawingType = PPAsyncDrawingTypeTouch;
        [touchView setNeedsDisplay];
    } else if (self.textLayout.highlighttextBackground) {
        touchView.drawingType = PPAsyncDrawingTypeTouch;
        self.highlight = YES;
        [touchView setNeedsDisplay];
    }
    _touchesBeginPoint = point;
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    PPAsyncDrawingView *touchView = self.eventDelegateContextView;
    UITouch *touch = touches.anyObject;
    CGPoint point = CGPointZero;
    if (touch) {
        point = [touch locationInView:touchView];
    }
//    CGPoint touchesBeginPoint = _touchesBeginPoint;
    
    BOOL touchInside = YES;
//    CGFloat left = touchView.bounds.size.width - touchesBeginPoint.x;
//    if (point.x > touchesBeginPoint.x) {
//        touchInside = NO;
//    }
    if (!touchInside) {
        PPTextHighlightRange *r = _pressingHighlightRange;
        if (r) {
            _pressingHighlightRange = nil;
            _savedPressingHighlightRange = r;
            touchView.drawingType = PPAsyncDrawingTypeTouch;
            [touchView setNeedsDisplay];
        }
    } else {
        if (_savedPressingHighlightRange) {
            _pressingHighlightRange = _savedPressingHighlightRange;
            touchView.drawingType = PPAsyncDrawingTypeTouch;
            [touchView setNeedsDisplay];
        }
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    _savedPressingHighlightRange = nil;
    PPTextHighlightRange *high = self.pressingHighlightRange;
    if (high) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self eventDelegateDidPressHighlightRange:high];
        });
        self.pressingHighlightRange = nil;
        PPAsyncDrawingView *touchView = self.eventDelegateContextView;
        touchView.drawingType = PPAsyncDrawingTypeTouch;
        [touchView setNeedsDisplay];
    } else if (self.textLayout.highlighttextBackground) {
        PPAsyncDrawingView *touchView = self.eventDelegateContextView;
        touchView.drawingType = PPAsyncDrawingTypeTouch;
        self.highlight = NO;
        [touchView setNeedsDisplay];
        
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    _savedPressingHighlightRange = nil;
    if (_pressingHighlightRange) {
        _pressingHighlightRange = nil;
        PPAsyncDrawingView *touchView = self.eventDelegateContextView;
        touchView.drawingType = PPAsyncDrawingTypeTouch;
        [touchView setNeedsDisplay];
    } else if (self.textLayout.highlighttextBackground) {
        PPAsyncDrawingView *touchView = self.eventDelegateContextView;
        touchView.drawingType = PPAsyncDrawingTypeTouch;
        self.highlight = NO;
        [touchView setNeedsDisplay];
    }
}

#pragma mark - getter & setter

- (void)setEventDelegate:(id<PPTextRendererEventDelegate>)eventDelegate
{
    _eventDelegate = eventDelegate;
    _eventDelegateFlags.contextViewForTextRenderer = [eventDelegate respondsToSelector:@selector(contextViewForTextRenderer:)];
    _eventDelegateFlags.didPressHighlightRange = [eventDelegate respondsToSelector:@selector(textRenderer:didPressHighlightRange:)];
    _eventDelegateFlags.didPressTextBackground = [eventDelegate respondsToSelector:@selector(textRenderer:didPressTextBackground:)];
}

#pragma mark - Layout
- (CGRect)frame
{
    return self.textLayout.frame;
}

- (CGPoint)drawingOrigin
{
    return self.textLayout.drawOrigin;
}

@end

@implementation PPTextRenderer (PPTextRendererDrawing)
- (void)drawInContext:(CGContextRef)context
{
    [self drawInContext:context visibleRect:CGRectNull placeAttachments:YES];
}

- (void)drawInContext:(CGContextRef)context visibleRect:(CGRect)visibleRect placeAttachments:(BOOL)placeAttachments
{   
    NSAttributedString *attributedString = self.textLayout.attributedString;
    if (!(attributedString.length > 1)) {
        return;
    }
    
    if (!CGRectIsNull(visibleRect)) {
        self.textLayout.maxSize = visibleRect.size;
    }
    
    PPTextLayoutFrame *layoutFrame = self.textLayout.layoutFrame;
    if ([PPTextRenderer debugModeEnabled]) {
        [self drawdebugMode:layoutFrame context:context];
    }
    PPTextHighlightRange *highlightRange = self.pressingHighlightRange;
    if (highlightRange) {
        [self.textLayout enumerateEnclosingRectsForCharacterRange:highlightRange.range usingBlock:^(CGRect rect, BOOL * _Nonnull stop) {
            CGRect drawRect = [self convertRectFromLayout:rect];
            [self drawBorder:highlightRange rect:drawRect context:context];
        }];
    }
    
    PPTextBackground *highlightTextBackground = self.textLayout.highlighttextBackground;
    if (highlightTextBackground && self.highlight) {
        [self drawTextBackground:highlightTextBackground context:context];
    }
    
    [self drawTextInContext:context layout:self.textLayout];
    if (placeAttachments) {
        [self drawAttachmentsWithAttributedString:attributedString layoutFrame:layoutFrame context:context];
    }
}

- (void)drawTextInContext:(CGContextRef)context layout:(PPTextLayout *)textLayout
{
    CGContextSaveGState(context);
    CGContextTranslateCTM(context, self.drawingOrigin.x, self.drawingOrigin.y + self.frame.size.height);
    CGContextScaleCTM(context, 1.0, -1.0);
    
    for (PPTextLayoutLine *line in textLayout.layoutFrame.lineFragments) {
        CGPoint position = line.baselineOrigin;
        position = [textLayout convertPointToCoreText:position];
        CGContextSetTextMatrix(context, CGAffineTransformIdentity);
        CGContextSetTextPosition(context, position.x, position.y);
        CTLineDraw(line.lineRef, context);
    }
    CGContextRestoreGState(context);
}

- (void)drawAttachmentsWithAttributedString:(NSAttributedString *)attributedString layoutFrame:(PPTextLayoutFrame *)layoutFrame context:(CGContextRef)context
{
    [layoutFrame.lineFragments enumerateObjectsUsingBlock:^(PPTextLayoutLine * _Nonnull line, NSUInteger idx, BOOL * _Nonnull stop) {
        [line enumerateLayoutRunsUsingBlock:^(NSDictionary *attributes, NSRange range) {
            PPTextAttachment *textAttachment = [attributes objectForKey:PPTextAttachmentAttributeName];
            if (textAttachment) {
                CGPoint origin = [line baselineOriginForCharacterAtIndex:range.location];
                CGSize size = textAttachment.contentSize;
                CGRect rect = (CGRect){(CGPoint)origin, (CGSize)size};
                rect.origin.y -= textAttachment.ascentForLayout;
                UIImage *content = textAttachment.contents;
                rect = [self convertRectFromLayout:rect];
                [content pp_drawInRect:rect contentMode:textAttachment.contentType withContext:context];
            }
        }];
    }];
}

- (void)drawTextBackground:(PPTextBackground *)textBackground context:(CGContextRef)context
{
    CGPoint origin = self.drawingOrigin;
    CGSize size = self.textLayout.maxSize;
    CGContextSaveGState(context);
    CGContextSetFillColorWithColor(context, textBackground.backgroundColor.CGColor);
    CGContextFillRect(context, CGRectMake(origin.x, origin.y, size.width, size.height));
    CGContextRestoreGState(context);
}

- (void)drawBorder:(PPTextHighlightRange *)highlightRange rect:(CGRect)rect context:(CGContextRef)context
{
    PPTextBorder *textBorder = highlightRange.border;
    if (textBorder) {
        CGColorRef color;
        if (textBorder.fillColor) {
            color = textBorder.fillColor.CGColor;
        } else {
            color = [UIColor colorWithWhite:0.5f alpha:1.0f].CGColor;
        }
        CGContextSetFillColorWithColor(context, color);
        CGContextBeginPath(context);
        CGFloat x = rect.origin.x;
        CGFloat y = rect.origin.y;
        CGFloat width = rect.size.width;
        CGFloat height = rect.size.height;
        CGFloat radius = textBorder.cornerRadius;
        CGContextMoveToPoint(context, x + radius, y);
        x += width;
        CGContextAddLineToPoint(context, x + width - radius, y);
        CGContextAddArc(context, x - radius, y + radius, radius,  -0.5 * M_PI, 0.0f, 0);
        y += height;
        CGContextAddLineToPoint(context, x, y);
        CGContextAddArc(context, x - radius, y - radius, radius, 0, 0.5 * M_PI, 0);
        x -= width;
        CGContextAddLineToPoint(context, x + radius, y);
        CGContextAddArc(context, x + radius, y - radius, radius, 0.5 * M_PI, M_PI, 0);
        y -= height;
        CGContextAddLineToPoint(context, x, y);
        CGContextAddArc(context, x + radius, y + radius, radius, M_PI, 1.5 * M_PI, 0);
        CGContextClosePath(context);
        CGContextFillPath(context);
    }
}

@end


@implementation PPTextRenderer (PPTextRendererCoordinates)
- (CGPoint)convertPointToLayout:(CGPoint)point
{
    CGPoint drawingOrigin = self.drawingOrigin;
    return CGPointMake(point.x - drawingOrigin.x, point.y - drawingOrigin.y);
}

- (CGPoint)convertPointFromLayout:(CGPoint)point
{
    CGPoint drawingOrigin = self.drawingOrigin;
    return CGPointMake(point.x + drawingOrigin.x, point.y + drawingOrigin.y);
}

- (CGRect)convertRectToLayout:(CGRect)rect
{
    if (CGRectIsNull(rect)) {
        
    } else {
        rect.origin = [self convertPointToLayout:rect.origin];
    }
    return rect;
}

- (CGRect)convertRectFromLayout:(CGRect)rect
{
    if (CGRectIsNull(rect)) {
        
    } else {
        rect.origin = [self convertPointFromLayout:rect.origin];
    }
    return rect;
}

@end

@implementation PPTextRenderer (PPTextRendererEvents)
- (PPAsyncDrawingView *)eventDelegateContextView
{
    if (_eventDelegateFlags.contextViewForTextRenderer) {
        return [_eventDelegate contextViewForTextRenderer:self];
    }
    return nil;
}

- (void)eventDelegateDidPressHighlightRange:(PPTextHighlightRange *)highlightRange
{
    if (_eventDelegateFlags.didPressHighlightRange) {
        [_eventDelegate textRenderer:self didPressHighlightRange:highlightRange];
    }
}

- (void)eventDelegateDidPressTextBackground:(PPTextBackground *)textBackground
{
    if (_eventDelegateFlags.didPressTextBackground) {
        [_eventDelegate textRenderer:self didPressTextBackground:textBackground];
    }
}

- (PPTextHighlightRange *)highlightRangeForLayoutLocation:(CGPoint)location
{
    __block PPTextHighlightRange *r;
    __weak typeof(self) weakSelf = self;
    NSAttributedString *attributedString = self.textLayout.attributedString;
    [attributedString enumerateAttribute:PPTextHighlightRangeAttributeName inRange:attributedString.pp_stringRange options:kNilOptions usingBlock:^(id  _Nullable value, NSRange range, BOOL * _Nonnull stop) {
        if (value) {
            [weakSelf.textLayout enumerateEnclosingRectsForCharacterRange:range usingBlock:^(CGRect rect, BOOL * _Nonnull sstop) {
                if (CGRectContainsPoint(rect, location)) {
                    r = value;
                    r.range = range;
                    *sstop = YES;
                    *stop = YES;
                }
            }];
        }
    }];
    return r;
}

@end

@implementation PPTextRenderer (PPTextRendererDebug)
static BOOL textRendererDebugModeEnabled = NO;

+ (BOOL)debugModeEnabled
{
    return textRendererDebugModeEnabled;
}

+ (void)setDebugModeEnabled:(BOOL)debugModeEnabled
{
    textRendererDebugModeEnabled = debugModeEnabled;
    UIViewController *viewController = [self visibleViewController];
    [self drawDebugInView:viewController.view];
}

+ (void)drawDebugInView:(UIView *)view
{
    NSArray<__kindof UIView *> *subviews = view.subviews;
    if (subviews.count == 0) {
        return;
    }
    [subviews enumerateObjectsUsingBlock:^(__kindof UIView * _Nonnull subview, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([subview isKindOfClass:[PPAsyncDrawingView class]]) {
            PPAsyncDrawingView *v = (PPAsyncDrawingView *)subview;
            v.drawingType = PPAsyncDrawingTypeTouch;
            [v setNeedsDisplay];
        }
        [self drawDebugInView:subview];
    }];
}

+ (UIViewController *)visibleViewController
{
    UIViewController *viewController = [UIApplication sharedApplication].keyWindow.rootViewController;
    return [self getVisibleViewControllerFrom:viewController];
}

+ (UIViewController *)getVisibleViewControllerFrom:(UIViewController *)viewController
{
    if ([viewController isKindOfClass:[UINavigationController class]]) {
        UINavigationController *navigtationController = (UINavigationController *)viewController;
        return [self getVisibleViewControllerFrom:navigtationController.visibleViewController];
    } else if ([viewController isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tabBarController = (UITabBarController *)viewController;
        return [self getVisibleViewControllerFrom:tabBarController.selectedViewController];
    } else {
        if (viewController.presentedViewController) {
            return [self getVisibleViewControllerFrom:viewController.presentedViewController];
        } else {
            return viewController;
        }
    }
}

- (void)drawdebugMode:(PPTextLayoutFrame *)layoutFrame context:(CGContextRef)context
{
    CGPoint origin = self.drawingOrigin;
    CGSize size = self.textLayout.maxSize;
    CGContextSaveGState(context);
    CGContextSetAlpha(context, 0.1f);
    CGContextSetFillColorWithColor(context, [UIColor grayColor].CGColor);
    CGContextFillRect(context, CGRectMake(origin.x, origin.y, size.width, size.height));
    CGContextRestoreGState(context);
    
    [layoutFrame.lineFragments enumerateObjectsUsingBlock:^(PPTextLayoutLine * _Nonnull line, NSUInteger idx, BOOL * _Nonnull stop) {
        CGRect rect = [self convertRectFromLayout:line.fragmentRect];
        CGContextSaveGState(context);
        CGContextSetAlpha(context, 0.5f);
        CGContextSetFillColorWithColor(context, [UIColor yellowColor].CGColor);
        CGContextFillRect(context, rect);
        
        CGContextSetAlpha(context, 1.0f);
        CGContextSetFillColorWithColor(context, [UIColor redColor].CGColor);
        CGContextFillRect(context, CGRectMake(line.baselineOrigin.x + origin.x, line.baselineOrigin.y + origin.y, rect.size.width, 0.5f));
        CGContextRestoreGState(context);
    }];
}

@end

