//
//  Created by Jesse Squires
//  http://www.hexedbits.com
//
//
//  Documentation
//  http://cocoadocs.org/docsets/JSMessagesViewController
//
//
//  The MIT License
//  Copyright (c) 2014 Jesse Squires
//  http://opensource.org/licenses/MIT
//

#import "JSQMessagesViewController.h"

#import <DAKeyboardControl/DAKeyboardControl.h>

#import "JSQMessageData.h"
#import "JSQMessage.h"

#import "JSQMessagesCollectionViewCellIncoming.h"
#import "JSQMessagesCollectionViewCellOutgoing.h"

#import "JSQMessagesToolbarContentView.h"
#import "JSQMessagesInputToolbar.h"
#import "JSQMessagesComposerTextView.h"

#import "JSQMessagesTimestampFormatter.h"

#import "NSString+JSQMessages.h"


static void * kJSQMessagesKeyValueObservingContext = &kJSQMessagesKeyValueObservingContext;



@interface JSQMessagesViewController () <JSQMessagesInputToolbarDelegate, UITextViewDelegate>

@property (weak, nonatomic) IBOutlet JSQMessagesCollectionView *collectionView;
@property (weak, nonatomic) IBOutlet JSQMessagesInputToolbar *inputToolbar;

@property (weak, nonatomic) IBOutlet NSLayoutConstraint *toolbarHeightContraint;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *toolbarBottomLayoutGuide;

- (void)jsq_prepareMessagesViewController;

- (void)jsq_prepareForRotation;

- (JSQMessage *)jsq_currentlyComposedMessage;

- (void)jsq_configureKeyboardControl;
- (void)jsq_updateKeyboardTriggerOffset;

- (BOOL)jsq_inputToolbarHasReachedMaximumHeight;
- (void)jsq_adjustInputToolbarForComposerTextViewContentSizeChange:(CGFloat)dy;
- (void)jsq_adjustInputToolbarHeightConstraintByDelta:(CGFloat)dy;
- (void)jsq_scrollComposerTextViewToBottomAnimated:(BOOL)animated;

- (void)jsq_updateCollectionViewInsets;
- (void)jsq_setCollectionViewInsetsTopValue:(CGFloat)top bottomValue:(CGFloat)bottom;

- (void)jsq_addObservers;
- (void)jsq_removeObservers;

@end



@implementation JSQMessagesViewController

#pragma mark - Class methods

+ (UINib *)nib
{
    return [UINib nibWithNibName:NSStringFromClass([JSQMessagesViewController class])
                          bundle:[NSBundle mainBundle]];
}

+ (instancetype)messagesViewController
{
    return [[[self class] alloc] initWithNibName:NSStringFromClass([JSQMessagesViewController class])
                                          bundle:[NSBundle mainBundle]];
}

#pragma mark - Initialization

- (void)jsq_prepareMessagesViewController
{
    self.view.backgroundColor = [UIColor whiteColor];
    
    self.toolbarHeightContraint.constant = kJSQMessagesInputToolbarHeightDefault;
    
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    
    self.inputToolbar.delegate = self;
    self.inputToolbar.contentView.textView.placeHolder = NSLocalizedString(@"New Message", @"Placeholder text for the message input text view");
    self.inputToolbar.contentView.textView.delegate = self;
    
    self.sender = @"JSQDefaultSender";
    
    self.autoScrollsToMostRecentMessage = YES;
    
    self.outgoingCellIdentifier = [JSQMessagesCollectionViewCellOutgoing cellReuseIdentifier];
    self.incomingCellIdentifier = [JSQMessagesCollectionViewCellIncoming cellReuseIdentifier];
    
    [[JSQMessagesCollectionViewCell appearance] setFont:[UIFont systemFontOfSize:15.0f]];
    
    [self jsq_updateCollectionViewInsets];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        [[NSBundle mainBundle] loadNibNamed:NSStringFromClass([JSQMessagesViewController class])
                                      owner:self
                                    options:nil];
    }
    return self;
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self jsq_prepareMessagesViewController];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.view layoutIfNeeded];
    [self.collectionView.collectionViewLayout invalidateLayout];
    
    if (self.autoScrollsToMostRecentMessage) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self scrollToBottomAnimated:NO];
            [self.collectionView.collectionViewLayout invalidateLayout];
        });
    }
    
    [self jsq_updateKeyboardTriggerOffset];
    [self jsq_configureKeyboardControl];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self jsq_addObservers];
    
    self.collectionView.collectionViewLayout.springinessEnabled = YES;
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self.view removeKeyboardControl];
    [self jsq_removeObservers];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    NSLog(@"%s MEMORY WARNING!", __PRETTY_FUNCTION__);
}

