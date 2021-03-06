// Copyright 2018 Google Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import "GADMediationAdapterAppLovin.h"
#import "GADMAdapterAppLovinConstant.h"
#import "GADMAdapterAppLovinExtras.h"
#import "GADMAdapterAppLovinRewardedRenderer.h"
#import "GADMAdapterAppLovinUtils.h"
#import "GADMRTBAdapterAppLovinBannerRenderer.h"
#import "GADMRTBAdapterAppLovinInterstitialRenderer.h"

@implementation GADMediationAdapterAppLovin {
  /// AppLovin banner ad wrapper.
  GADMRTBAdapterAppLovinBannerRenderer *_bannerRenderer;

  /// AppLovin interstitial ad wrapper.
  GADMRTBAdapterAppLovinInterstitialRenderer *_interstitialRenderer;

  /// AppLovin rewarded ad wrapper.
  GADMAdapterAppLovinRewardedRenderer *_rewardedRenderer;
}

+ (void)setUpWithConfiguration:(nonnull GADMediationServerConfiguration *)configuration
             completionHandler:(nonnull GADMediationAdapterSetUpCompletionBlock)completionHandler {
  // Compile all the SDK keys that should be initialized.
  NSMutableSet<NSString *> *sdkKeys = [NSMutableSet set];

  // Compile SDK keys from configuration credentials.
  for (GADMediationCredentials *credentials in configuration.credentials) {
    NSString *sdkKey = credentials.settings[GADMAdapterAppLovinSDKKey];
    if ([GADMAdapterAppLovinUtils isValidAppLovinSDKKey:sdkKey]) {
      GADMAdapterAppLovinMutableSetAddObject(sdkKeys, sdkKey);
    }
  }

  // Add SDK key from Info.plist if it exists.
  if ([GADMAdapterAppLovinUtils infoDictionarySDKKey]) {
    NSString *sdkKey = [GADMAdapterAppLovinUtils infoDictionarySDKKey];
    if ([GADMAdapterAppLovinUtils isValidAppLovinSDKKey:sdkKey]) {
      GADMAdapterAppLovinMutableSetAddObject(sdkKeys, sdkKey);
    }
  }

  if (!sdkKeys.count) {
    NSString *errorString = @"No SDK keys are found. Please add valid SDK keys in the AdMob UI.";
    [GADMAdapterAppLovinUtils log:errorString];
    NSError *error =
        GADMAdapterAppLovinErrorWithCodeAndDescription(kGADErrorMediationAdapterError, errorString);
    completionHandler(error);
    return;
  }

  [GADMAdapterAppLovinUtils
      log:@"Found %lu SDK keys. Please remove any SDK keys you are not using from the AdMob UI.",
          (unsigned long)sdkKeys.count];

  // Initialize SDKs based on SDK keys.
  NSSet<NSString *> *sdkKeysCopy = [sdkKeys copy];
  for (NSString *sdkKey in sdkKeysCopy) {
    [GADMAdapterAppLovinUtils log:@"Initializing SDK for SDK key %@", sdkKey];

    ALSdk *sdk = [GADMAdapterAppLovinUtils retrieveSDKFromSDKKey:sdkKey];
    [sdk initializeSdkWithCompletionHandler:^(ALSdkConfiguration *configuration) {
      [GADMAdapterAppLovinUtils log:@"Initialization completed for SDK key %@", sdkKey];
      GADMAdapterAppLovinMutableSetRemoveObject(sdkKeys, sdkKey);

      // Once all instances of SDK keys have been initialized, callback the initialization
      // listener.
      if (sdkKeys.count == 0) {
        [GADMAdapterAppLovinUtils log:@"All SDK(s) completed initialization"];
        completionHandler(nil);
      }
    }];
  }
}

