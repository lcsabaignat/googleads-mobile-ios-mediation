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

#import "GADMAdapterUnityRewardedAd.h"
#import "GADMAdapterUnityConstants.h"
#import "GADMAdapterUnitySingleton.h"
#import "GADUnityError.h"

@interface GADMAdapterUnityRewardedAd () <GADMAdapterUnityDataProvider, UnityAdsExtendedDelegate> {
    // The completion handler to call when the ad loading succeeds or fails.
  GADMediationRewardedLoadCompletionHandler _adLoadCompletionHandler;
  // Ad configuration for the ad to be rendered.
  GADMediationAdConfiguration *_adConfiguration;

  // An ad event delegate to invoke when ad rendering events occur.
  __weak id<GADMediationRewardedAdEventDelegate> _adEventDelegate;

  /// Game ID of Unity Ads network.
  NSString *_gameID;

  /// Placement ID of Unity Ads network.
  NSString *_placementID;

  /// YES if the adapter is loading.
  BOOL _isLoading;
    
  NSString *_uuid;
    
  UADSMetaData *_metaData;
}


@end

@implementation GADMAdapterUnityRewardedAd

- (instancetype)initWithAdConfiguration:(GADMediationRewardedAdConfiguration *)adConfiguration
                      completionHandler:
                          (GADMediationRewardedLoadCompletionHandler)completionHandler {
  self = [super init];
  if (self) {
    _adLoadCompletionHandler = completionHandler;
    _adConfiguration = adConfiguration;
    
    _uuid = [[NSUUID UUID] UUIDString];
      
    _metaData = [[UADSMetaData alloc] init];
      
    [_metaData setCategory:@"mediation_adapter"];
    [_metaData setValue:@"create-adapter" forKey:_uuid];
    [_metaData commit];
  }
  return self;
}

- (void)requestRewardedAd {
  _gameID = [_adConfiguration.credentials.settings objectForKey:kGADMAdapterUnityGameID];
  _placementID = [_adConfiguration.credentials.settings objectForKey:kGADMAdapterUnityPlacementID];
  NSLog(@"Requesting unity rewarded ad with placement: %@", _placementID);

  if (!_gameID || !_placementID) {
      if (_adLoadCompletionHandler) {
      NSError *error = GADUnityErrorWithDescription(@"Game ID and Placement ID cannot be nil.");
      _adLoadCompletionHandler(nil, error);
      _adLoadCompletionHandler = nil;
    }
    return;
  }

  if (![UnityAds isSupported]) {
    NSString *description =
        [[NSString alloc] initWithFormat:@"%@ is not supported for this device.",
                                         NSStringFromClass([UnityAds class])];

    if (_adLoadCompletionHandler) {
      NSError *error = GADUnityErrorWithDescription(description);
      _adLoadCompletionHandler(nil, error);
      _adLoadCompletionHandler = nil;
    }
    return;
  }
  GADMAdapterUnityRewardedAd *__weak weakSelf = self;
    UnitySingletonCompletion completeBlock = ^(UnityAdsError *error, NSString *message) {
        GADMAdapterUnityRewardedAd *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        
        if (error) {
            NSError *errorWithDescription = GADUnityErrorWithDescription(message);
            strongSelf->_adLoadCompletionHandler(nil, errorWithDescription);
            return;
        }
        [UnityAds addDelegate:strongSelf];
        [UnityAds load:[strongSelf getPlacementID]];
    };
    
  [[GADMAdapterUnitySingleton sharedInstance] initializeWithGameID:_gameID
                                                       completeBlock:completeBlock];
  [_metaData setCategory:@"mediation_adapter"];
  [_metaData setValue:@"load-rewarded" forKey:_uuid];
  [_metaData setValue:_placementID forKey:_uuid];
  [_metaData commit];
}

