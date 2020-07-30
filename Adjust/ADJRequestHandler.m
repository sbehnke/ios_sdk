//
//  ADJRequestHandler.m
//  Adjust
//
//  Created by Christian Wellenbrock on 2013-07-04.
//  Copyright (c) 2013 adjust GmbH. All rights reserved.
//

#import "ADJUtil.h"
#import "ADJLogger.h"
#import "ADJActivityKind.h"
#import "ADJAdjustFactory.h"
#import "ADJPackageBuilder.h"
#import "ADJActivityPackage.h"
#import "NSString+ADJAdditions.h"

static NSString * const ADJAttemptDefaultURL = @"AttemptDefaultURL";
static NSString * const ADJAttemptFallbackURL = @"AttemptFallbackURL";
static NSString * const ADJAttemptRandomIP = @"AttemptRandomIP";

static NSString * const ADJMethodGET = @"MethodGET";
static NSString * const ADJMethodPOST = @"MethodPOST";

@interface ADJRequestHandler()

@property (nonatomic, copy) NSString *baseUrlString;
@property (nonatomic, copy) NSString *gdrpUrlString;
@property (nonatomic, copy) NSString *subscriptionUrlString;
@property (nonatomic, copy) NSString *extraPath;
@property (nonatomic, copy) NSString *userAgent;
@property (nonatomic, assign) double requestTimeout;
@property (nonatomic, weak) id<ADJResponseCallback> responseCallback;

@property (nonatomic, weak) id<ADJLogger> logger;

@property (nonatomic, copy) NSURLSessionConfiguration *defaultSessionConfiguration;

@property (nonatomic, strong) NSHashTable<NSString *> *exceptionKeys;

@property (nonatomic, copy) NSString *subscriptionPath;

@end

@implementation ADJRequestHandler

#pragma mark - Public methods

- (id)initWithResponseCallback:(id<ADJResponseCallback>)responseCallback
                     extraPath:(NSString *)extraPath
                       baseUrl:(NSString *)baseUrl
                       gdprUrl:(NSString *)gdprUrl
               subscriptionUrl:(NSString *)subscriptionUrl
                     userAgent:(NSString *)userAgent
                requestTimeout:(double)requestTimeout
{
    self = [super init];
    
    if (self == nil) {
        return nil;
    }
    self.baseUrlString = baseUrl;
    self.gdrpUrlString = gdprUrl;
    self.subscriptionUrlString = subscriptionUrl;
    self.extraPath = extraPath ?: @"";
    self.userAgent = userAgent;
    self.requestTimeout = requestTimeout;
    self.responseCallback = responseCallback;

    self.logger = ADJAdjustFactory.logger;
    self.defaultSessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];

    self.exceptionKeys =
        [NSHashTable hashTableWithOptions:NSHashTableStrongMemory];
    [self.exceptionKeys addObject:@"event_callback_id"];
    [self.exceptionKeys addObject:@"secret_id"];
    [self.exceptionKeys addObject:@"signature"];
    [self.exceptionKeys addObject:@"headers_id"];
    [self.exceptionKeys addObject:@"native_version"];
    [self.exceptionKeys addObject:@"algorithm"];
    [self.exceptionKeys addObject:@"app_secret"];

    return self;
}

- (void)sendPackageByPOST:(ADJActivityPackage *)activityPackage
        sendingParameters:(NSDictionary *)sendingParameters
{
    [self sendPackageByPOST:activityPackage
          sendingParameters:sendingParameters
            attemptTypeInfo:ADJAttemptDefaultURL];
}

