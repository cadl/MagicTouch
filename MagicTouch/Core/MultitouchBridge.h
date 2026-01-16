//
//  MultitouchBridge.h
//  MagicTouch
//
//  Bridge header for Apple's private MultitouchSupport.framework
//

#ifndef MultitouchBridge_h
#define MultitouchBridge_h

#import <Foundation/Foundation.h>

// MARK: - Data Structures

typedef struct {
    float x;
    float y;
} MTPoint;

typedef struct {
    MTPoint position;
    MTPoint velocity;
} MTReadout;

typedef struct {
    int frame;
    double timestamp;
    int identifier;
    int state;
    int unknown1;
    int unknown2;
    MTReadout normalized;
    float size;
    int unknown3;
    float angle;
    float majorAxis;
    float minorAxis;
    MTReadout absoluteVector;
    int unknown4;
    int unknown5;
    float density;
} MTTouch;

// MARK: - Callback Type

typedef int (*MTContactFrameCallback)(int device, MTTouch *data, int nFingers, double timestamp, int frame);

// MARK: - Framework Functions

#ifdef __cplusplus
extern "C" {
#endif

// Device management
CFMutableArrayRef MTDeviceCreateList(void);
void MTDeviceRelease(void *device);

// Event callbacks
void MTRegisterContactFrameCallback(void *device, MTContactFrameCallback callback);
void MTUnregisterContactFrameCallback(void *device, MTContactFrameCallback callback);

// Device control
void MTDeviceStart(void *device, int mode);
void MTDeviceStop(void *device);

// Device properties
bool MTDeviceIsOpaqueSurface(void *device);
bool MTDeviceIsBuiltIn(void *device);

#ifdef __cplusplus
}
#endif

#endif /* MultitouchBridge_h */
