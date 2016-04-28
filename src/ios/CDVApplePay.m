#import "CDVApplePay.h"
#import <Stripe/Stripe.h>
#import <Stripe/STPAPIClient.h>
#import <Stripe/STPCardBrand.h>
#import <PassKit/PassKit.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>


@implementation CDVApplePay

- (void) pluginInitialize {
  NSLog(@"Initialize Apple Pay Plugin");
  NSString * StripePublishableKey = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"StripePublishableKey"];
  merchantId = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"ApplePayMerchant"];
  [Stripe setDefaultPublishableKey:StripePublishableKey];
}

- (void)dealloc
{
  
}

- (void)onReset
{
  
}

- (void)setMerchantId:(CDVInvokedUrlCommand*)command
{
  merchantId = [command.arguments objectAtIndex:0];
  NSLog(@"ApplePay set merchant id to %@", merchantId);
}

- (void)getAllowsApplePay:(CDVInvokedUrlCommand*)command
{
  if (merchantId == nil) {
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: @"Please call setMerchantId() with your Apple-given merchant ID."];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    return;
  }
  
  PKPaymentRequest *request = [Stripe
                               paymentRequestWithMerchantIdentifier:merchantId];
  
  // Configure a dummy request
  NSString *label = @"Premium Llama Food";
  NSDecimalNumber *amount = [NSDecimalNumber decimalNumberWithString:@"10.00"];
  request.paymentSummaryItems = @[
                                  [PKPaymentSummaryItem summaryItemWithLabel:label
                                                                      amount:amount]
                                  ];
  
  if ([Stripe canSubmitPaymentRequest:request]) {
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString: @"user has apple pay"];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
  } else {
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: @"user does not have apple pay"];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
  }
}

- (void)getStripeToken:(CDVInvokedUrlCommand*)command
{
  
  if (merchantId == nil) {
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: @"Please call setMerchantId() with your Apple-given merchant ID."];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    return;
  }
  
  
  PKPaymentRequest *paymentRequest = [self parsePaymentRequestForStripeToken:command];
  
  callbackId = command.callbackId;
  
  if ([Stripe canSubmitPaymentRequest:paymentRequest]) {
    PKPaymentAuthorizationViewController *paymentController;
    paymentController = [[PKPaymentAuthorizationViewController alloc]
                         initWithPaymentRequest:paymentRequest];
    paymentController.delegate = self;
    [self.viewController presentViewController:paymentController animated:YES completion:nil];
  } else {
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: @"You dont have access to ApplePay"];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    return;
  }
  
}

- (PKPaymentRequest *)parsePaymentRequestForStripeToken:(CDVInvokedUrlCommand*)command {

  PKPaymentRequest *paymentRequest = [Stripe paymentRequestWithMerchantIdentifier:merchantId];

  NSString *cur = [command.arguments objectAtIndex:1];
  paymentRequest.currencyCode = cur;

  NSArray *items = [command.arguments objectAtIndex:0];
  NSMutableArray *paymentSummaryItems = [[NSMutableArray alloc] init];

  for (NSDictionary *item in items) {

    NSString* label = [item valueForKey:@"label"];
    NSDecimalNumber *amount = [NSDecimalNumber decimalNumberWithDecimal:[[item valueForKey:@"amount"] decimalValue]];
    PKPaymentSummaryItem * summaryItem = [PKPaymentSummaryItem summaryItemWithLabel: label
                                                                             amount:amount];
    [paymentSummaryItems addObject:summaryItem];
  }

  paymentRequest.paymentSummaryItems = paymentSummaryItems;

  return paymentRequest;
}


- (void)paymentAuthorizationViewController:(PKPaymentAuthorizationViewController *)controller
                       didAuthorizePayment:(PKPayment *)payment
                                completion:(void (^)(PKPaymentAuthorizationStatus))completion {
  
#if DEBUG
  [self handleDebugPaymentAuthorizationWithPayment:payment completion:completion];
#else
  [self handlePaymentAuthorizationWithPayment:payment completion:completion];
#endif
}