- (void)sendPackageByPOST:(ADJActivityPackage *)activityPackage
        sendingParameters:(NSDictionary *)sendingParameters
          attemptTypeInfo:(NSString *)attemptTypeInfo
{
    NSDictionary *parameters = [[NSDictionary alloc]
                                initWithDictionary:activityPackage.parameters
                                copyItems:YES];
    NSString *path = [activityPackage.path copy];
    NSString *clientSdk = [activityPackage.clientSdk copy];
    ADJActivityKind activityKind = activityPackage.activityKind;

    ADJResponseData *responseData =
        [ADJResponseData buildResponseData:activityPackage];
    responseData.sendingParameters = [[NSDictionary alloc]
                                      initWithDictionary:sendingParameters
                                      copyItems:YES];

    NSString * authorizationHeader = [self buildAuthorizationHeader:parameters activityKind:activityKind];

    NSString *urlHostString;
    if (attemptTypeInfo == ADJAttemptFallbackURL) {
        urlHostString = @"https://app.adjust.net.in";
    } else if (attemptTypeInfo == ADJAttemptRandomIP) {
        urlHostString = [ADJRequestHandler randomIpAddress];
    } else {
        if (activityPackage.activityKind == ADJActivityKindGdpr) {
            urlHostString = self.gdrpUrlString;
        } else if (activityPackage.activityKind == ADJActivityKindSubscription) {
            urlHostString = self.subscriptionUrlString;
        } else {
            urlHostString = self.baseUrlString;
        }
    }

    NSMutableURLRequest *urlRequest =
        [self requestForPostPackage:path
                          clientSdk:clientSdk
                         parameters:parameters
                      urlHostString:urlHostString
                  sendingParameters:sendingParameters];

    [self sendRequest:urlRequest
  authorizationHeader:authorizationHeader
         responseData:responseData
      attemptTypeInfo:attemptTypeInfo
       methodTypeInfo:ADJMethodPOST];
}

- (void)sendPackageByGET:(ADJActivityPackage *)activityPackage
       sendingParameters:(NSDictionary *)sendingParameters
{
    [self sendPackageByGET:activityPackage
         sendingParameters:sendingParameters
           attemptTypeInfo:ADJAttemptDefaultURL];
}

- (void)sendPackageByGET:(ADJActivityPackage *)activityPackage
       sendingParameters:(NSDictionary *)sendingParameters
         attemptTypeInfo:(NSString *)attemptTypeInfo
{
    NSDictionary *parameters = [[NSDictionary alloc]
                                initWithDictionary:activityPackage.parameters
                                copyItems:YES];
    NSString *path = [activityPackage.path copy];
    NSString *clientSdk = [activityPackage.clientSdk copy];
    ADJActivityKind activityKind = activityPackage.activityKind;

    ADJResponseData *responseData =
        [ADJResponseData buildResponseData:activityPackage];
    responseData.sendingParameters = [[NSDictionary alloc]
                                      initWithDictionary:sendingParameters
                                      copyItems:YES];

    NSString * authorizationHeader = [self buildAuthorizationHeader:parameters activityKind:activityKind];

    NSString *urlHostString;
    if (attemptTypeInfo == ADJAttemptFallbackURL) {
        urlHostString = @"https://app.adjust.net.in";
    } else if (attemptTypeInfo == ADJAttemptRandomIP) {
        urlHostString = [ADJRequestHandler randomIpAddress];
    } else {
        urlHostString = self.baseUrlString;
    }

    NSMutableURLRequest *urlRequest =
        [self requestForGetPackage:path
                         clientSdk:clientSdk
                        parameters:parameters
                     urlHostString:urlHostString
                 sendingParameters:sendingParameters];

    [self sendRequest:urlRequest
     authorizationHeader:authorizationHeader
         responseData:responseData
      attemptTypeInfo:attemptTypeInfo
       methodTypeInfo:ADJMethodGET];
}

#pragma mark Internal methods
- (void)sendRequest:(NSMutableURLRequest *)request
authorizationHeader:(NSString *)authorizationHeader
       responseData:(ADJResponseData *)responseData
    attemptTypeInfo:(NSString *)attemptTypeInfo
     methodTypeInfo:(NSString *)methodTypeInfo

{
    if (authorizationHeader != nil) {
        [ADJAdjustFactory.logger debug:@"authorizationHeader %@", authorizationHeader];
        [request setValue:authorizationHeader forHTTPHeaderField:@"Authorization"];
    }
    if (self.userAgent != nil) {
        [request setValue:self.userAgent forHTTPHeaderField:@"User-Agent"];
    }

    Class NSURLSessionClass = NSClassFromString(@"NSURLSession");
    if (NSURLSessionClass != nil) {
        [self sendNSURLSessionRequest:request
                      responseData:responseData
                      attemptTypeInfo:attemptTypeInfo
                       methodTypeInfo:methodTypeInfo];
    } else {
        [self sendNSURLConnectionRequest:request
                         responseData:responseData
                         attemptTypeInfo:attemptTypeInfo
                          methodTypeInfo:methodTypeInfo];
    }
}

