/**
 * BAGPagingScrollView.m
 * iRefKickballLite
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without 
 * modification, are permitted provided that the following conditions are met:
 * 
 * -Redistributions of source code must retain the above copyright
 *  notice, this list of conditions and the following disclaimer.
 * -Redistributions in binary form must reproduce the above copyright
 *  notice, this list of conditions and the following disclaimer in the 
 *  documentation and/or other materials provided with the distribution.
 * -Neither the name of Benjamin Guest nor the names of its 
 *  contributors may be used to endorse or promote products derived from 
 *  this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE 
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE 
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE 
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) 
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE 
 * POSSIBILITY OF SUCH DAMAGE. 
 */

#import "BAGPagingScrollView.h"

#import <QuartzCore/QuartzCore.h>

@interface BAGPageView : UIView

@property (nonatomic, assign) CGSize originalSize;

- (UIView*)subView;
- (void)adjustSizeToBounds:(CGSize)size zoomScale:(CGFloat)zoomScale;

@end

@implementation BAGPageView

- (UIView*)subView
{
    return [[self subviews] lastObject];
}

- (void)adjustSizeToBounds:(CGSize)size zoomScale:(CGFloat)zoomScale
{
    CGRect pageRect = self.frame;
    CGFloat widthFactor = size.width / self.originalSize.width;
    CGFloat heightFactor = size.height / self.originalSize.height;
    
    CGFloat scaleFactor = 0.0;
    if (widthFactor < heightFactor) {
        scaleFactor = widthFactor;
    } else {
        scaleFactor = heightFactor;
    }
    
    pageRect.size = CGSizeMake(self.originalSize.width * scaleFactor * zoomScale, self.originalSize.height * scaleFactor * zoomScale);
    
    self.frame = pageRect;
}

- (void)setFrame:(CGRect)frame
{
    [super setFrame:frame];
    [[self subView] setFrame:self.bounds];
}

@end

#define MAX_BUFFER_SIZE 5
/*
 * Returns the correct modulus
 * http://stackoverflow.com/questions/1082917/mod-of-negative-number-is-melting-my-brain
 */
NSInteger intMod(NSInteger num, NSInteger denom) {
    NSInteger r = num % denom;
    return r < 0 ? r + denom : r;
}

// Defines a modulus when the denominator = 0
NSInteger BAGintMod(NSInteger num, NSInteger denom) {
	return (denom == 0 ? num : intMod(num, denom));
}

@interface BAGPagingScrollView ()

@property (nonatomic, assign) NSInteger viewIndex;
@property (nonatomic, strong) NSMutableDictionary* viewBuffer;
@property (nonatomic, readonly) NSUInteger numberOfPages;
@property (nonatomic, readonly) UIScrollView *scrollView;
@property (nonatomic, readonly) UIPageControl* pageControl;
@property (nonatomic, assign, getter = isZooming) BOOL zooming;
@property (nonatomic, readonly) BAGPageView* zoomingView;

@end

@implementation BAGPagingScrollView
//-----------------------------------------------------------------------------

- (id)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        [self setup];
    }
    return self;
}

//For use with Interface Builder
- (id)initWithCoder:(NSCoder *)aDecoder
{
	if((self = [super initWithCoder:aDecoder])){
		[self setup];
	}
	return self;
}

- (void)dealloc
{
    _dataSource = nil;
    _delegate = nil;
#if !__has_feature(objc_arc)
    [_viewBuffer release];
    [super dealloc];
#endif
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    
    if ([self isZooming]) {
        [_zoomingView adjustSizeToBounds:_scrollView.frame.size zoomScale:_scrollView.zoomScale];
        NSLog(@"Content size zooming: %@", NSStringFromCGSize(_zoomingView.frame.size));
        [_scrollView setContentSize:_zoomingView.frame.size];
        
        [self centerZoomingView];
        
//        [_scrollView setContentOffset:CGPointMake((_zoomingView.frame.size.width - _scrollView.frame.size.width)/2, (_zoomingView.frame.size.height - _scrollView.frame.size.height)/2)];
        
        [self notifyDelegateOfZooming];
        return;
    }
    
    [_scrollView setFrame:self.bounds];
    
    NSUInteger i = 0;
    for (BAGPageView* pageView in [_scrollView subviews]) {
        [pageView adjustSizeToBounds:_scrollView.frame.size zoomScale:1.0f];
		pageView.center = CGPointMake((.5 + i) * _scrollView.frame.size.width, _scrollView.frame.size.height / 2);
        ++i;
	}
    
    [_scrollView setContentSize:CGSizeMake(_scrollView.frame.size.width * 3, _scrollView.frame.size.height)];
    NSLog(@"Frame: %@, Content size: %@", NSStringFromCGRect(_scrollView.frame), NSStringFromCGSize(_scrollView.contentSize));
    [_scrollView setContentOffset:CGPointMake(_numberOfPages > 1 ? _scrollView.frame.size.width : 0, 0)];
    
    CGFloat height = 20;
	CGRect pageControlFrame= CGRectMake(0, _scrollView.frame.size.height - height, _scrollView.frame.size.width, height);
    [_pageControl setFrame:pageControlFrame];
}

