#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const ARKTorrentErrorDomain;

typedef NS_ENUM(NSInteger, ARKTorrentErrorCode) {
  ARKTorrentErrorInvalidMagnet = 1,
  ARKTorrentErrorAddFailed = 2,
  ARKTorrentErrorNoVideoFile = 3,
  ARKTorrentErrorTimedOut = 4,
};

/// Mirrors the Android bridge's status map ("state", "peers", "downloadRate", "progress").
typedef void (^ARKTorrentStatusHandler)(NSDictionary<NSString *, id> *status);

@interface ARKTorrentStartResult : NSObject
@property(nonatomic, copy, readonly) NSString *filePath;
@property(nonatomic, copy, readonly) NSString *fileName;
@property(nonatomic, readonly) int64_t downloadedBytes;
@property(nonatomic, readonly) int64_t totalBytes;
@end

/// Objective-C++ bridge around libtorrent-rasterbar. A direct, deliberately
/// thin port of the Android bridge's TorrentStreamManager.kt (+ its
/// reader-driven Scheduler) onto libtorrent-rasterbar's native C++ API,
/// kept behind a pure Objective-C surface so Swift can import it on both
/// macOS and iOS with no bridging-header plumbing.
@interface ARKTorrentEngine : NSObject

+ (instancetype)sharedEngine NS_SWIFT_NAME(shared());

/// Starts the libtorrent session (DHT bootstrap etc.) ahead of time - see
/// TorrentStreamManager.kt's warmUp for why this is called the instant the
/// torrent source picker opens rather than only once a magnet is chosen.
- (void)warmUpWithCacheDirectory:(NSString *)cacheDirectory
    NS_SWIFT_NAME(warmUp(cacheDirectory:));

/// Queues a magnet for background download into `downloadsDirectory`
/// without streaming it. Throws via `error` if the magnet is invalid.
- (BOOL)queueDownloadMagnet:(NSString *)magnet
         downloadsDirectory:(NSString *)downloadsDirectory
                      error:(NSError **)error
    NS_SWIFT_NAME(queueDownload(magnet:downloadsDirectory:));

/// Blocks the calling thread (call this off the main/UI thread) until
/// enough of the selected file has arrived to start streaming, or throws
/// after a two-minute timeout. `preferredFileIndex` is Torrentio's
/// season-pack hint (see TorrentSource.fileIndex); pass nil to fall back to
/// "largest video file in the torrent".
- (nullable ARKTorrentStartResult *)
    startMagnet:(NSString *)magnet
    preferredFileIndex:(nullable NSNumber *)preferredFileIndex
    cacheDirectory:(NSString *)cacheDirectory
    statusHandler:(ARKTorrentStatusHandler)statusHandler
    error:(NSError **)error
    NS_SWIFT_NAME(startMagnet(_:preferredFileIndex:cacheDirectory:statusHandler:));

/// Called by the HTTP server the instant it parses a new Range request, so
/// a seek retargets piece priorities immediately - see Scheduler.retarget.
- (void)registerReaderOffset:(int64_t)offsetInFile
    NS_SWIFT_NAME(registerReader(offset:));

/// Given a request's own start offset, returns the contiguous available
/// absolute byte boundary for the active stream's file - see
/// TorrentStreamManager.kt's contiguousAvailableFrom.
- (int64_t)availableContiguousBytesFrom:(int64_t)fromByte
    NS_SWIFT_NAME(availableContiguousBytes(from:));

/// Stops any in-flight stream and wipes both the streaming cache and the
/// queued-download directory.
- (void)clearCacheDirectory:(NSString *)cacheDirectory
          downloadsDirectory:(NSString *)downloadsDirectory
    NS_SWIFT_NAME(clearCache(cacheDirectory:downloadsDirectory:));

@end

NS_ASSUME_NONNULL_END
