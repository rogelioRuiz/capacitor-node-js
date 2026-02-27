#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol NodeProcessDelegate <NSObject>
- (void)didReceiveMessageOnChannel:(NSString *)channel message:(NSString *)message;
@end

@interface NodeProcess : NSObject

@property (nonatomic, weak, nullable) id<NodeProcessDelegate> delegate;

/// Start the Node.js engine. This blocks until Node.js exits.
/// Must be called on a background thread with >= 2MB stack.
- (void)startWithArguments:(NSArray<NSString *> *)arguments
      environmentVariables:(NSDictionary<NSString *, NSString *> *)env;

/// Send a message to the Node.js engine on a named channel.
- (void)sendToChannel:(NSString *)channel message:(NSString *)message;

@end

NS_ASSUME_NONNULL_END
