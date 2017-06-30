//
//  XQDContactsManager.m
//  Pods
//
//  Created by EriceWang on 2017/6/30.
//
//

@interface UIWindow (VISIBLECONTROLLER)
+ (UIViewController *)visibleViewController;
@end

@implementation UIWindow (VISIBLECONTROLLER)

+ (UIViewController *)visibleViewController {
    UIWindow *win = [UIWindow xqd_getWindow];
    UIViewController *rootViewController = win.rootViewController;
    return [UIWindow getVisibleViewControllerFrom:rootViewController];
}

+ (UIWindow*)xqd_getWindow{
    NSEnumerator *frontToBackWindows = [[[UIApplication sharedApplication]windows]reverseObjectEnumerator];
    
    for (UIWindow *window in frontToBackWindows){
        if (window.windowLevel == UIWindowLevelNormal && !window.hidden) {
            return window;
        }
    }
    return [UIApplication sharedApplication].keyWindow;
}
+ (UIViewController *) getVisibleViewControllerFrom:(UIViewController *) vc {
    if ([vc isKindOfClass:[UINavigationController class]]) {
        return [UIWindow getVisibleViewControllerFrom:[((UINavigationController *) vc) visibleViewController]];
    } else if ([vc isKindOfClass:[UITabBarController class]]) {
        return [UIWindow getVisibleViewControllerFrom:[((UITabBarController *) vc) selectedViewController]];
    } else {
        if (vc.presentedViewController) {
            return [UIWindow getVisibleViewControllerFrom:vc.presentedViewController];
        } else {
            return vc;
        }
    }
}
@end

#import "XQDContactsManager.h"
#import <AddressBook/AddressBook.h>
#import <AddressBookUI/AddressBookUI.h>
#import <ContactsUI/ContactsUI.h>
#import <objc/runtime.h>
#define IOS_OR_LATER(s)       ([[[UIDevice currentDevice] systemVersion] compare:[NSString stringWithFormat:@"%@",@(s)] options:NSNumericSearch] != NSOrderedAscending)
#define GET_NONNIL_VAL(v)   v==nil?[NSNull null]:v
#define kValidate(s)    (s && s.length)

static char cancelBlock_Key,detailBlock_Key, allContacts_key;
static XQDContactsManager *manager;

@interface XQDContactsManager ()<ABPeoplePickerNavigationControllerDelegate, CNContactPickerDelegate>
@property (strong, nonatomic) UIViewController *pickerController;
@property (assign, atomic) BOOL forbidAppear;
@property (strong, nonatomic) _Nullable dispatch_queue_t queue;
@end

@implementation XQDContactsManager

