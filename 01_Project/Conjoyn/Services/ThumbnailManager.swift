import Foundation
import AppKit

// MARK: - Thumbnail Manager (Wave 1, task 1.10)

/// Manages asynchronous thumbnail generation for DJI clips with caching and concurrency control.
///
/// Ported from P2toMXF (`Services/ThumbnailManager.swift`). The cache (LRU), the bounded
/// concurrency semaphore, and the cancellation machinery are format-agnostic and port verbatim.
///
/// **The DJI change:** P2 clips had a PROXY → ICON → VIDEO(MXF) fallback chain per frame (a P2 card
/// carries low-res proxies and a first-frame BMP). A DJI segment is a single self-contained MP4/MOV,
/// so extraction reads directly from `clip.videoURL` — no fallback chain, and the P2 `ThumbnailSource`
/// indicator enum is dropped.
actor ThumbnailManager {

    /// Thumbnail pair for a clip (first and last frames).
    struct ClipThumbnails: Sendable {
        let first: NSImage?
        let last: NSImage?

        static let empty = ClipThumbnails(first: nil, last: nil)
    }

    // MARK: - Properties

    private let ffmpeg: FFmpegWrapper
    private var cache: [UUID: ClipThumbnails] = [:]
    private var pendingTasks: [UUID: Task<ClipThumbnails, Never>] = [:]

    /// LRU cache eviction - tracks access order (most recent at end)
    private var accessOrder: [UUID] = []
    /// Maximum number of clips to cache thumbnails for
    private let maxCacheSize = 100

    /// Semaphore to limit concurrent FFmpeg processes
    private let maxConcurrentExtractions = 3
    private var activeExtractions = 0

    /// Identified continuation for cancellation support.
    /// Wraps the continuation with a UUID so we can find and remove it when cancelled.
    private struct WaitingContinuation {
        let id: UUID
        let continuation: CheckedContinuation<Void, Never>
    }
    private var waitingContinuations: [WaitingContinuation] = []

    // MARK: - Initialization

    init(ffmpeg: FFmpegWrapper = FFmpegWrapper()) {
        self.ffmpeg = ffmpeg
    }

    // MARK: - Public API

    /// Request thumbnails for a clip. Returns cached result or starts extraction.
    /// - Parameter clip: The DJI clip to get thumbnails for.
    /// - Returns: `ClipThumbnails` with first and last frame images.
    func getThumbnails(for clip: DJIClip) async -> ClipThumbnails {
        // Return cached result if available
        if let cached = cache[clip.id] {
            // Update LRU access order (move to most recent)
            updateAccessOrder(for: clip.id)
            return cached
        }

        // Return result from pending task if already in progress
        if let pendingTask = pendingTasks[clip.id] {
            return await pendingTask.value
        }

        // Start new extraction task
        let task = Task {
            await extractThumbnails(for: clip)
        }
        pendingTasks[clip.id] = task

        let result = await task.value
        pendingTasks[clip.id] = nil

        // Store in cache with LRU tracking
        cache[clip.id] = result
        updateAccessOrder(for: clip.id)

        // Evict oldest entries if cache exceeds limit
        evictOldestIfNeeded()

        return result
    }

    // MARK: - LRU Cache Management

    /// Updates access order for LRU tracking (moves clip to most recently used).
    private func updateAccessOrder(for clipId: UUID) {
        // Remove existing entry (if present)
        accessOrder.removeAll { $0 == clipId }
        // Add to end (most recently used)
        accessOrder.append(clipId)
    }

    /// Evicts oldest cache entries if cache exceeds maximum size.
    private func evictOldestIfNeeded() {
        while cache.count > maxCacheSize, let oldest = accessOrder.first {
            accessOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }

    /// Cancel pending thumbnail extraction for a clip (e.g., when a row scrolls off screen).
    func cancelRequest(for clipId: UUID) {
        pendingTasks[clipId]?.cancel()
        pendingTasks[clipId] = nil
    }

    /// Clear all cached thumbnails (e.g., when loading a new DJI folder).
    func clearCache() {
        cache.removeAll()
        accessOrder.removeAll()
        for task in pendingTasks.values {
            task.cancel()
        }
        pendingTasks.removeAll()
    }

    /// Check if thumbnails are cached for a clip.
    func hasCachedThumbnails(for clipId: UUID) -> Bool {
        cache[clipId] != nil
    }

    // MARK: - Private Extraction Logic

    /// Extract both first and last frame thumbnails for a clip, directly from its MP4/MOV.
    private func extractThumbnails(for clip: DJIClip) async -> ClipThumbnails {
        // Extract first and last frames concurrently
        async let firstFrame = extractFrameWithSemaphore(from: clip.videoURL, atSeconds: 0)
        async let lastFrame = extractFrameWithSemaphore(from: clip.videoURL, atSeconds: clip.lastFrameSeekSeconds)

        return ClipThumbnails(
            first: await firstFrame,
            last: await lastFrame
        )
    }

    /// Extract a frame with semaphore-controlled concurrency.
    private func extractFrameWithSemaphore(from url: URL, atSeconds timestamp: Double) async -> NSImage? {
        // Wait for semaphore slot
        let acquired = await acquireSemaphore()
        guard acquired else { return nil }  // Cancelled while waiting
        defer { releaseSemaphore() }

        // Check for cancellation before starting the expensive operation
        guard !Task.isCancelled else { return nil }

        return await ffmpeg.extractFrame(from: url, atSeconds: timestamp)
    }

    // MARK: - Semaphore Implementation

    /// Returns true if the semaphore was acquired, false if cancelled while waiting.
    private func acquireSemaphore() async -> Bool {
        if activeExtractions < maxConcurrentExtractions {
            activeExtractions += 1
            return true
        }

        // Generate unique ID for this waiter (for cancellation tracking)
        let waiterId = UUID()

        // Wait until a slot is available, with cancellation support
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waitingContinuations.append(WaitingContinuation(id: waiterId, continuation: continuation))
            }
        } onCancel: {
            // Note: onCancel runs on ANY thread, NOT isolated to the actor.
            // Schedule cleanup on the actor to safely access state.
            Task { [waiterId] in
                await self.handleWaiterCancellation(waiterId)
            }
        }

        // Check if we were cancelled. If so, we were NOT granted a slot —
        // handleWaiterCancellation just resumed us to unblock. Don't touch the count.
        if Task.isCancelled {
            return false
        }

        // We were resumed by releaseSemaphore(), which means a slot was freed for us.
        // The slot was already "transferred" — increment to claim it.
        activeExtractions += 1
        return true
    }

    /// Handle cancellation of a waiting task.
    /// Removes the continuation from the waiting list and resumes it.
    /// Does NOT grant a slot — the resumed task checks `Task.isCancelled` and returns false.
    private func handleWaiterCancellation(_ waiterId: UUID) {
        if let index = waitingContinuations.firstIndex(where: { $0.id == waiterId }) {
            let waiter = waitingContinuations.remove(at: index)
            // Resume continuation so the task can check for cancellation and exit cleanly.
            // No slot is granted — the waiter will return false from acquireSemaphore.
            waiter.continuation.resume()
        }
    }

    private func releaseSemaphore() {
        if let waiter = waitingContinuations.first {
            // Transfer our slot to the next waiter (they will increment activeExtractions)
            waitingContinuations.removeFirst()
            activeExtractions -= 1  // Release our slot
            waiter.continuation.resume()  // Waiter will re-increment in acquireSemaphore
        } else {
            activeExtractions -= 1
        }
    }
}