- (void)handleDebugPaymentAuthorizationWithPayment:(PKPayment *)payment completion:(void (^)(PKPaymentAuthorizationStatus))completion {
  
  STPCard *card = [STPCard new];
  card.number = @"5555555555554444";
  card.expMonth = 12;
  card.expYear = 2020;
  card.cvc = @"123";
  
  [[STPAPIClient sharedClient] createTokenWithCard:card
                                        completion:^(STPToken *token, NSError *error)
   {
     if (error)
     {
       NSLog(@"Error Token Creation.");
       completion(PKPaymentAuthorizationStatusFailure);
       [[[UIAlertView alloc] initWithTitle:@"Error"
                                   message:@"Payment Unsuccessful! \n Please Try Again"
                                  delegate:self
                         cancelButtonTitle:@"OK"
                         otherButtonTitles:nil] show];
       return;
     } else {
       
       NSLog(@"Success Token Creation.");
       
       /*
        Handle Token here
        */
       NSString* brand;
       
       switch (token.card.brand) {
         case STPCardBrandVisa:
           brand = @"Visa";
           break;
         case STPCardBrandAmex:
           brand = @"American Express";
           break;
         case STPCardBrandMasterCard:
           brand = @"MasterCard";
           break;
         case STPCardBrandDiscover:
           brand = @"Discover";
           break;
         case STPCardBrandJCB:
           brand = @"JCB";
           break;
         case STPCardBrandDinersClub:
           brand = @"Diners Club";
           break;
         case STPCardBrandUnknown:
           brand = @"Unknown";
           break;
       }
       
       
       NSDictionary* card = @{
                              @"id": token.card.cardId,
                              @"brand": brand,
                              @"last4": [NSString stringWithFormat:@"%@", token.card.last4],
                              @"dynamic_last4" : @"1234",
                              @"tokenization_method": @"apple_pay",
                              @"exp_month": [NSString stringWithFormat:@"%u", token.card.expMonth],
                              @"exp_year": [NSString stringWithFormat:@"%u", token.card.expYear]
                              };
       
       NSDictionary* message = @{
                                 @"id": token.tokenId,
                                 @"card": card
                                 };
       
       completion(PKPaymentAuthorizationStatusSuccess);
       CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary: message];
       [self.commandDelegate sendPluginResult:result callbackId:callbackId];
       
     }
     
     [self.viewController dismissViewControllerAnimated:YES completion:nil];
   }];
}

- (void)handlePaymentAuthorizationWithPayment:(PKPayment *)payment completion:(void (^)(PKPaymentAuthorizationStatus))completion {
  
  [[STPAPIClient sharedClient] createTokenWithPayment:payment completion:^(STPToken *token, NSError *error) {
    if (error) {
      completion(PKPaymentAuthorizationStatusFailure);
      NSLog(@"%@",error);
      CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: @"couldn't get a stripe token from STPAPIClient"];
      [self.commandDelegate sendPluginResult:result callbackId:callbackId];
      return;
    } else {
      
      NSString* brand;
      
      switch (token.card.brand) {
        case STPCardBrandVisa:
          brand = @"Visa";
          break;
        case STPCardBrandAmex:
          brand = @"American Express";
          break;
        case STPCardBrandMasterCard:
          brand = @"MasterCard";
          break;
        case STPCardBrandDiscover:
          brand = @"Discover";
          break;
        case STPCardBrandJCB:
          brand = @"JCB";
          break;
        case STPCardBrandDinersClub:
          brand = @"Diners Club";
          break;
        case STPCardBrandUnknown:
          brand = @"Unknown";
          break;
      }
      
      NSDictionary* card = @{
                             @"id": token.card.cardId,
                             @"brand": brand,
                             @"last4": [NSString stringWithFormat:@"%@", token.card.last4],
                             @"dynamic_last4" : [NSString stringWithFormat:@"%@", token.card.dynamicLast4],
                             @"tokenization_method": @"apple_pay",
                             @"exp_month": [NSString stringWithFormat:@"%lu", token.card.expMonth],
                             @"exp_year": [NSString stringWithFormat:@"%lu", token.card.expYear]
                             };
      
      NSDictionary* message = @{
                                @"id": token.tokenId,
                                @"card": card
                                };
      
      completion(PKPaymentAuthorizationStatusSuccess);
      CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary: message];
      [self.commandDelegate sendPluginResult:result callbackId:callbackId];
    }
    [self.viewController dismissViewControllerAnimated:YES completion:nil];
    
  }];
}


- (void)paymentAuthorizationViewControllerDidFinish:(PKPaymentAuthorizationViewController *)controller {
  CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: @"user cancelled apple pay"];
  [self.commandDelegate sendPluginResult:result callbackId:callbackId];
  [self.viewController dismissViewControllerAnimated:YES completion:nil];
}

@end