#pragma mark Usage

/**
 * Reinitializes view and displays first page
 */
- (void)reloadData
{
    //Setup Page Control
    if ([_dataSource respondsToSelector:@selector(shouldDisplayPageControlForPagingScrollView:)]) {
        [_pageControl setHidden:![_dataSource shouldDisplayPageControlForPagingScrollView:self]];
    }

	if ([_dataSource respondsToSelector:@selector(numberOfPagesForPagingScrollView:)]) {
		_numberOfPages = [_dataSource numberOfPagesForPagingScrollView:self];
	}
    
    _pageControl.numberOfPages = _numberOfPages;
    [_scrollView setScrollEnabled:(_numberOfPages > 1)];
    
	//initialize first pages
    [self clearBuffer];
	[self goToPage:0 direction:BAGPagingDirectionUnspecified notifying:YES];
}

/**
 * This method displays the requested page without animation
 */
- (void)goToPage:(NSUInteger)page
{
    [self goToPage:page direction:BAGPagingDirectionUnspecified notifying:YES];
}

/**
 * This method animates views moving one to the left and then updates the views
 */
- (void)goToNextPage
{
	[self getNextPage];
	self.scrollView.contentOffset = CGPointMake(0, 0);
	[self.scrollView setNeedsDisplay];
	[self.scrollView setContentOffset:CGPointMake(_scrollView.frame.size.width, 0) animated:YES];
}

/**
 * This methos animates views moving one to the right and then updates the views
 */
- (void)goToPreviousPage
{
	[self getPreviousPage];
	self.scrollView.contentOffset = CGPointMake(_scrollView.frame.size.width * 2, 0);
	[self.scrollView setNeedsDisplay];
	[self.scrollView setContentOffset:CGPointMake(_scrollView.frame.size.width, 0) animated:YES];
}

#pragma mark -
#pragma mark "Private" methods

/**
 * Initial setup of view
 */
- (void)setup
{
	//init view buffer
	self.viewBuffer = [NSMutableDictionary dictionary];
	
	//setup view
	self.backgroundColor = [UIColor clearColor];
    self.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
	
	//init scroll view
	_scrollView = [[UIScrollView alloc] initWithFrame:self.bounds];
#if !__has_feature(objc_arc)
    [_scrollView autorelease];
#endif
	_scrollView.backgroundColor = [UIColor clearColor];
//    _scrollView.backgroundColor = [UIColor yellowColor];
	_scrollView.pagingEnabled = YES;
	_scrollView.delegate = self;
	_scrollView.scrollEnabled = YES;
	_scrollView.showsHorizontalScrollIndicator = NO;
    _scrollView.showsVerticalScrollIndicator = NO;
    _scrollView.alwaysBounceVertical = NO;
//    _scrollView.bounces = NO;
    _scrollView.directionalLockEnabled = YES;
    _scrollView.contentInset = UIEdgeInsetsZero;
    _scrollView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    _scrollView.minimumZoomScale = 1.0f;
    _scrollView.maximumZoomScale = 5.0f;
    _scrollView.decelerationRate = UIScrollViewDecelerationRateFast;
	
	_scrollView.contentOffset = CGPointMake(0, 0);
    
    UITapGestureRecognizer* singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    [_scrollView addGestureRecognizer:singleTap];
    
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    [doubleTap setNumberOfTapsRequired:2];
    [_scrollView addGestureRecognizer:doubleTap];
    
    // prevent double tap to trigger single tap recognizer as well
    [singleTap requireGestureRecognizerToFail:doubleTap];
	
	//add scroll view
	[self addSubview:_scrollView];
	
	//Set up page control
	CGFloat height = 20;
	CGRect pageControlFrame= CGRectMake(0, _scrollView.frame.size.height - height, _scrollView.frame.size.width, height);
	_pageControl = [[UIPageControl alloc] initWithFrame:pageControlFrame];
    _pageControl.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
#if !__has_feature(objc_arc)
    [_pageControl autorelease];
#endif
	[_pageControl addTarget:self action:@selector(pageControlValueChanged) forControlEvents:UIControlEventValueChanged];
	[self addSubview:_pageControl];
}