#pragma mark - View rotation

- (BOOL)shouldAutorotate
{
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations
{
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
        return UIInterfaceOrientationMaskAllButUpsideDown;
    }
    return UIInterfaceOrientationMaskAll;
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    [super willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
    [self jsq_prepareForRotation];
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    [super willAnimateRotationToInterfaceOrientation:toInterfaceOrientation duration:duration];
    [self jsq_prepareForRotation];
    
    // TODO: keyboard
}

- (void)jsq_prepareForRotation
{
    [self.collectionView.collectionViewLayout invalidateLayout];
}

#pragma mark - Messages view controller

- (void)didPressSendButton:(UIButton *)sender withMessage:(JSQMessage *)message { }

- (void)didPressAccessoryButton:(UIButton *)sender { }

- (void)finishSending
{
    UITextView *textView = self.inputToolbar.contentView.textView;
    textView.text = nil;
    
    [self.inputToolbar toggleSendButtonEnabled];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:UITextViewTextDidChangeNotification object:textView];
    
    [self.collectionView reloadData];
    
    if (self.autoScrollsToMostRecentMessage) {
        [self scrollToBottomAnimated:YES];
    }
}

- (void)scrollToBottomAnimated:(BOOL)animated
{
    if ([self.collectionView numberOfSections] == 0) {
        return;
    }
    
    NSInteger items = [self.collectionView numberOfItemsInSection:0];
    
    if (items > 0) {
        [self.collectionView scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:items - 1 inSection:0]
                                    atScrollPosition:UICollectionViewScrollPositionBottom
                                            animated:animated];
    }
}

#pragma mark - JSQMessages collection view data source

- (id<JSQMessageData>)collectionView:(JSQMessagesCollectionView *)collectionView messageDataForItemAtIndexPath:(NSIndexPath *)indexPath
{
    NSAssert(NO, @"ERROR: required method not implemented: %s", __PRETTY_FUNCTION__);
    return nil;
}

- (UIImageView *)collectionView:(JSQMessagesCollectionView *)collectionView sender:(NSString *)sender  bubbleImageViewForItemAtIndexPath:(NSIndexPath *)indexPath
{
    NSAssert(NO, @"ERROR: required method not implemented: %s", __PRETTY_FUNCTION__);
    return nil;
}

- (UIImageView *)collectionView:(JSQMessagesCollectionView *)collectionView sender:(NSString *)sender  avatarImageViewForItemAtIndexPath:(NSIndexPath *)indexPath
{
    NSAssert(NO, @"ERROR: required method not implemented: %s", __PRETTY_FUNCTION__);
    return nil;
}

- (NSAttributedString *)collectionView:(JSQMessagesCollectionView *)collectionView sender:(NSString *)sender attributedTextForCellTopLabelAtIndexPath:(NSIndexPath *)indexPath
{
    return nil;
}

- (NSAttributedString *)collectionView:(JSQMessagesCollectionView *)collectionView sender:(NSString *)sender attributedTextForMessageBubbleTopLabelAtIndexPath:(NSIndexPath *)indexPath
{
    return nil;
}

