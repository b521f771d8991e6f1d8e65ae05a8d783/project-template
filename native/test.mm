#include "test.h"
#define NS_ROOT_CLASS __attribute__((objc_root_class))

NS_ROOT_CLASS
@interface NSObject
- (instancetype)init;
@end

@implementation NSObject
- (instancetype)init {
  return self;
}
@end

const SEL selector = @selector(lowercaseString);

extern "C" int get1FromObjCpp(void) { return 1; }