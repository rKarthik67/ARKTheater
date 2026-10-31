#import "ARKTorrentEngine.h"

#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/download_priority.hpp>
#include <libtorrent/error_code.hpp>
#include <libtorrent/file_storage.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/session.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/torrent_status.hpp>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <memory>
#include <mutex>
#include <set>
#include <string>
#include <thread>
#include <vector>

NSErrorDomain const ARKTorrentErrorDomain = @"ARKTorrentErrorDomain";

namespace {

namespace lt = libtorrent;

// Was 12MB on Android - see TorrentStreamManager.kt's own comment: a real
// player only needs to parse the container header and a few seconds of
// queued video, so 4MB (a few seconds at typical torrent-release bitrates)
// avoids unnecessary startup latency without the engine estimating bitrate.
constexpr int64_t kStartupBytes = 4LL * 1024 * 1024;
constexpr int64_t kTimeoutMs = 120'000;

constexpr int kTickMs = 500;
constexpr int64_t kRushBytes = 6LL * 1024 * 1024;
constexpr int64_t kReadaheadBytes = 48LL * 1024 * 1024;
constexpr int64_t kRewindBytes = 12LL * 1024 * 1024;
// MKV's seek index (Cues) commonly sits at the end of the file, not the
// front - keeping the tail at top priority unconditionally means it's
// usually already there by the time an extractor actually needs it. Mirrors
// TorrentStreamManager.kt's Scheduler.tailBytes.
constexpr int64_t kTailBytes = 4LL * 1024 * 1024;
constexpr int64_t kStallMs = 5'000;
constexpr int64_t kStarveMs = 5'000;
constexpr int64_t kShakeIntervalMs = 10'000;

const std::set<std::string>& videoExtensions() {
  static const std::set<std::string> extensions = {"mp4", "mkv", "webm",
                                                     "avi", "mov", "m4v", "ts"};
  return extensions;
}

std::string lowercaseExtension(std::string const &fileName) {
  auto pos = fileName.find_last_of('.');
  if (pos == std::string::npos) return "";
  std::string ext = fileName.substr(pos + 1);
  std::transform(ext.begin(), ext.end(), ext.begin(),
                  [](unsigned char c) { return std::tolower(c); });
  return ext;
}

int64_t nowMs() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}

bool isMagnet(std::string const &value) {
  std::string prefix = value.substr(0, 8);
  std::transform(prefix.begin(), prefix.end(), prefix.begin(),
                  [](unsigned char c) { return std::tolower(c); });
  return prefix == "magnet:?";
}

/// Reader-position-driven piece scheduler, replacing plain sequential
/// download - a direct port of TorrentStreamManager.kt's Scheduler. See that
/// file's doc comment for the rush/readahead/rewind/tail zone rationale.
class Scheduler {
 public:
  Scheduler(lt::torrent_handle handle, int firstPiece, int lastPiece,
            int64_t fileStart, int pieceLength)
      : handle_(std::move(handle)),
        firstPiece_(firstPiece),
        lastPiece_(lastPiece),
        fileStart_(fileStart),
        pieceLength_(pieceLength) {}

  ~Scheduler() { stop(); }

  void start() {
    running_.store(true);
    thread_ = std::thread([this] { run(); });
  }

  void stop() {
    running_.store(false);
    if (thread_.joinable()) thread_.join();
  }

  void retarget(int64_t offsetInFile) {
    target_.store(std::max<int64_t>(0, offsetInFile));
  }

 private:
  void run() {
    while (running_.load()) {
      try {
        tick();
      } catch (...) {
        // The handle can go invalid mid-tick if the session is reset by a
        // new startMagnet call; stop() will already have been requested.
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(kTickMs));
    }
  }

