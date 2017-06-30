//
//  XQDContactsManager.h
//  Pods
//
//  Created by EriceWang on 2017/6/30.
//
//

#import <Foundation/Foundation.h>
typedef void(^AuthorizationDeniedBlock)(void);
typedef void(^CancelBlock)(void);
typedef void(^DetailInfoBlock)(NSDictionary *detail);
typedef void(^AllContactsBlock)(NSArray *allContacts);
@interface XQDContactsManager : NSObject
+ (void)showPickerController:(AuthorizationDeniedBlock)authotizationBlock cancel:(CancelBlock)cancelBlock detail:(DetailInfoBlock)detailInfoBlock allContacts:(AllContactsBlock)allContactsBlock;
+ (void)getAllContacts:(AuthorizationDeniedBlock)authotizationBlock allContacts:(AllContactsBlock)allContactsBlock;
@end
