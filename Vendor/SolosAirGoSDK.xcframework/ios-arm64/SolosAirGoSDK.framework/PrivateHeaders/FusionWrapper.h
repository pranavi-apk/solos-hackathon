#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Enumeration for coordinate system conventions.
 */
typedef NS_ENUM(NSInteger, FusionConventionType) {
    FusionConventionTypeNWU = 0, // North-West-Up
    FusionConventionTypeENU = 1, // East-North-Up
    FusionConventionTypeNED = 2, // North-East-Down
};

/**
 * 3D vector representation.
 */
@interface FusionVectorObj : NSObject

@property (nonatomic, assign) float x;
@property (nonatomic, assign) float y;
@property (nonatomic, assign) float z;

- (instancetype)initWithX:(float)x y:(float)y z:(float)z;
+ (instancetype)vectorWithX:(float)x y:(float)y z:(float)z;
+ (instancetype)zero;

@end

/**
 * Quaternion representation.
 */
@interface FusionQuaternionObj : NSObject

@property (nonatomic, assign) float w;
@property (nonatomic, assign) float x;
@property (nonatomic, assign) float y;
@property (nonatomic, assign) float z;

- (instancetype)initWithW:(float)w x:(float)x y:(float)y z:(float)z;
+ (instancetype)quaternionWithW:(float)w x:(float)x y:(float)y z:(float)z;
+ (instancetype)identity;

@end

/**
 * Settings for the Fusion AHRS algorithm.
 */
@interface FusionSettingsObj : NSObject

@property (nonatomic, assign) FusionConventionType convention;
@property (nonatomic, assign) float gain;
@property (nonatomic, assign) float gyroscopeRange;
@property (nonatomic, assign) float accelerationRejection;
@property (nonatomic, assign) float magneticRejection;
@property (nonatomic, assign) NSUInteger recoveryTriggerPeriod;

+ (instancetype)defaultSettings;

@end

/**
 * Wrapper for the Fusion sensor fusion library.
 */
@interface FusionWrapper : NSObject

/**
 * Initialize the Fusion library with default settings.
 */
- (instancetype)init;

/**
 * Reset the AHRS algorithm.
 */
- (void)reset;

/**
 * Update the AHRS with sensor data.
 *
 * @param gyroscope Gyroscope data in degrees/s
 * @param accelerometer Accelerometer data in g
 * @param magnetometer Magnetometer data (can be in any consistent unit)
 * @param deltaTime Time in seconds since the last update
 */
- (void)updateWithGyroscope:(FusionVectorObj *)gyroscope
              accelerometer:(FusionVectorObj *)accelerometer
               magnetometer:(FusionVectorObj *)magnetometer
                  deltaTime:(float)deltaTime;

/**
 * Update the AHRS with sensor data (without magnetometer).
 *
 * @param gyroscope Gyroscope data in degrees/s
 * @param accelerometer Accelerometer data in g
 * @param deltaTime Time in seconds since the last update
 */
- (void)updateWithGyroscope:(FusionVectorObj *)gyroscope
              accelerometer:(FusionVectorObj *)accelerometer
                  deltaTime:(float)deltaTime;

/**
 * Get the current orientation as a quaternion.
 *
 * @return Quaternion representing the current orientation
 */
- (FusionQuaternionObj *)getQuaternion;

/**
 * Get the gravity vector.
 *
 * @return Vector representing the gravity vector in g
 */
- (FusionVectorObj *)getGravity;

/**
 * Get the linear acceleration (acceleration with gravity removed).
 *
 * @return Vector representing the linear acceleration in g
 */
- (FusionVectorObj *)getLinearAcceleration;

/**
 * Get the earth acceleration.
 *
 * @return Vector representing the earth acceleration in g
 */
- (FusionVectorObj *)getEarthAcceleration;

/**
 * Set the AHRS settings.
 *
 * @param settings Settings for the AHRS algorithm
 */
- (void)setSettings:(FusionSettingsObj *)settings;

@end

NS_ASSUME_NONNULL_END 