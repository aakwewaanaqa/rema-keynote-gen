import Darwin
import Foundation

// 查詢中彈窗要顯示的是「現在這台 Mac 的網路上下傳速度」（跟 Activity Monitor 的網路頁籤同一種數字），
// 不是這次查詢本身的進度——帶著查經班的人在教會現場常常是 Wi-Fi 很多人擠、忽快忽慢，
// 使用者要看的是「現在網路本身順不順」，方便判斷是網路慢還是別的問題，跟查詢邏輯無關，
// 所以獨立成一個跟 BibleQueryTask 沒有關係的小工具，之後其他畫面要用也能直接拿去用。
private struct NetworkByteCounters {
    var bytesIn: UInt64
    var bytesOut: UInt64
}

// 加總所有「已啟用、非 loopback」網路介面目前累計收/送的位元組數。
// getifaddrs 對同一個介面會回傳好幾筆（各種位址家族各一筆），位元組計數只掛在 AF_LINK 那一筆上，
// 不篩會重複加總、算出來的速度變好幾倍。
private func currentNetworkByteCounters() -> NetworkByteCounters {
    var bytesIn: UInt64 = 0
    var bytesOut: UInt64 = 0

    var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else {
        return NetworkByteCounters(bytesIn: 0, bytesOut: 0)
    }
    defer { freeifaddrs(ifaddrPtr) }

    var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
    while let addr = ptr {
        let ifa = addr.pointee
        ptr = ifa.ifa_next

        let flags = Int32(ifa.ifa_flags)
        guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
        guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_LINK) else { continue }
        guard let data = ifa.ifa_data else { continue }

        let networkData = data.assumingMemoryBound(to: if_data.self).pointee
        bytesIn += UInt64(networkData.ifi_ibytes)
        bytesOut += UInt64(networkData.ifi_obytes)
    }
    return NetworkByteCounters(bytesIn: bytesIn, bytesOut: bytesOut)
}

@MainActor
final class NetworkThroughputMonitor: ObservableObject {
    @Published var downloadKBps: Double = 0
    @Published var uploadKBps: Double = 0

    private var timer: Timer?
    private var lastCounters: NetworkByteCounters?
    private var lastSampleTime: Date?

    func start() {
        stop()
        lastCounters = currentNetworkByteCounters()
        lastSampleTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastCounters = nil
        lastSampleTime = nil
        downloadKBps = 0
        uploadKBps = 0
    }

    private func tick() {
        let now = Date()
        let counters = currentNetworkByteCounters()
        defer {
            lastCounters = counters
            lastSampleTime = now
        }
        guard let last = lastCounters, let lastTime = lastSampleTime else { return }
        let elapsed = now.timeIntervalSince(lastTime)
        guard elapsed > 0 else { return }

        // 切換 Wi-Fi/介面重置會讓計數器歸零、變得比上一筆還小，這種情況當作這一拍量不到，
        // 不要算出負的速度
        let inDelta = counters.bytesIn >= last.bytesIn ? counters.bytesIn - last.bytesIn : 0
        let outDelta = counters.bytesOut >= last.bytesOut ? counters.bytesOut - last.bytesOut : 0
        downloadKBps = Double(inDelta) / 1024.0 / elapsed
        uploadKBps = Double(outDelta) / 1024.0 / elapsed
    }
}