- (void)sendNSURLSessionRequest:(NSMutableURLRequest *)request
                   responseData:(ADJResponseData *)responseData
                attemptTypeInfo:(NSString *)attemptTypeInfo
                 methodTypeInfo:(NSString *)methodTypeInfo

{
    NSURLSession *session =
        [NSURLSession sessionWithConfiguration:self.defaultSessionConfiguration
                                      delegate:self delegateQueue:nil];

    NSURLSessionDataTask *task =
        [session dataTaskWithRequest:request
                   completionHandler:
         ^(NSData *data, NSURLResponse *response, NSError *error)
         {
            [self handleResponseWithData:data
                                response:(NSHTTPURLResponse *)response
                                   error:error
                            responseData:responseData];

            if (responseData.jsonResponse != nil) {
                [self.responseCallback responseCallback:responseData];
            } else if (attemptTypeInfo == ADJAttemptDefaultURL) {
                // Failed attempt with DefaultURL
                //  Retry with FallbackURL
                [self retryWithResponseData:responseData
                            attemptTypeInfo:ADJAttemptFallbackURL
                             methodTypeInfo:methodTypeInfo];
                return;
            } else if (attemptTypeInfo == ADJAttemptFallbackURL) {
                // Failed attempt with FallbackURL
                //  Retry with RandomIP
                [self retryWithResponseData:responseData
                            attemptTypeInfo:ADJAttemptRandomIP
                             methodTypeInfo:methodTypeInfo];
                return;
            } else {
                // Failed attempt with RandomIP
                //  Stop retrying with different type and return to caller
                [self.responseCallback responseCallback:responseData];
            }
        }];

    [task resume];
    [session finishTasksAndInvalidate];
}