- (NSAttributedString *)collectionView:(JSQMessagesCollectionView *)collectionView sender:(NSString *)sender attributedTextForCellBottomLabelAtIndexPath:(NSIndexPath *)indexPath
{
    return nil;
}

#pragma mark - Collection view data source

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return 0;
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    return 1;
}

- (UICollectionViewCell *)collectionView:(JSQMessagesCollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    id<JSQMessageData> messageData = [collectionView.dataSource collectionView:collectionView messageDataForItemAtIndexPath:indexPath];
    
    NSString *messageSender = [messageData sender];
    BOOL isOutgoingMessage = [messageSender isEqualToString:self.sender];
    
    NSString *cellIdentifier = isOutgoingMessage ? self.outgoingCellIdentifier : self.incomingCellIdentifier;
    JSQMessagesCollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:cellIdentifier forIndexPath:indexPath];
    
    cell.textView.text = [messageData text];
    
    cell.messageBubbleImageView = [collectionView.dataSource collectionView:collectionView
                                                                     sender:messageSender bubbleImageViewForItemAtIndexPath:indexPath];
    
    cell.avatarImageView = [collectionView.dataSource collectionView:collectionView
                                                              sender:messageSender avatarImageViewForItemAtIndexPath:indexPath];
    
    cell.cellTopLabel.attributedText = [collectionView.dataSource collectionView:collectionView
                                                                          sender:messageSender attributedTextForCellTopLabelAtIndexPath:indexPath];
    
    cell.messageBubbleTopLabel.attributedText = [collectionView.dataSource collectionView:collectionView
                                                                                   sender:messageSender attributedTextForMessageBubbleTopLabelAtIndexPath:indexPath];
    
    cell.cellBottomLabel.attributedText = [collectionView.dataSource collectionView:collectionView
                                                                             sender:messageSender attributedTextForCellBottomLabelAtIndexPath:indexPath];
    
    cell.backgroundColor = [UIColor clearColor];
    
    CGFloat bubbleTopLabelInset = 60.0f;
    
    if (isOutgoingMessage) {
        cell.textView.textColor = [UIColor whiteColor];
        cell.messageBubbleTopLabel.textInsets = UIEdgeInsetsMake(0.0f, 0.0f, 0.0f, bubbleTopLabelInset);
    }
    else {
        cell.textView.textColor = [UIColor blackColor];
        cell.messageBubbleTopLabel.textInsets = UIEdgeInsetsMake(0.0f, bubbleTopLabelInset, 0.0f, 0.0f);
    }
    
    // TODO: data detectors
    //cell.textView.dataDetectorTypes = UIDataDetectorTypeAll;
    cell.textView.selectable = NO;
    
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
           viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)indexPath
{
    return nil; // TODO: load previous messages, typing indicator
}

#pragma mark - Collection view delegate

// TODO: copy & paste

#pragma mark - Collection view delegate flow layout

- (CGSize)collectionView:(JSQMessagesCollectionView *)collectionView
                  layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    CGFloat textVerticalPadding = collectionViewLayout.messageBubbleTextContainerInsets.top + collectionViewLayout.messageBubbleTextContainerInsets.bottom;
    
    CGSize bubbleSize = [collectionViewLayout messageBubbleSizeForItemAtIndexPath:indexPath];
    
    CGFloat cellHeight = bubbleSize.height;
    cellHeight += textVerticalPadding;
    cellHeight += [self collectionView:collectionView layout:collectionViewLayout heightForCellTopLabelAtIndexPath:indexPath];
    cellHeight += [self collectionView:collectionView layout:collectionViewLayout heightForMessageBubbleTopLabelAtIndexPath:indexPath];
    cellHeight += [self collectionView:collectionView layout:collectionViewLayout heightForCellBottomLabelAtIndexPath:indexPath];
    
    return CGSizeMake(collectionViewLayout.itemWidth, cellHeight);
}

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                   layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout heightForCellTopLabelAtIndexPath:(NSIndexPath *)indexPath
{
    return 0.0f;
}

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                   layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout heightForMessageBubbleTopLabelAtIndexPath:(NSIndexPath *)indexPath
{
    return 0.0f;
}

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                   layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout heightForCellBottomLabelAtIndexPath:(NSIndexPath *)indexPath
{
    return 0.0f;
}