- (void)presentFromViewController:(nonnull UIViewController *)viewController {
  [UnityAds show:viewController placementId:_placementID];
    
  [_metaData setCategory:@"mediation_adapter"];
  [_metaData setValue:@"show-rewarded" forKey:_uuid];
  [_metaData setValue:_placementID forKey:_uuid];
  [_metaData commit];
}

#pragma mark GADMAdapterUnityDataProvider Methods

- (NSString *)getGameID {
  return _gameID;
}

- (NSString *)getPlacementID {
  return _placementID;
}

#pragma mark - Unity Delegate Methods

- (void)unityAdsDidError:(UnityAdsError)error withMessage:(nonnull NSString *)message {
}

- (void)unityAdsDidFinish:(nonnull NSString *)placementID
          withFinishState:(UnityAdsFinishState)state {
  id<GADMediationRewardedAdEventDelegate> strongDelegate = _adEventDelegate;
  if (strongDelegate && [placementID isEqualToString:_placementID]) {
    if (state == kUnityAdsFinishStateCompleted) {
      [strongDelegate didEndVideo];
      // Unity Ads doesn't provide a way to set the reward on their front-end. Default to a reward
      // amount of 1. Publishers using this adapter should override the reward on the AdMob
      // front-end.
      GADAdReward *reward = [[GADAdReward alloc] initWithRewardType:@""
                                                         rewardAmount:[NSDecimalNumber one]];
      [strongDelegate didRewardUserWithReward:reward];
    } else if (state == kUnityAdsFinishStateError) {
      [strongDelegate willPresentFullScreenView];
      NSError *presentError = GADUnityErrorWithDescription(@"Finish State Error");
      [strongDelegate didFailToPresentWithError:presentError];
    }
    [strongDelegate didDismissFullScreenView];
    [UnityAds removeDelegate:self];
  }
}

- (void)unityAdsDidStart:(nonnull NSString *)placementID {
  id<GADMediationRewardedAdEventDelegate> strongDelegate = _adEventDelegate;
  if (strongDelegate && [placementID isEqualToString:_placementID]) {
    [strongDelegate willPresentFullScreenView];
    [strongDelegate didStartVideo];
  }
}

- (void)unityAdsReady:(nonnull NSString *)placementID {
  if (_adLoadCompletionHandler && [placementID isEqualToString:_placementID]) {
    _adEventDelegate = _adLoadCompletionHandler(self, nil);
  }
}

- (void)unityAdsDidClick:(nonnull NSString *)placementID {
  // The Unity Ads SDK doesn't provide an event for leaving the application, so the adapter assumes
  // that a click event indicates the user is leaving the application for a browser or deeplink, and
  // notifies the Google Mobile Ads SDK accordingly.
  id<GADMediationRewardedAdEventDelegate> strongDelegate = _adEventDelegate;
  if (strongDelegate && [placementID isEqualToString:_placementID]) {
    [strongDelegate reportClick];
  }
}

- (void)unityAdsPlacementStateChanged:(nonnull NSString *)placementID
                             oldState:(UnityAdsPlacementState)oldState
                             newState:(UnityAdsPlacementState)newState {
  if (_adLoadCompletionHandler && [placementID isEqualToString:_placementID]) {
    if (newState == kUnityAdsPlacementStateNoFill) {
      NSError *errorWithDescription = GADUnityErrorWithDescription(@"NO_FILL");
      _adLoadCompletionHandler(nil, errorWithDescription);
    } else if (newState == kUnityAdsPlacementStateNotAvailable) {
      NSError *errorWithDescription = GADUnityErrorWithDescription(@"PlACEMENT_NOTAVAILABLE");
      _adLoadCompletionHandler(nil, errorWithDescription);
    } else if (newState == kUnityAdsPlacementStateDisabled) {
      NSError *errorWithDescription = GADUnityErrorWithDescription(@"PlACEMENT_DISABLED");
      _adLoadCompletionHandler(nil, errorWithDescription);
    }
  }
}

@end