- (void)
    URLSession:(NSURLSession *)session
    didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
    completionHandler:
        (void (^)
            (NSURLSessionAuthChallengeDisposition disposition,
             NSURLCredential * _Nullable credential))completionHandler
{
    completionHandler(NSURLSessionAuthChallengeUseCredential,
                      [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
}

- (void)sendNSURLConnectionRequest:(NSMutableURLRequest *)request
                responseData:(ADJResponseData *)responseData
                   attemptTypeInfo:(NSString *)attemptTypeInfo
                    methodTypeInfo:(NSString *)methodTypeInfo
{
    dispatch_async
        (dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),
         ^{
            NSError *error = nil;
            NSURLResponse *response = nil;
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            NSData *data = [NSURLConnection sendSynchronousRequest:request
                                                 returningResponse:&response
                                                             error:&error];
/*
            NSURLConnection *urlConnection =
                [[NSURLConnection alloc] initWithRequest:request delegate:self];
            [urlConnection start];
*/
            #pragma clang diagnostic pop
            [self handleResponseWithData:data
                                response:(NSHTTPURLResponse *)response
                                   error:error
                            responseData:responseData];

            [self.responseCallback responseCallback:responseData];
/*
            if (responseData.jsonResponse != nil) {
                [self.responseCallback responseCallback:responseData];
            } else if (attemptTypeInfo == ADJAttemptDefaultURL) {
                // Failed attempt with DefaultURL
                //  Retry with FallbackURL
                [self retryWithResponseData:responseData
                            attemptTypeInfo:ADJAttemptFallbackURL
                             methodTypeInfo:methodTypeInfo];
            } else if (attemptTypeInfo == ADJAttemptFallbackURL) {
                // Failed attempt with FallbackURL
                //  Retry with RandomIP
                [self retryWithResponseData:responseData
                            attemptTypeInfo:ADJAttemptRandomIP
                             methodTypeInfo:methodTypeInfo];
            } else {
                // Failed attempt with RandomIP
                //  Stop retrying with different type and return to caller
                [self.responseCallback responseCallback:responseData];
            }
 */
        });
}

- (void)connection:(NSURLConnection *)connection
willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    if (challenge.previousFailureCount > 0) {
        [challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
    } else {
        NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        [challenge.sender useCredential:credential forAuthenticationChallenge:challenge];
    }
}

+ (NSString *)randomIpAddress {
    // TODO get one of random ips
    return @"https://185.151.204.6";
}

- (void)retryWithResponseData:(ADJResponseData *)responseData
              attemptTypeInfo:(NSString *)attemptTypeInfo
               methodTypeInfo:(NSString *)methodTypeInfo
{
    ADJActivityPackage *activityPackage = responseData.sdkPackage;
    NSDictionary *sendingParameters = responseData.sendingParameters;

    if (methodTypeInfo == ADJMethodGET) {
        [self sendPackageByGET:activityPackage
              sendingParameters:sendingParameters
                attemptTypeInfo:attemptTypeInfo];
    } else {
        [self sendPackageByPOST:activityPackage
              sendingParameters:sendingParameters
                attemptTypeInfo:attemptTypeInfo];
    }
}

- (void)handleResponseWithData:(NSData *)data
                      response:(NSHTTPURLResponse *)urlResponse
                         error:(NSError *)responseError
                       responseData:(ADJResponseData *)responseData
{
    // Connection error
    if (responseError != nil) {
        responseData.message = responseError.description;
        return;
    }
    if ([ADJUtil isNull:data]) {
        responseData.message = @"nil response data";
        return;
    }

    NSString *responseString = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] adjTrim];
    NSInteger statusCode = urlResponse.statusCode;
    [self.logger verbose:@"Response: %@", responseString];

    if (statusCode == 429) {
        responseData.message = @"Too frequent requests to the endpoint (429)";
        return;
    }

    [self saveJsonResponse:data responseData:responseData];
    if (responseData.jsonResponse == nil) {
        return;
    }

    NSString *messageResponse = [responseData.jsonResponse objectForKey:@"message"];
    responseData.message = messageResponse;
    responseData.timeStamp = [responseData.jsonResponse objectForKey:@"timestamp"];
    responseData.adid = [responseData.jsonResponse objectForKey:@"adid"];

    NSString *trackingState = [responseData.jsonResponse objectForKey:@"tracking_state"];
    if (trackingState != nil) {
        if ([trackingState isEqualToString:@"opted_out"]) {
            responseData.trackingState = ADJTrackingStateOptedOut;
        }
    }

    if (statusCode == 200) {
        responseData.success = YES;
    }
}
#pragma mark - URL Request
- (NSMutableURLRequest *)
    requestForPostPackage:(NSString *)path
    clientSdk:(NSString *)clientSdk
    parameters:(NSDictionary *)parameters
    urlHostString:(NSString *)urlHostString
    sendingParameters:
        (NSDictionary<NSString *, NSString *> *)sendingParameters
{
    NSString *urlString = [NSString stringWithFormat:@"%@%@%@",
                           urlHostString, self.extraPath, path];

    NSURL *url = [NSURL URLWithString:urlString];
    //NSURL *url = [baseUrl URLByAppendingPathComponent:path];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = self.requestTimeout;
    request.HTTPMethod = @"POST";
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [request setValue:clientSdk forHTTPHeaderField:@"Client-Sdk"];

    NSUInteger sendingParametersCount = sendingParameters? sendingParameters.count : 0;
    NSMutableArray<NSString *> *kvParameters =
        [NSMutableArray arrayWithCapacity:
            parameters.count + sendingParametersCount];

    [self injectParameters:parameters
        kvArray:kvParameters];
    [self injectParameters:sendingParameters
        kvArray:kvParameters];

    NSString *bodyString = [kvParameters componentsJoinedByString:@"&"];
    NSData *body = [NSData dataWithBytes:bodyString.UTF8String length:bodyString.length];
    [request setHTTPBody:body];
    return request;
}

- (NSMutableURLRequest *)
    requestForGetPackage:(NSString *)path
    clientSdk:(NSString *)clientSdk
    parameters:(NSDictionary *)parameters
    urlHostString:(NSString *)urlHostString
    sendingParameters:(NSDictionary *)sendingParameters
{
    NSUInteger sendingParametersCount = sendingParameters? sendingParameters.count : 0;
    NSMutableArray<NSString *> *kvParameters =
        [NSMutableArray arrayWithCapacity:
            parameters.count + sendingParametersCount];

    [self injectParameters:parameters
        kvArray:kvParameters];
    [self injectParameters:sendingParameters
        kvArray:kvParameters];

    NSString *queryStringParameters = [kvParameters componentsJoinedByString:@"&"];

    NSString *urlString =
        [NSString stringWithFormat:@"%@%@%@?%@",
            urlHostString, self.extraPath, path, queryStringParameters];

    NSURL *url = [NSURL URLWithString:urlString];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = self.requestTimeout;
    request.HTTPMethod = @"GET";
    [request setValue:clientSdk forHTTPHeaderField:@"Client-Sdk"];
    return request;
}