  void tick() {
    if (!handle_.is_valid()) return;
    int64_t now = nowMs();
    int64_t absoluteTarget = fileStart_ + target_.load();
    int targetPiece = std::clamp(
        static_cast<int>(absoluteTarget / pieceLength_), firstPiece_, lastPiece_);
    int rushPieces = std::max(
        1, static_cast<int>((kRushBytes + pieceLength_ - 1) / pieceLength_));
    int rewindPieces =
        static_cast<int>((kRewindBytes + pieceLength_ - 1) / pieceLength_);

    if (targetPiece != lastTargetPiece_) {
      lastTargetPiece_ = targetPiece;
      rushSince_ = now;
    }

    bool blocked = !handle_.have_piece(lt::piece_index_t(targetPiece));
    bool starving = blocked && (now - rushSince_ > kStarveMs);
    int readaheadPieces =
        starving ? rushPieces
                 : std::max(rushPieces,
                            static_cast<int>((kReadaheadBytes + pieceLength_ - 1) /
                                             pieceLength_));

    int rushEnd = std::min(lastPiece_, targetPiece + rushPieces);
    int readaheadEnd = std::min(lastPiece_, targetPiece + readaheadPieces);
    int rewindStart = std::max(firstPiece_, targetPiece - rewindPieces);
    int tailPieces = std::max(
        1, static_cast<int>((kTailBytes + pieceLength_ - 1) / pieceLength_));
    int tailStart = std::max(firstPiece_, lastPiece_ - tailPieces + 1);

    for (int piece = firstPiece_; piece <= lastPiece_; piece++) {
      if (handle_.have_piece(lt::piece_index_t(piece))) continue;
      bool inTail = piece >= tailStart;
      lt::download_priority_t priority;
      if (piece >= targetPiece && piece <= rushEnd) {
        priority = lt::top_priority;
      } else if (inTail) {
        priority = lt::top_priority;
      } else if (piece >= rewindStart && piece < targetPiece) {
        priority = lt::low_priority;
      } else if (piece >= targetPiece && piece <= readaheadEnd) {
        priority = lt::default_priority;
      } else {
        priority = lt::dont_download;
      }
      handle_.piece_priority(lt::piece_index_t(piece), priority);
      if (priority == lt::top_priority) {
        int deadline = inTail ? 4000 : (piece - targetPiece) * 800;
        handle_.set_piece_deadline(lt::piece_index_t(piece), deadline);
      }
    }

    lt::torrent_status status = handle_.status();
    if (status.download_rate > 0) lastDataAt_ = now;

    // Stall watchdog: re-kick the one piece playback is blocked on solo
    // rather than waiting for the swarm to satisfy it on its own.
    if (blocked && now - rushSince_ > kStallMs) {
      handle_.piece_priority(lt::piece_index_t(targetPiece), lt::top_priority);
      handle_.reset_piece_deadline(lt::piece_index_t(targetPiece));
      handle_.set_piece_deadline(lt::piece_index_t(targetPiece), 0);
      rushSince_ = now;
    }

    // Shake: force a fresh tracker/DHT announce to surface peers we aren't
    // currently connected to.
    if ((now - lastDataAt_ > kStarveMs || starving) &&
        now - lastShakeAt_ > kShakeIntervalMs) {
      lastShakeAt_ = now;
      try {
        handle_.force_reannounce();
      } catch (...) {
      }
      try {
        handle_.force_dht_announce();
      } catch (...) {
      }
    }
  }

  lt::torrent_handle handle_;
  int firstPiece_;
  int lastPiece_;
  int64_t fileStart_;
  int pieceLength_;
  std::atomic<int64_t> target_{0};
  std::atomic<bool> running_{false};
  std::thread thread_;
  int lastTargetPiece_ = -1;
  int64_t rushSince_ = 0;
  int64_t lastDataAt_ = 0;
  int64_t lastShakeAt_ = 0;
};

int largestVideoIndex(lt::file_storage const &fs) {
  int best = -1;
  int64_t bestSize = -1;
  for (int i = 0; i < fs.num_files(); i++) {
    auto index = lt::file_index_t(i);
    std::string ext = lowercaseExtension(std::string(fs.file_name(index)));
    if (videoExtensions().count(ext) && fs.file_size(index) > bestSize) {
      best = i;
      bestSize = fs.file_size(index);
    }
  }
  return best;
}

int pickFileIndex(lt::file_storage const &fs, int preferredFileIndex) {
  if (preferredFileIndex >= 0 && preferredFileIndex < fs.num_files()) {
    auto index = lt::file_index_t(preferredFileIndex);
    std::string ext = lowercaseExtension(std::string(fs.file_name(index)));
    if (videoExtensions().count(ext)) return preferredFileIndex;
  }
  return largestVideoIndex(fs);
}

void deprioritizeOtherFiles(lt::torrent_handle &handle,
                             lt::file_storage const &fs, int selectedIndex) {
  std::vector<lt::download_priority_t> priorities(
      fs.num_files(), lt::dont_download);
  priorities[selectedIndex] = lt::default_priority;
  handle.prioritize_files(priorities);
}