#pragma mark - Input toolbar delegate

- (void)messagesInputToolbar:(JSQMessagesInputToolbar *)toolbar didPressLeftBarButton:(UIButton *)sender
{
    if (toolbar.sendButtonOnRight) {
        [self didPressAccessoryButton:sender];
    }
    else {
        [self didPressSendButton:sender withMessage:[self jsq_currentlyComposedMessage]];
    }
}

- (void)messagesInputToolbar:(JSQMessagesInputToolbar *)toolbar didPressRightBarButton:(UIButton *)sender
{
    if (toolbar.sendButtonOnRight) {
        [self didPressSendButton:sender withMessage:[self jsq_currentlyComposedMessage]];
    }
    else {
        [self didPressAccessoryButton:sender];
    }
}

- (JSQMessage *)jsq_currentlyComposedMessage
{
    return [JSQMessage messageWithText:[self.inputToolbar.contentView.textView.text jsq_stringByTrimingWhitespace]
                                sender:self.sender];
}

#pragma mark - Text view delegate

- (void)textViewDidBeginEditing:(UITextView *)textView
{
    [textView becomeFirstResponder];
    
    if (self.autoScrollsToMostRecentMessage) {
        [self scrollToBottomAnimated:YES];
    }
}

- (void)textViewDidChange:(UITextView *)textView
{
    [self.inputToolbar toggleSendButtonEnabled];
}

- (void)textViewDidEndEditing:(UITextView *)textView
{
    [textView resignFirstResponder];
}

#pragma mark - Key-value observing

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == kJSQMessagesKeyValueObservingContext) {
        
        if (object == self.inputToolbar.contentView.textView
            && [keyPath isEqualToString:NSStringFromSelector(@selector(contentSize))]) {
            
            CGSize oldContentSize = [[change objectForKey:NSKeyValueChangeOldKey] CGSizeValue];
            CGSize newContentSize = [[change objectForKey:NSKeyValueChangeNewKey] CGSizeValue];
            
            CGFloat dy = newContentSize.height - oldContentSize.height;
        
            [self jsq_adjustInputToolbarForComposerTextViewContentSizeChange:dy];
        }
    }
}

#pragma mark - Keyboard control utilities

- (void)jsq_configureKeyboardControl
{
    __weak JSQMessagesViewController *weakSelf = self;
    __weak UIView *weakView = self.view;
    __weak JSQMessagesInputToolbar *weakInputToolbar = self.inputToolbar;
    __weak NSLayoutConstraint *weakToolbarBottomLayoutGuide = self.toolbarBottomLayoutGuide;
    
    [self.view addKeyboardPanningWithActionHandler:^(CGRect keyboardFrameInView) {
        CGRect newToolbarFrame = weakInputToolbar.frame;
        newToolbarFrame.origin.y = CGRectGetMinY(keyboardFrameInView) - CGRectGetHeight(newToolbarFrame);
        weakInputToolbar.frame = newToolbarFrame;
        
        CGFloat heightFromBottom = CGRectGetHeight(weakView.frame) - CGRectGetMinY(keyboardFrameInView);
        weakToolbarBottomLayoutGuide.constant = heightFromBottom;
        [weakSelf.view setNeedsUpdateConstraints];
        
        [weakSelf jsq_updateCollectionViewInsets];
    }];
}

- (void)jsq_updateKeyboardTriggerOffset
{
    self.view.keyboardTriggerOffset = CGRectGetHeight(self.inputToolbar.bounds);
}

#pragma mark - Input toolbar utilities

- (BOOL)jsq_inputToolbarHasReachedMaximumHeight
{
    return (CGRectGetMinY(self.inputToolbar.frame) == self.topLayoutGuide.length);
}