- (void)
    injectParameters:(NSDictionary<NSString *, NSString *> *)parameters
    kvArray:(NSMutableArray<NSString *> *)kvArray
{
    if (parameters == nil || parameters.count == 0) {
        return;
    }

    for (NSString *key in parameters) {
        if ([self.exceptionKeys containsObject:key]) {
            continue;
        }
        NSString *value = [parameters objectForKey:key];
        NSString *escapedValue = [value  adjUrlEncode];
        NSString *escapedKey = [key  adjUrlEncode];
        NSString *pair = [NSString stringWithFormat:@"%@=%@", escapedKey, escapedValue];
        [kvArray addObject:pair];
    }
}

#pragma mark - Authorization Header
- (NSString *)buildAuthorizationHeader:(NSDictionary *)parameters
                          activityKind:(ADJActivityKind)activityKind
{
    NSString *secretId = [parameters objectForKey:@"secret_id"];
    NSString *signature = [parameters objectForKey:@"signature"];
    NSString *headersId = [parameters objectForKey:@"headers_id"];
    NSString *nativeVersion = [parameters objectForKey:@"native_version"];
    NSString *algorithm = [parameters objectForKey:@"algorithm"];
    NSString *authorizationHeader = [self buildAuthorizationHeaderV2:signature
                                                            secretId:secretId
                                                           headersId:headersId
                                                       nativeVersion:nativeVersion
                                                           algorithm:algorithm];
    if (authorizationHeader != nil) {
        return authorizationHeader;
    }

    NSString * appSecret = [parameters objectForKey:@"app_secret"];
    return [self buildAuthorizationHeaderV1:appSecret
                                      secretId:secretId
                                    parameters:parameters
                                  activityKind:activityKind];
}

- (NSString *)buildAuthorizationHeaderV2:(NSString *)signature
                                secretId:(NSString *)secretId
                                headersId:(NSString *)headersId
                           nativeVersion:(NSString *)nativeVersion
                               algorithm:(NSString *)algorithm
{
    if (secretId == nil || signature == nil || headersId == nil) {
        return nil;
    }

    NSString * signatureHeader = [NSString stringWithFormat:@"signature=\"%@\"", signature];
    NSString * secretIdHeader  = [NSString stringWithFormat:@"secret_id=\"%@\"", secretId];
    NSString * idHeader        = [NSString stringWithFormat:@"headers_id=\"%@\"", headersId];
    NSString * algorithmHeader = [NSString stringWithFormat:@"algorithm=\"%@\"", algorithm != nil ? algorithm : @"adj1"];

    NSString * authorizationHeader = [NSString stringWithFormat:@"Signature %@,%@,%@,%@",
            signatureHeader, secretIdHeader, algorithmHeader, idHeader];

    if (nativeVersion == nil) {
        return [authorizationHeader stringByAppendingFormat:@",native_version=\"\""];
    }
    return [authorizationHeader stringByAppendingFormat:@",native_version=\"%@\"", nativeVersion];
}

- (NSString *)buildAuthorizationHeaderV1:(NSString *)appSecret
                              secretId:(NSString *)secretId
                              parameters:(NSDictionary *)parameters
                       activityKind:(ADJActivityKind)activityKind
{
    if (appSecret == nil) {
        return nil;
    }

    NSString *activityKindS = [ADJActivityKindUtil activityKindToString:activityKind];
    NSDictionary *signatureParameters = [self buildSignatureParameters:parameters
                                                                appSecret:appSecret
                                                            activityKindS:activityKindS];
    NSMutableString *fields = [[NSMutableString alloc] initWithCapacity:5];
    NSMutableString *clearSignature = [[NSMutableString alloc] initWithCapacity:5];

    // signature part of header
    for (NSDictionary *key in signatureParameters) {
        [fields appendFormat:@"%@ ", key];
        NSString *value = [signatureParameters objectForKey:key];
        [clearSignature appendString:value];
    }

    NSString *secretIdHeader = [NSString stringWithFormat:@"secret_id=\"%@\"", secretId];
    // algorithm part of header
    NSString *algorithm = @"sha256";
    NSString *signature = [clearSignature adjSha256];
    NSString *signatureHeader = [NSString stringWithFormat:@"signature=\"%@\"", signature];
    NSString *algorithmHeader = [NSString stringWithFormat:@"algorithm=\"%@\"", algorithm];
    // fields part of header
    // Remove last empty space.
    if (fields.length > 0) {
        [fields deleteCharactersInRange:NSMakeRange(fields.length - 1, 1)];
    }

    NSString *fieldsHeader = [NSString stringWithFormat:@"headers=\"%@\"", fields];
    // putting it all together
    NSString *authorizationHeader = [NSString stringWithFormat:@"Signature %@,%@,%@,%@",
                                     secretIdHeader,
                                     signatureHeader,
                                     algorithmHeader,
                                     fieldsHeader];
    return authorizationHeader;
}