/// Like the Kotlin contiguousAvailableFrom: given a request's own start
/// offset (not always byte 0 - a seek, or an extractor reading a container's
/// tail-of-file seek index first), returns how far the contiguously
/// downloaded region extends from there.
int64_t contiguousAvailableFrom(lt::torrent_handle &handle,
                                 lt::torrent_info const &info, int fileIndex,
                                 int64_t fileSize, int64_t fromByte) {
  lt::file_storage const &fs = info.layout();
  auto index = lt::file_index_t(fileIndex);
  int64_t fileStart = fs.file_offset(index);
  int64_t fileEnd = fileStart + fileSize;
  int pieceLength = info.piece_length();
  int firstPiece = static_cast<int>(fileStart / pieceLength);
  int lastPiece = static_cast<int>((fileEnd - 1) / pieceLength);
  int64_t from = std::clamp(fileStart + fromByte, fileStart, fileEnd);
  int startPiece =
      std::clamp(static_cast<int>(from / pieceLength), firstPiece, lastPiece);
  int64_t boundary = from;
  for (int piece = startPiece; piece <= lastPiece; piece++) {
    if (!handle.have_piece(lt::piece_index_t(piece))) break;
    int64_t pieceStart = static_cast<int64_t>(piece) * pieceLength;
    int64_t size = info.piece_size(lt::piece_index_t(piece));
    int64_t pieceEnd = std::min(pieceStart + size, fileEnd);
    if (pieceEnd <= boundary) continue;
    boundary = pieceEnd;
  }
  return std::clamp(boundary - fileStart, fromByte, fileSize);
}

NSError *makeError(ARKTorrentErrorCode code, NSString *message) {
  return [NSError errorWithDomain:ARKTorrentErrorDomain
                              code:code
                          userInfo:@{NSLocalizedDescriptionKey : message}];
}

}  // namespace

@implementation ARKTorrentStartResult {
 @public
  NSString *_filePath;
  NSString *_fileName;
  int64_t _downloadedBytes;
  int64_t _totalBytes;
}
- (NSString *)filePath { return _filePath; }
- (NSString *)fileName { return _fileName; }
- (int64_t)downloadedBytes { return _downloadedBytes; }
- (int64_t)totalBytes { return _totalBytes; }
@end

@implementation ARKTorrentEngine {
  std::mutex _mutex;
  std::unique_ptr<lt::session> _session;
  std::unique_ptr<Scheduler> _scheduler;

  // Active-stream state consulted by availableContiguousBytesFrom: /
  // registerReaderOffset: while a stream is live.
  lt::torrent_handle _activeHandle;
  std::shared_ptr<const lt::torrent_info> _activeInfo;
  int _activeFileIndex;
  int64_t _activeFileSize;
}

+ (instancetype)sharedEngine {
  static ARKTorrentEngine *instance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[ARKTorrentEngine alloc] init];
  });
  return instance;
}

- (instancetype)init {
  if (self = [super init]) {
    _activeFileIndex = -1;
    _activeFileSize = 0;
  }
  return self;
}

/// Mirrors TorrentStreamManager.kt's tunedSettings: plain default libtorrent
/// settings connect to peers cautiously and give a stalled request far
/// longer before retrying elsewhere than a streaming player can tolerate.
- (lt::settings_pack)tunedSettings {
  lt::settings_pack pack;
  unsigned long long totalMemory = [NSProcessInfo processInfo].physicalMemory;
  bool tightMemory = totalMemory > 0 && totalMemory <= (3ULL * 1024 * 1024 * 1024);
  int peers = tightMemory ? 80 : 200;

  pack.set_bool(lt::settings_pack::enable_dht, true);
  pack.set_int(lt::settings_pack::connections_limit, peers);
  pack.set_int(lt::settings_pack::active_dht_limit, 88);
  pack.set_int(lt::settings_pack::download_rate_limit, 0);
  pack.set_int(lt::settings_pack::upload_rate_limit, 0);
  pack.set_int(lt::settings_pack::torrent_connect_boost, peers);
  pack.set_int(lt::settings_pack::connection_speed, peers);
  pack.set_int(lt::settings_pack::peer_connect_timeout, 5);
  pack.set_int(lt::settings_pack::whole_pieces_threshold, 10);
  pack.set_int(lt::settings_pack::request_timeout, 6);
  pack.set_bool(lt::settings_pack::strict_end_game_mode, false);
  pack.set_int(lt::settings_pack::max_out_request_queue, 1500);
  pack.set_bool(lt::settings_pack::close_redundant_connections, false);
  pack.set_str(lt::settings_pack::listen_interfaces, "0.0.0.0:6881,[::]:6881");
  return pack;
}