- (void)jsq_adjustInputToolbarForComposerTextViewContentSizeChange:(CGFloat)dy
{
    BOOL contentSizeIsIncreasing = (dy > 0);
    
    if ([self jsq_inputToolbarHasReachedMaximumHeight]) {
        BOOL contentOffsetIsPositive = (self.inputToolbar.contentView.textView.contentOffset.y > 0);
        
        if (contentSizeIsIncreasing || contentOffsetIsPositive) {
            [self jsq_scrollComposerTextViewToBottomAnimated:YES];
            return;
        }
    }
    
    CGFloat toolbarOriginY = CGRectGetMinY(self.inputToolbar.frame);
    CGFloat newToolbarOriginY = toolbarOriginY - dy;
    
    //  attempted to increase origin.Y above topLayoutGuide
    if (newToolbarOriginY <= self.topLayoutGuide.length) {
        dy = toolbarOriginY - self.topLayoutGuide.length;
        [self jsq_scrollComposerTextViewToBottomAnimated:YES];
    }
    
    [self jsq_adjustInputToolbarHeightConstraintByDelta:dy];
    
    [self jsq_updateKeyboardTriggerOffset];
    
    if (dy < 0) {
        [self jsq_scrollComposerTextViewToBottomAnimated:NO];
    }
}

- (void)jsq_adjustInputToolbarHeightConstraintByDelta:(CGFloat)dy
{
    self.toolbarHeightContraint.constant += dy;
    
    if (self.toolbarHeightContraint.constant < kJSQMessagesInputToolbarHeightDefault) {
        self.toolbarHeightContraint.constant = kJSQMessagesInputToolbarHeightDefault;
    }
    
    [self.view setNeedsUpdateConstraints];
    [self.view layoutIfNeeded];
}

- (void)jsq_scrollComposerTextViewToBottomAnimated:(BOOL)animated
{
    UITextView *textView = self.inputToolbar.contentView.textView;
    CGPoint contentOffsetToShowLastLine = CGPointMake(0.0f, textView.contentSize.height - CGRectGetHeight(textView.bounds));
    
    if (!animated) {
        textView.contentOffset = contentOffsetToShowLastLine;
        return;
    }
    
    [UIView animateWithDuration:0.01
                          delay:0.01
                        options:UIViewAnimationOptionCurveLinear
                     animations:^{
                         textView.contentOffset = contentOffsetToShowLastLine;
                     }
                     completion:nil];
}

#pragma mark - Collection view utilities

- (void)jsq_updateCollectionViewInsets
{
    [self jsq_setCollectionViewInsetsTopValue:self.topLayoutGuide.length
                                  bottomValue:CGRectGetHeight(self.collectionView.frame) - CGRectGetMinY(self.inputToolbar.frame)];
}

- (void)jsq_setCollectionViewInsetsTopValue:(CGFloat)top bottomValue:(CGFloat)bottom
{
    UIEdgeInsets insets = UIEdgeInsetsMake(top, 0.0f, bottom, 0.0f);
    self.collectionView.contentInset = insets;
    self.collectionView.scrollIndicatorInsets = insets;
}

#pragma mark - Utilities

- (void)jsq_addObservers
{
    [self.inputToolbar.contentView.textView addObserver:self
                                             forKeyPath:NSStringFromSelector(@selector(contentSize))
                                                options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew
                                                context:kJSQMessagesKeyValueObservingContext];
}

- (void)jsq_removeObservers
{
    @try {
        [self.inputToolbar.contentView.textView removeObserver:self
                                                    forKeyPath:NSStringFromSelector(@selector(contentSize))
                                                       context:kJSQMessagesKeyValueObservingContext];
    }
    @catch (NSException *exception) {
        NSLog(@"%s EXCEPTION CAUGHT : %@, %@", __PRETTY_FUNCTION__, exception, [exception userInfo]);
    }
}

@end