- (NSDictionary *)buildSignatureParameters:(NSDictionary *)parameters
                                 appSecret:(NSString *)appSecret
                             activityKindS:(NSString *)activityKindS {
    NSString *appSecretName = @"app_secret";
    NSString *sourceName = @"source";
    NSString *payloadName = @"payload";
    NSString *activityKindName = @"activity_kind";
    NSString *activityKindValue = activityKindS;
    NSString *createdAtName = @"created_at";
    NSString *createdAtValue = [parameters objectForKey:createdAtName];
    NSString *deviceIdentifierName = [self getValidIdentifier:parameters];
    NSString *deviceIdentifierValue = [parameters objectForKey:deviceIdentifierName];
    NSMutableDictionary *signatureParameters = [[NSMutableDictionary alloc] initWithCapacity:6];

    [self checkAndAddEntry:signatureParameters key:appSecretName value:appSecret];
    [self checkAndAddEntry:signatureParameters key:createdAtName value:createdAtValue];
    [self checkAndAddEntry:signatureParameters key:activityKindName value:activityKindValue];
    [self checkAndAddEntry:signatureParameters key:deviceIdentifierName value:deviceIdentifierValue];
    [self checkAndAddEntry:signatureParameters key:sourceName value:parameters[sourceName]];
    [self checkAndAddEntry:signatureParameters key:payloadName value:parameters[payloadName]];

    return signatureParameters;
}

- (void)checkAndAddEntry:(NSMutableDictionary *)parameters
                     key:(NSString *)key
                   value:(NSString *)value {
    if (key == nil) {
        return;
    }

    if (value == nil) {
        return;
    }

    [parameters setObject:value forKey:key];
}

- (NSString *)getValidIdentifier:(NSDictionary *)parameters {
    NSString *idfaName = @"idfa";
    NSString *persistentUUIDName = @"persistent_ios_uuid";
    NSString *uuidName = @"ios_uuid";

    if ([parameters objectForKey:idfaName] != nil) {
        return idfaName;
    }
    if ([parameters objectForKey:persistentUUIDName] != nil) {
        return persistentUUIDName;
    }
    if ([parameters objectForKey:uuidName] != nil) {
        return uuidName;
    }
    return nil;
}

#pragma mark - JSON
- (void)saveJsonResponse:(NSData *)jsonData responseData:(ADJResponseData *)responseData {
    NSError *error = nil;
    NSException *exception = nil;
    NSDictionary *jsonDict =
        [self buildJsonDict:jsonData exceptionPtr:&exception errorPtr:&error];

    if (exception != nil) {
        responseData.message =
            [NSString stringWithFormat:
                @"Failed to parse json response. (%@)", exception.description];
    } else if (error != nil) {
        responseData.message =
            [NSString stringWithFormat:
                @"Failed to parse json response. (%@)", error.localizedDescription];
    } else if ([ADJUtil isNull:jsonDict]) {
        responseData.message = [NSString stringWithFormat:@"Failed to parse json response "];
    } else {
        responseData.jsonResponse = jsonDict;
    }
}

- (NSDictionary *)buildJsonDict:(NSData *)jsonData
                   exceptionPtr:(NSException **)exceptionPtr
                       errorPtr:(NSError **)error {
    if (jsonData == nil) {
        return nil;
    }

    NSDictionary *jsonDict = nil;
    @try {
        jsonDict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:error];
    } @catch (NSException *ex) {
        *exceptionPtr = ex;
        return nil;
    }
    return jsonDict;
}

@end