+ (GADVersionNumber)version {
  NSString *versionString = GADMAdapterAppLovinAdapterVersion;
  NSArray *versionComponents = [versionString componentsSeparatedByString:@"."];
  [GADMAdapterAppLovinUtils
      log:[NSString stringWithFormat:@"AppLovin adapter version: %@", versionString]];
  GADVersionNumber version = {0};
  if (versionComponents.count >= 4) {
    version.majorVersion = [versionComponents[0] integerValue];
    version.minorVersion = [versionComponents[1] integerValue];
    // Adapter versions have 2 patch versions. Multiply the first patch by 100.
    version.patchVersion =
        [versionComponents[2] integerValue] * 100 + [versionComponents[3] integerValue];
  }
  return version;
}

+ (GADVersionNumber)adSDKVersion {
  NSString *versionString = ALSdk.version;
  NSArray *versionComponents = [versionString componentsSeparatedByString:@"."];
  [GADMAdapterAppLovinUtils
      log:[NSString stringWithFormat:@"AppLovin SDK version: %@", versionString]];
  GADVersionNumber version = {0};
  if (versionComponents.count >= 3) {
    version.majorVersion = [versionComponents[0] integerValue];
    version.minorVersion = [versionComponents[1] integerValue];
    version.patchVersion = [versionComponents[2] integerValue];
  }
  return version;
}

+ (Class<GADAdNetworkExtras>)networkExtrasClass {
  return [GADMAdapterAppLovinExtras class];
}

- (void)collectSignalsForRequestParameters:(nonnull GADRTBRequestParameters *)params
                         completionHandler:
                             (nonnull GADRTBSignalCompletionHandler)completionHandler {
  [GADMAdapterAppLovinUtils log:@"AppLovin adapter collecting signals."];
  // Check if supported ad format.
  if (params.configuration.credentials.firstObject.format == GADAdFormatNative) {
    [self handleCollectSignalsFailureForMessage:
              @"Requested to collect signal for unsupported native ad format. Ignoring..."
                              completionHandler:completionHandler];
    return;
  }

  ALSdk *sdk = [GADMAdapterAppLovinUtils
      retrieveSDKFromCredentials:params.configuration.credentials.firstObject.settings];

  NSString *signal = sdk.adService.bidToken;

  if (signal.length > 0) {
    [GADMAdapterAppLovinUtils log:@"Generated bid token %@.", signal];
    completionHandler(signal, nil);
  } else {
    [self handleCollectSignalsFailureForMessage:@"Failed to generate bid token."
                              completionHandler:completionHandler];
  }
}

- (void)handleCollectSignalsFailureForMessage:(NSString *)errorMessage
                            completionHandler:(GADRTBSignalCompletionHandler)completionHandler {
  NSError *error =
      GADMAdapterAppLovinErrorWithCodeAndDescription(kGADErrorMediationAdapterError, errorMessage);
  completionHandler(nil, error);
}

#pragma mark - GADMediationAdapter load Ad

- (void)loadBannerForAdConfiguration:(nonnull GADMediationBannerAdConfiguration *)adConfiguration
                   completionHandler:
                       (nonnull GADMediationBannerLoadCompletionHandler)completionHandler {
  _bannerRenderer =
      [[GADMRTBAdapterAppLovinBannerRenderer alloc] initWithAdConfiguration:adConfiguration
                                                          completionHandler:completionHandler];
  [_bannerRenderer loadAd];
}

- (void)loadInterstitialForAdConfiguration:
            (nonnull GADMediationInterstitialAdConfiguration *)adConfiguration
                         completionHandler:(nonnull GADMediationInterstitialLoadCompletionHandler)
                                               completionHandler {
  _interstitialRenderer = [[GADMRTBAdapterAppLovinInterstitialRenderer alloc]
      initWithAdConfiguration:adConfiguration
            completionHandler:completionHandler];
  [_interstitialRenderer loadAd];
}

- (void)loadRewardedAdForAdConfiguration:
            (nonnull GADMediationRewardedAdConfiguration *)adConfiguration
                       completionHandler:
                           (nonnull GADMediationRewardedLoadCompletionHandler)completionHandler {
  _rewardedRenderer =
      [[GADMAdapterAppLovinRewardedRenderer alloc] initWithAdConfiguration:adConfiguration
                                                         completionHandler:completionHandler];
  [_rewardedRenderer requestRewardedAd];
}

@end