// Call with _mutex already held.
- (lt::session &)ensureSessionLocked {
  if (!_session) {
    _session = std::make_unique<lt::session>([self tunedSettings]);
  }
  return *_session;
}

- (void)warmUpWithCacheDirectory:(NSString *)cacheDirectory {
  std::lock_guard<std::mutex> lock(_mutex);
  [self ensureSessionLocked];
}

- (BOOL)queueDownloadMagnet:(NSString *)magnet
         downloadsDirectory:(NSString *)downloadsDirectory
                      error:(NSError **)error {
  std::string magnetStr = magnet.UTF8String ?: "";
  if (!isMagnet(magnetStr)) {
    if (error) *error = makeError(ARKTorrentErrorInvalidMagnet, @"Enter a valid magnet URI.");
    return NO;
  }
  [[NSFileManager defaultManager] createDirectoryAtPath:downloadsDirectory
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];
  std::lock_guard<std::mutex> lock(_mutex);
  lt::session &session = [self ensureSessionLocked];

  lt::add_torrent_params params;
  lt::error_code parseEc;
  lt::parse_magnet_uri(magnetStr, params, parseEc);
  if (parseEc) {
    if (error) *error = makeError(ARKTorrentErrorInvalidMagnet, @"Enter a valid magnet URI.");
    return NO;
  }
  params.save_path = downloadsDirectory.UTF8String;
  lt::error_code addEc;
  session.add_torrent(params, addEc);
  if (addEc) {
    if (error) {
      *error = makeError(ARKTorrentErrorAddFailed,
                          @"Could not add this torrent. Check the magnet URI and try again.");
    }
    return NO;
  }
  return YES;
}