+ (instancetype)shareInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[self alloc] init];
    });
    return manager;
}
+ (void)showPickerController:(AuthorizationDeniedBlock)authotizationBlock cancel:(CancelBlock)cancelBlock detail:(DetailInfoBlock)detailInfoBlock allContacts:(AllContactsBlock)allContactsBlock {
    XQDContactsManager *manager = [XQDContactsManager shareInstance];
    if (manager.forbidAppear) {
        return;
    }
    [self getAuthorization:^(BOOL success) {
        if (!success) {
            authotizationBlock();
            return ;
        }
        [self getAllContacts:^(NSArray *all) {
            if (allContactsBlock) {
                allContactsBlock(all);
            }
        }];
        UIViewController *currentController = [UIWindow visibleViewController];
        //save block
        objc_setAssociatedObject(manager, &cancelBlock_Key, cancelBlock, OBJC_ASSOCIATION_COPY);
        objc_setAssociatedObject(manager, &detailBlock_Key, detailInfoBlock, OBJC_ASSOCIATION_COPY);
        objc_setAssociatedObject(manager, &allContacts_key, allContactsBlock, OBJC_ASSOCIATION_COPY);
        
        void(^presentController)(void) = ^() {
            [currentController presentViewController:manager.pickerController animated:YES completion:^{
                manager.forbidAppear = YES;
            }];
        };
        
        if (![NSThread isMainThread]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                presentController();
            });
        } else {
            presentController();
        }
        
    }];
}
+ (void)getAllContacts:(AuthorizationDeniedBlock)authotizationBlock allContacts:(AllContactsBlock)allContactsBlock {
    [self getAuthorization:^(BOOL success) {
        if (success) {
            [self getAllContacts:^(NSArray *contacts) {
                allContactsBlock(contacts);
            }];
        } else {
            authotizationBlock();
        }
    }];
}
- (UIViewController *)pickerController {
    if (!_pickerController) {
        if (IOS_OR_LATER(9.0)) {
            CNContactPickerViewController *contactController = [[CNContactPickerViewController alloc] init];
            contactController.delegate = self;
            _pickerController = contactController;
        } else {
            ABPeoplePickerNavigationController *picker;
            picker = [[ABPeoplePickerNavigationController alloc] init];
            picker.peoplePickerDelegate = self;
            if (IOS_OR_LATER(8.0)) {
                picker.predicateForSelectionOfPerson = [NSPredicate predicateWithValue:false];
            }
            _pickerController = picker;
        }
    }
    return _pickerController;
}
+ (void)getAuthorization:(void(^)(BOOL success))block {
    if (IOS_OR_LATER(9.0)) {
        CNAuthorizationStatus status = [CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts];
        if (status == CNAuthorizationStatusAuthorized) {//已经授权
            block(YES);
        } else if(status == CNAuthorizationStatusNotDetermined) {//尚未进行第一次授权
            CNContactStore *store = [[CNContactStore alloc] init];
            [store requestAccessForEntityType:CNEntityTypeContacts completionHandler:^(BOOL granted, NSError * _Nullable error) {
                if (granted) {
                    block(YES);
                } else {
                    block(NO);
                }
            }];
        } else {//用户未授权访问通讯录
            block(NO);
        }
    } else {
        ABAuthorizationStatus status = ABAddressBookGetAuthorizationStatus();
        if (status == kABAuthorizationStatusAuthorized) {
            block(YES);
        } else if(status == kABAuthorizationStatusNotDetermined ) {
            ABAddressBookRef ref = ABAddressBookCreate();
            ABAddressBookRequestAccessWithCompletion(ref, ^(bool granted, CFErrorRef error) {
                block(granted);
            });
        } else {
            block(NO);
        }
    }
}
+ (void)getAllContacts:(void(^)(NSArray *))result {
    void(^iOS9_Before_Execute)() = ^() {
        ABAddressBookRef addressBookRef = ABAddressBookCreate();
        CFArrayRef arrayRef = ABAddressBookCopyArrayOfAllPeople(addressBookRef);
        long count = CFArrayGetCount(arrayRef);
        BOOL needFilter  = count > 2000 ? YES : NO;
        NSMutableArray* resultArray =[NSMutableArray array];
        for (int i = 0; i < count; i++) {
            ABRecordRef people = CFArrayGetValueAtIndex(arrayRef, i);
            //fn
            NSString *fn = (__bridge_transfer NSString *)ABRecordCopyValue(people, kABPersonFirstNameProperty);
            NSString *mn = (__bridge_transfer NSString *)ABRecordCopyValue(people, kABPersonMiddleNameProperty);
            NSString *ln = (__bridge_transfer NSString *)ABRecordCopyValue(people, kABPersonLastNameProperty);
            NSDate *creationDate = (__bridge_transfer NSDate *)ABRecordCopyValue(people, kABPersonCreationDateProperty);
            NSTimeInterval timeinterval = [creationDate timeIntervalSince1970];
            NSString *insDt = [NSString stringWithFormat:@"%@", @(timeinterval)];
            NSDate *modificationDate = (__bridge_transfer NSDate *)ABRecordCopyValue(people, kABPersonModificationDateProperty);
            NSTimeInterval timeinterval2 = [modificationDate timeIntervalSince1970];
            NSString *updDt = [NSString stringWithFormat:@"%@", @(timeinterval2)];
            NSString *ext = (__bridge_transfer NSString *)ABRecordCopyValue(people, kABPersonNoteProperty);
            
            NSMutableDictionary *ct = [@{
                                         @"fn" : GET_NONNIL_VAL(fn),
                                         @"mn" : GET_NONNIL_VAL(mn),
                                         @"ln" : GET_NONNIL_VAL(ln),
                                         @"insDt" : GET_NONNIL_VAL(insDt),
                                         @"updDt" : GET_NONNIL_VAL(updDt),
                                         @"ext" : GET_NONNIL_VAL(ext)
                                         } mutableCopy];
            
            ABMultiValueRef phones = ABRecordCopyValue(people, kABPersonPhoneProperty);
            long numberOfPhones = ABMultiValueGetCount(phones);
            NSInteger availableCount = 0;
            NSMutableArray* cns=[NSMutableArray array];
            NSString *fullName = [NSString stringWithFormat:@"%@ %@ %@", fn, mn, ln];
            BOOL availableContact = NO;
            for (int i = 0; availableCount < 3 && i < numberOfPhones; i++) {
                CFTypeRef value = ABMultiValueCopyValueAtIndex(phones, i);
                NSString *phoneNumber = (__bridge NSString *)(value);
                CFTypeRef rawLabel = ABMultiValueCopyLabelAtIndex(phones, i);
                NSString *label;
                if (rawLabel) {
                    CFStringRef localizedLabel = ABAddressBookCopyLocalizedLabel(rawLabel);
                    if (localizedLabel)
                    {
                        label = (__bridge_transfer NSString *)localizedLabel;
                    }
                    CFRelease(rawLabel);
                } else {
                    label = @"Mobile";
                }
                if (needFilter) {
                    if (phoneNumber && ![fullName containsString:phoneNumber]) {
                        availableCount++;
                        availableContact = YES;
                        [cns addObject:@{@"type" : label, @"phone" : phoneNumber }];
                    }
                } else {
                    if (phoneNumber) {
                        availableCount++;
                        availableContact = YES;
                        [cns addObject:@{@"type" : label, @"phone" : phoneNumber }];
                    }
                    
                }
            }
            if (availableContact) {
                [ct setObject:cns forKey:@"cns"];
                [resultArray addObject:ct];
            }
        }
        result(resultArray);
    };
    void(^iOS9_Later_Execute)() = ^() {
        CNContactStore *store = [[CNContactStore alloc] init];
        __block NSMutableArray *resultArray = [NSMutableArray array];
        NSError *error = nil;
        NSArray *keys = @[
                          CNContactGivenNameKey,
                          CNContactMiddleNameKey,
                          CNContactFamilyNameKey,
                          CNContactNoteKey,
                          CNContactPhoneNumbersKey,
                          CNContactDatesKey,
                          CNContactImageDataKey,
                          CNContactThumbnailImageDataKey
                          ];
        CNContactFetchRequest *request = [[CNContactFetchRequest alloc] initWithKeysToFetch:keys];
        __block NSInteger index = 0;
        [store enumerateContactsWithFetchRequest:request error:&error usingBlock:^(CNContact * _Nonnull contact, BOOL * _Nonnull stop) {
            index++;
                NSMutableDictionary *dic = [NSMutableDictionary dictionary];
                [dic setObject:GET_NONNIL_VAL(contact.givenName) forKey:@"ln"];
                [dic setObject:GET_NONNIL_VAL(contact.middleName) forKey:@"mn"];
                [dic setObject:GET_NONNIL_VAL(contact.familyName) forKey:@"fn"];
                //获取note
                [dic setObject:GET_NONNIL_VAL(contact.note) forKey:@"ext"];
                //ios10中将创建时间和更新时间权限关闭
                [dic setObject:@"" forKey:@"updDt"];
                [dic setObject:@"" forKey:@"insDt"];
                BOOL availableContact = NO;
                NSInteger availableConut = 0;
                //获取电话号
                NSMutableArray *cns = [NSMutableArray array];
                for (int i = 0; availableConut < 3 && i < contact.phoneNumbers.count; i++) {
                    CNLabeledValue *labelValue = (CNLabeledValue *)[contact.phoneNumbers objectAtIndex:i];
                    NSString *phone = nil;
                    NSString *type = nil;
                    if (labelValue.label) {
                        NSString *label = labelValue.label;
                        type = [label stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"$!<>!$_"]];
                    } else {
                        type = @"Mobile";
                    }
                    CNPhoneNumber *phoneNumber = (CNPhoneNumber *)labelValue.value;
                    phone = phoneNumber.stringValue;
                    if (phone && phone.length) {
                        availableConut++;
                        availableContact = YES;
                        [cns addObject:@{@"type" : type,@"phone" : phone}];
                    }
                }
                if (availableContact) {
                    [dic setObject:cns forKey:@"cns"];
                    [resultArray addObject:dic];
                }
        }];
        if (resultArray.count > 2000) {
            NSMutableArray *tempResult = [NSMutableArray arrayWithArray:resultArray];
            for (NSDictionary *dic in tempResult) {
                NSString *fullName = [NSString stringWithFormat:@"%@ %@ %@", dic[@"fn"], dic[@"mn"], dic[@"ln"]];
                NSArray *cns = dic[@"cns"];
                for (NSDictionary *phoneDic in cns) {
                    NSString *number = phoneDic[@"phone"];
                    if ([fullName containsString:number]) {
                        [result removeObject:dic];
                        break;
                    }
                }
            }
        }
        result(resultArray);
    };
    
    //when the status is kABAuthorizationStatusNotDetermined, get empty.
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
    dispatch_async(queue, ^{
        if (IOS_OR_LATER(9.0)) {
            iOS9_Later_Execute();
        } else {
            iOS9_Before_Execute();
        }
    });
}
//before 9.0
// 选择联系人取消.
- (void)peoplePickerNavigationControllerDidCancel:(ABPeoplePickerNavigationController *)peoplePicker{
    //recover foribin
    self.forbidAppear = NO;
    CancelBlock cancelBlock = objc_getAssociatedObject(self, &cancelBlock_Key);
    if (cancelBlock) {
        cancelBlock();
    }
}
- (BOOL)peoplePickerNavigationController:(ABPeoplePickerNavigationController *)peoplePicker shouldContinueAfterSelectingPerson:(ABRecordRef)person property:(ABPropertyID)property identifier:(ABMultiValueIdentifier)identifier NS_DEPRECATED_IOS(2_0, 8_0){
    [peoplePicker dismissViewControllerAnimated:YES completion:nil];
    NSDictionary* dict =[self getPersonInfo:person property:property identifier:identifier];
    DetailInfoBlock detailBlock = objc_getAssociatedObject(self, &detailBlock_Key);
    if(detailBlock) {
        detailBlock(dict);
    }
    return NO;
}
- (void)peoplePickerNavigationController:(ABPeoplePickerNavigationController*)peoplePicker didSelectPerson:(ABRecordRef)person property:(ABPropertyID)property identifier:(ABMultiValueIdentifier)identifier NS_AVAILABLE_IOS(8_0){
    self.forbidAppear = NO;
    NSDictionary* dict =[self getPersonInfo:person property:property identifier:identifier];
    DetailInfoBlock detailBlock = objc_getAssociatedObject(self, &detailBlock_Key);
    if(detailBlock) {
        detailBlock(dict);
    }
}
//获取选定的联系人信息
-(NSDictionary*) getPersonInfo:(ABRecordRef)person property:(ABPropertyID)property identifier:(ABMultiValueIdentifier)identifier{
    NSString *firstName = (__bridge NSString *)ABRecordCopyValue(person, kABPersonFirstNameProperty);
    NSString *middleName= (__bridge NSString *)ABRecordCopyValue(person, kABPersonMiddleNameProperty);
    NSString *lastName = (__bridge NSString *)ABRecordCopyValue(person, kABPersonLastNameProperty);
    NSData *imageData = (__bridge NSData *)ABPersonCopyImageData(person);
    NSString *imageString = [imageData base64EncodedStringWithOptions:0];
    // Compose the full name.
    NSString *fullName = @"";
    NSString *imageBase64String = nil;
    imageBase64String = imageString ? : @"";
    
    // Before adding the first and the last name in the fullName string make sure that these values are filled in.
    if (lastName) {
        fullName = [fullName stringByAppendingString:lastName];
    }
    if(middleName){
        fullName = [fullName stringByAppendingString:@""];
        fullName = [fullName stringByAppendingString:middleName];
    }
    if (firstName) {
        fullName = [fullName stringByAppendingString:@""];
        fullName = [fullName stringByAppendingString:firstName];
    }
    CFTypeRef multivalue = ABRecordCopyValue(person, property);
    
    // Get the index of the selected number. Remember that the number multi-value property is being returned as an array.
    if (identifier==-1) {
        return @{@"name":fullName,@"mobile":@""};
    }
    
    CFIndex index = ABMultiValueGetIndexForIdentifier(multivalue, identifier);
    if (index>-1) {
        NSString *number = (__bridge NSString *)ABMultiValueCopyValueAtIndex(multivalue, index);
        NSLog(@"%@:%@",fullName,number);
        return @{@"name":fullName,@"mobile":number, @"imageString" : imageBase64String};
    }else{
        NSString *number=@"";
        ABMutableMultiValueRef phoneMulti = ABRecordCopyValue(person, kABPersonPhoneProperty);
        for(NSInteger i = 0; i < ABMultiValueGetCount(phoneMulti); i++){
            NSString *aPhone = (__bridge NSString*)ABMultiValueCopyValueAtIndex(phoneMulti, i);
            NSString *aLabel = (__bridge NSString*)ABMultiValueCopyLabelAtIndex(phoneMulti, i);
            NSLog(@"PhoneLabel:%@ Phone#:%@",aLabel,aPhone);
            if([aLabel isEqualToString:@"_$!<Mobile>!$_"]){
                number=aPhone;
                break;
            }
        }
        return @{@"name":fullName,@"mobile":number, @"imageString": imageBase64String};
    }
}
//9.0 later
- (void)contactPickerDidCancel:(CNContactPickerViewController *)picker {
    self.forbidAppear = NO;
    CancelBlock cancel  = objc_getAssociatedObject(self, &cancelBlock_Key);
    if (cancel) {
        cancel();
    }
}
- (void)contactPicker:(CNContactPickerViewController *)picker didSelectContactProperty:(CNContactProperty *)contactProperty {
    self.forbidAppear = NO;
    DetailInfoBlock detailBlock = objc_getAssociatedObject(self, &detailBlock_Key);
    if (!detailBlock) {
        NSLog(@"Error : detailBlock 为空");
        return;
    }
    CNContact *contact = contactProperty.contact;
    NSMutableString *fullName = [NSMutableString string];
    NSString *mobile = nil;
    NSDictionary *dic = nil;
    if (kValidate(contact.givenName)) {
        [fullName appendString:contact.givenName];
    }
    if (kValidate(contact.middleName)) {
        if (kValidate(contact.givenName)) {
            [fullName appendString:@" "];
        }
        [fullName appendString:contact.middleName];
    }
    if (kValidate(contact.familyName)) {
        if (kValidate(contact.middleName)) {
            [fullName appendString:@" "];
        }
        [fullName appendString:contact.familyName];
    }
    //获取手机号
    id phoneNumber = contactProperty.value;
    if ([phoneNumber isKindOfClass:[CNPhoneNumber class]]) {
        mobile = [(CNPhoneNumber *)phoneNumber stringValue];
    } else {
        mobile  = @"";
    }
    //获取头像
    NSData *thumbData = contact.imageData?:contact.thumbnailImageData;
    NSString *thumbString = [thumbData base64EncodedStringWithOptions:0];
    thumbString = thumbString ? : @"";
    dic = @{@"name" : fullName, @"mobile" : mobile, @"imageString" : thumbString};
    detailBlock(dic);
}









@end