/**
 * Rebuilds the scrollview and displays the requested page
 */
- (void)goToPage:(NSUInteger)page direction:(BAGPagingDirection)direction notifying:(BOOL)notifying
{
	CGSize pageSize = _scrollView.frame.size;
    
    [[_scrollView subviews] makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    if (_numberOfPages > 1) {
        // Get page - 1, page and page + 1
        for (NSInteger i = 0 ; i < 3; ++i) {
            // Get the page from data source
            BAGPageView* pageView = [self viewForIndex:page - 1 + i];
            
            //Place new view in correct place
            [pageView adjustSizeToBounds:pageSize zoomScale:1.0f];
            pageView.center = CGPointMake((.5f + i) * pageSize.width, pageSize.height / 2.0f);
            
            [_scrollView addSubview:pageView];
        }
    } else if (_numberOfPages > 0) {
        BAGPageView* pageView = [self viewForIndex:page];
        
        //Place new view in correct place
        [pageView adjustSizeToBounds:pageSize zoomScale:1.0f];
        pageView.center = CGPointMake(pageSize.width / 2.0f, pageSize.height / 2.0f);
        
        [_scrollView addSubview:pageView];
    }
    
    _scrollView.contentSize = CGSizeMake(_numberOfPages > 1 ? pageSize.width * 3 : pageSize.width, pageSize.height);
	_scrollView.contentOffset = CGPointMake(_numberOfPages > 1 ? pageSize.width : 0, 0);
	[_scrollView setNeedsDisplay];
    
    NSLog(@"Content size: %@", NSStringFromCGSize(_scrollView.contentSize));
	
    _viewIndex = _currentPageIndex = page;
    _pageControl.currentPage = _currentPageIndex;
    
	[self checkViewBuffer];
    
    if (notifying) {
        if ([_delegate respondsToSelector:@selector(pagingScrollView:didShowPageAtIndex: direction:)]) {
            [_delegate pagingScrollView:self didShowPageAtIndex:_currentPageIndex direction:direction];
        }
    }
}

/**
 * Returns the UIView for the specified index, checks buffer first before
 * Asking the data source for the UIView
 */
- (BAGPageView*)viewForIndex:(NSInteger)index
{	
	if (_numberOfPages == 0) {
		return nil;
    }
		
	//check if view is allready within the view buffer
	BAGPageView *page = [_viewBuffer objectForKey:@(index)];
	
	if (!page) {
        NSUInteger pageIndex = intMod(index, _numberOfPages);
        
        UIView* view = [self.dataSource pagingScrollView:self viewForPageIndex:pageIndex];
//        view.backgroundColor = [UIColor yellowColor];
        
        //get view from data source
        page = [[BAGPageView alloc] initWithFrame:CGRectZero];
#if !__has_feature(objc_arc)
        [page autorelease];
#endif
        page.backgroundColor = [UIColor clearColor];
        page.originalSize = view.frame.size;
        [page setAutoresizesSubviews:YES];
        
        [page addSubview:view];
        
        [self checkViewBuffer];
		[_viewBuffer setObject:page forKey:@(index)];
	}
    
	return page;
}

/** 
 * Check if view buffer violates the max. view
 * buffer size and clean it up if necessary.
 *
 */
- (void)checkViewBuffer
{
    if ([[_viewBuffer allKeys] count] < MAX_BUFFER_SIZE) {
        return;
    }
    
	for (NSNumber* pageIndex in [_viewBuffer allKeys]) {
        BAGPageView* page  = [_viewBuffer objectForKey:pageIndex];
        if (![[_scrollView subviews] containsObject:page]) {
            [_viewBuffer removeObjectForKey:pageIndex];
        }
    }
}

/**
 *  This view method trys to compleaty clear the buffer
 */
- (void)clearBuffer
{
    [_viewBuffer removeAllObjects];
}

/**
 *  Called when UIPageControl is pressed
 */
- (void)pageControlValueChanged
{
	if (_pageControl.currentPage > _currentPageIndex) {
		[self goToNextPage];
	} else if (_pageControl.currentPage < _currentPageIndex) {
		[self goToPreviousPage];
    }
}

/**
 * Move view back to their correct locations
 */
-(void)resetPageViewLocations
{
    // Place views in correct place
    NSUInteger i = 0;
    for (BAGPageView* pageView in [_scrollView subviews]) {
        [pageView adjustSizeToBounds:_scrollView.frame.size zoomScale:1.0f];
		pageView.center = CGPointMake((.5 + i) * _scrollView.frame.size.width, _scrollView.frame.size.height / 2);
        ++i;
	}
    
    _pageControl.currentPage = _currentPageIndex;
}

/**
 * Shifts view pointer to views the right
 */
-(void)getNextPage
{
    ++_viewIndex;
    _currentPageIndex = intMod(_viewIndex, _numberOfPages);
    
    if ([[_scrollView subviews] count] > 1) {
        // If there are at least 3 page views in scrollview, remove the first one and add next one to the end
        [[[_scrollView subviews] objectAtIndex:0] removeFromSuperview];

        [_scrollView addSubview:[self viewForIndex:_viewIndex + 1]];
    }
    
	[self resetPageViewLocations];
    
    if ([_delegate respondsToSelector:@selector(pagingScrollView:didShowPageAtIndex: direction:)]) {
        [_delegate pagingScrollView:self didShowPageAtIndex:_currentPageIndex direction:BAGPagingDirectionRight];
    }
}
/**
 * Shifts view pointer to views to the left
 */
-(void)getPreviousPage
{
	--_viewIndex;
    _currentPageIndex = intMod(_viewIndex, _numberOfPages);
    
    if ([[_scrollView subviews] count] > 1) {
        // If there are at least 3 page views in scrollview, remove the last one and add previous one to the beginning
        [[[_scrollView subviews] lastObject] removeFromSuperview];
        [_scrollView insertSubview:[self viewForIndex:_viewIndex - 1] atIndex:0];
    }
	
	[self resetPageViewLocations];
    
    if ([_delegate respondsToSelector:@selector(pagingScrollView:didShowPageAtIndex: direction:)]) {
        [_delegate pagingScrollView:self didShowPageAtIndex:_currentPageIndex direction:BAGPagingDirectionLeft];
    }
}

#pragma mark Gesture Recognizers

- (void)handleDoubleTap:(UIGestureRecognizer *)gestureRecognizer
{    
    if (_scrollView.zoomScale > _scrollView.minimumZoomScale) {
        [_scrollView setZoomScale:_scrollView.minimumZoomScale animated:YES];
    } else {
        CGPoint center = [gestureRecognizer locationInView:_scrollView];
        CGPoint zoomingCenter = [_scrollView convertPoint:center toView:_zoomingView];
        CGRect zoomRect = [self zoomRectForScale:_scrollView.maximumZoomScale withCenter:zoomingCenter];
        NSLog(@"Zooming to rect: %@ from view rect: %@, content size: %@, content offset: %@, center: %@, zooming center: %@", NSStringFromCGRect(zoomRect), NSStringFromCGRect(_zoomingView.frame), NSStringFromCGSize(_scrollView.contentSize), NSStringFromCGPoint(_scrollView.contentOffset), NSStringFromCGPoint(center), NSStringFromCGPoint(zoomingCenter));
        [_scrollView zoomToRect:zoomRect animated:YES];
    }
}

- (void)handleTap:(UIGestureRecognizer*)gestureRecognizer
{
    if ([_delegate respondsToSelector:@selector(pagingScrollViewDidDetectTap:)]) {
        [_delegate pagingScrollViewDidDetectTap:self];
    }
}

#pragma mark -

- (CGRect)zoomRectForScale:(float)scale withCenter:(CGPoint)center
{
    CGRect zoomRect;
    
    zoomRect.size = CGSizeMake([_zoomingView frame].size.height / scale, [_zoomingView frame].size.width  / scale);
    
    zoomRect.origin = CGPointMake(center.x - ((zoomRect.size.width / 2.0)), center.y - ((zoomRect.size.height / 2.0)));
    
    return zoomRect;
}

- (void)centerZoomingView
{
    CGRect zoomingRect = _zoomingView.frame;
    
    if (zoomingRect.size.width < _scrollView.bounds.size.width) {
        zoomingRect.origin.x = (_scrollView.bounds.size.width - zoomingRect.size.width) / 2.0;
    } else {
        zoomingRect.origin.x = 0.0;
    }
    if (zoomingRect.size.height < _scrollView.bounds.size.height) {
        zoomingRect.origin.y = (_scrollView.bounds.size.height - zoomingRect.size.height) / 2.0;
    } else {
        zoomingRect.origin.y = 0.0;
    }
    _zoomingView.frame = zoomingRect;
}

- (void)notifyDelegateOfZooming
{
    if ([_delegate respondsToSelector:@selector(pagingScrollView:didZoomPageAtIndex:withRelativeOffset: relativeCenter: atScale:)]) {
        CGPoint relativeOffset = CGPointMake(_scrollView.contentOffset.x / (_scrollView.contentSize.width), _scrollView.contentOffset.y / (_scrollView.contentSize.height));
        
        CGPoint center = [_zoomingView convertPoint:_scrollView.center fromView:_scrollView];
        CGPoint relativeCenter = CGPointMake(relativeOffset.x + (center.x * _scrollView.zoomScale / _zoomingView.frame.size.width), relativeOffset.y + (center.y * _scrollView.zoomScale / _zoomingView.frame.size.height));
        NSLog(@"End Dragging: current offset: %@, relative offset: %@, relative center: %@, scale: %.2f", NSStringFromCGPoint(_scrollView.contentOffset), NSStringFromCGPoint(relativeOffset), NSStringFromCGPoint(relativeCenter), _scrollView.zoomScale);
    
        [_delegate pagingScrollView:self didZoomPageAtIndex:_currentPageIndex withRelativeOffset:relativeOffset relativeCenter:relativeCenter atScale:_scrollView.zoomScale];
    }
}

#pragma mark -
#pragma mark UIScrollViewDelegate
//-----------------------------------------------------------------------------

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    if (![self isZooming]) {
        //Determine if we are on Previous, Current or Next UIView
        CGFloat contentOffset = scrollView.contentOffset.x / scrollView.frame.size.width;
            
        if (contentOffset < 0.5) {
            [self getPreviousPage];
        } else if(contentOffset > 1.5) {
            [self getNextPage];
        }
        
        scrollView.contentOffset = CGPointMake(scrollView.frame.size.width, 0);
        [scrollView setNeedsDisplay];
    }
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView
{
    BAGPageView* newZoomingView = [self viewForIndex:_viewIndex];
    if (newZoomingView != _zoomingView) {
//        [self goToPage:_currentPageIndex direction:BAGPagingDirectionUnspecified notifying:NO];
        _zoomingView = newZoomingView;
    }
    
    return _zoomingView;
}

- (void)scrollViewWillBeginZooming:(UIScrollView *)scrollView withView:(UIView *)view
{
    if (![self isZooming]) {
        [self setZooming:YES];
        [_pageControl setHidden:YES];
        
        [scrollView setBounces:NO];
        [scrollView setPagingEnabled:NO];
        [scrollView setScrollEnabled:YES];
        
        [scrollView setContentSize:_zoomingView.frame.size];
        [scrollView setContentOffset:CGPointMake(0, 0)];
        
        NSLog(@"Content size before zooming: %@", NSStringFromCGSize(_scrollView.contentSize));
        
        [[scrollView subviews] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            if (obj != _zoomingView) {
                [obj removeFromSuperview];
            }
        }];
    }
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView
{
    [self centerZoomingView];
}

- (void)scrollViewDidEndZooming:(UIScrollView *)scrollView withView:(UIView *)view atScale:(CGFloat)scale
{
    if (scale > 1.0f) {
        [scrollView setContentSize:_zoomingView.frame.size];
        NSLog(@"Content size after zooming: %@", NSStringFromCGSize(_scrollView.contentSize));
        [self notifyDelegateOfZooming];
    } else {
        [self setZooming:NO];
        [_scrollView setScrollEnabled:(_numberOfPages > 1)];
        [_scrollView setPagingEnabled:YES];
        
        if ([_dataSource respondsToSelector:@selector(shouldDisplayPageControlForPagingScrollView:)]) {
            [_pageControl setHidden:![_dataSource shouldDisplayPageControlForPagingScrollView:self]];
        } else {
            [_pageControl setHidden:NO];
        }
                
        NSLog(@"Restored original zoom scale");
        if ([_delegate respondsToSelector:@selector(pagingScrollView:didZoomPageAtIndex:withRelativeOffset:relativeCenter:atScale:)]) {
            [_delegate pagingScrollView:self didZoomPageAtIndex:_currentPageIndex withRelativeOffset:CGPointMake(0, 0) relativeCenter:CGPointMake(0.5, 0.5) atScale:scale];
        }
        
        [self goToPage:_currentPageIndex direction:BAGPagingDirectionUnspecified notifying:NO];
    }
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    if ([self isZooming]) {
        [self notifyDelegateOfZooming];
    }
}

@end