- (nullable ARKTorrentStartResult *)
    startMagnet:(NSString *)magnet
    preferredFileIndex:(nullable NSNumber *)preferredFileIndex
    cacheDirectory:(NSString *)cacheDirectory
    statusHandler:(ARKTorrentStatusHandler)statusHandler
    error:(NSError **)error {
  std::string magnetStr = magnet.UTF8String ?: "";
  if (!isMagnet(magnetStr)) {
    if (error) *error = makeError(ARKTorrentErrorInvalidMagnet, @"Enter a valid magnet URI.");
    return nil;
  }

  NSString *saveDir =
      [cacheDirectory stringByAppendingPathComponent:@"torrent-streams"];
  [[NSFileManager defaultManager] createDirectoryAtPath:saveDir
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];

  lt::torrent_handle handle;
  {
    std::lock_guard<std::mutex> lock(_mutex);
    if (_scheduler) {
      _scheduler->stop();
      _scheduler.reset();
    }
    _activeFileIndex = -1;
    _activeInfo.reset();

    lt::session &session = [self ensureSessionLocked];

    lt::add_torrent_params params;
    lt::error_code parseEc;
    lt::parse_magnet_uri(magnetStr, params, parseEc);
    if (parseEc) {
      if (error) *error = makeError(ARKTorrentErrorInvalidMagnet, @"Enter a valid magnet URI.");
      return nil;
    }
    params.save_path = saveDir.UTF8String;
    lt::error_code addEc;
    handle = session.add_torrent(params, addEc);
    if (addEc || !handle.is_valid()) {
      if (error) {
        *error = makeError(ARKTorrentErrorAddFailed,
                            @"Could not add this torrent. Check the magnet URI and try again.");
      }
      return nil;
    }
  }

  int preferredIndex = preferredFileIndex ? preferredFileIndex.intValue : -1;
  int64_t deadline = nowMs() + kTimeoutMs;
  int selectedIndex = -1;
  std::string selectedPath;
  int64_t selectedTotal = 0;
  bool scheduled = false;

  while (nowMs() < deadline) {
    if (!handle.is_valid()) break;
    lt::torrent_status status = handle.status();
    statusHandler(@{
      @"state" : status.has_metadata ? @"Buffering" : @"Finding peers",
      @"peers" : @(status.num_peers),
      @"downloadRate" : @(status.download_rate),
      @"progress" : @(status.progress),
    });

    std::shared_ptr<const lt::torrent_info> info = handle.torrent_file();
    if (info) {
      lt::file_storage const &fs = info->layout();
      if (selectedIndex < 0) {
        selectedIndex = pickFileIndex(fs, preferredIndex);
        if (selectedIndex >= 0) {
          auto fi = lt::file_index_t(selectedIndex);
          selectedPath = fs.file_path(fi, saveDir.UTF8String);
          selectedTotal = fs.file_size(fi);
          deprioritizeOtherFiles(handle, fs, selectedIndex);

          int64_t fileStart = fs.file_offset(fi);
          int pieceLength = info->piece_length();
          int firstPiece = static_cast<int>(fileStart / pieceLength);
          int lastPiece =
              static_cast<int>((fileStart + selectedTotal - 1) / pieceLength);

          std::lock_guard<std::mutex> lock(_mutex);
          _scheduler = std::make_unique<Scheduler>(handle, firstPiece,
                                                    lastPiece, fileStart,
                                                    pieceLength);
          _scheduler->start();
          _activeHandle = handle;
          _activeInfo = info;
          _activeFileIndex = selectedIndex;
          _activeFileSize = selectedTotal;
          scheduled = true;
        }
      }
      if (selectedIndex >= 0) {
        int64_t contiguous =
            contiguousAvailableFrom(handle, *info, selectedIndex, selectedTotal, 0);
        if (contiguous >= std::min(kStartupBytes, selectedTotal)) {
          ARKTorrentStartResult *result = [[ARKTorrentStartResult alloc] init];
          result->_filePath = [NSString stringWithUTF8String:selectedPath.c_str()];
          result->_fileName =
              [NSString stringWithUTF8String:std::string(fs.file_name(
                                                              lt::file_index_t(selectedIndex)))
                                                  .c_str()];
          result->_downloadedBytes = contiguous;
          result->_totalBytes = selectedTotal;
          return result;
        }
      }
    } else {
      statusHandler(@{
        @"state" : @"Connecting to peers",
        @"peers" : @0,
        @"downloadRate" : @0,
        @"progress" : @0.0,
      });
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(500));
  }

  if (scheduled) {
    std::lock_guard<std::mutex> lock(_mutex);
    if (_scheduler) {
      _scheduler->stop();
      _scheduler.reset();
    }
  }
  if (error) {
    if (!handle.is_valid()) {
      *error = makeError(ARKTorrentErrorAddFailed,
                          @"Could not add this torrent. Check the magnet URI and try again.");
    } else if (selectedIndex < 0) {
      *error = makeError(ARKTorrentErrorNoVideoFile,
                          @"No supported video file was found in this torrent.");
    } else {
      *error = makeError(ARKTorrentErrorTimedOut,
                          @"No playable data arrived in two minutes. Check seed availability.");
    }
  }
  return nil;
}

- (void)registerReaderOffset:(int64_t)offsetInFile {
  std::lock_guard<std::mutex> lock(_mutex);
  if (_scheduler) _scheduler->retarget(offsetInFile);
}

- (int64_t)availableContiguousBytesFrom:(int64_t)fromByte {
  std::lock_guard<std::mutex> lock(_mutex);
  if (_activeFileIndex < 0 || !_activeInfo || !_activeHandle.is_valid()) return 0;
  return contiguousAvailableFrom(_activeHandle, *_activeInfo, _activeFileIndex,
                                  _activeFileSize, fromByte);
}

- (void)clearCacheDirectory:(NSString *)cacheDirectory
          downloadsDirectory:(NSString *)downloadsDirectory {
  {
    std::lock_guard<std::mutex> lock(_mutex);
    if (_scheduler) {
      _scheduler->stop();
      _scheduler.reset();
    }
    _activeFileIndex = -1;
    _activeInfo.reset();
    _activeHandle = lt::torrent_handle();
    _session.reset();
  }
  NSString *streamsDir =
      [cacheDirectory stringByAppendingPathComponent:@"torrent-streams"];
  [[NSFileManager defaultManager] removeItemAtPath:streamsDir error:nil];
  [[NSFileManager defaultManager] removeItemAtPath:downloadsDirectory error:nil];
}

@end
