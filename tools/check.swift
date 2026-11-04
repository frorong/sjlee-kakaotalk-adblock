// kleantalk-check: 카카오톡과 같은 방식(시스템 인증서 신뢰 + /etc/hosts)으로 빈 광고 서버에 접속해 본다.
// 성공하면 0, 아니면 1로 끝난다. 어디에도 외부 연결을 하지 않는다 (hosts가 깨져 있으면 연결 자체를 하지 않음).
import Foundation

let host = "serv.ds.kakao.com"
let expectedAddr = "127.84.11.1"

// hosts가 풀려 진짜 카카오 서버로 나가는 일이 없게, 먼저 이름이 전용 주소로 풀리는지 확인한다
func resolves(_ name: String) -> [String] {
    var hints = addrinfo(ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_STREAM, ai_protocol: 0,
                         ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
    var res: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(name, nil, &hints, &res) == 0 else { return [] }
    defer { freeaddrinfo(res) }
    var out: [String] = []
    var p = res
    while let ai = p {
        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        ai.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
            var a = sin.pointee.sin_addr
            inet_ntop(AF_INET, &a, &buf, socklen_t(INET_ADDRSTRLEN))
        }
        out.append(String(cString: buf))
        p = ai.pointee.ai_next
    }
    return out
}

let addrs = resolves(host)
guard addrs.contains(expectedAddr), addrs.allSatisfy({ $0 == expectedAddr }) else {
    print("FAIL hosts: \(host) -> \(addrs.isEmpty ? "(없음)" : addrs.joined(separator: ","))  (기대값 \(expectedAddr))")
    exit(1)
}

let config = URLSessionConfiguration.ephemeral
config.timeoutIntervalForRequest = 5
config.connectionProxyDictionary = [:]   // 프록시 무시
let session = URLSession(configuration: config)
let sem = DispatchSemaphore(value: 0)
var ok = false
session.dataTask(with: URL(string: "https://\(host)/sdk/banner?kleantalk=check")!) { data, resp, err in
    defer { sem.signal() }
    if let err { print("FAIL tls/http: \(err.localizedDescription)"); return }
    guard let h = resp as? HTTPURLResponse else { print("FAIL 응답 없음"); return }
    let marker = h.value(forHTTPHeaderField: "X-KleanTalk") ?? "-"
    if h.statusCode == 200 && marker == "1" {
        ok = true
        print("OK  빈 광고 서버 응답 (HTTP 200, 인증서 신뢰됨)")
    } else {
        print("FAIL HTTP \(h.statusCode), X-KleanTalk=\(marker)")
    }
}.resume()
if sem.wait(timeout: .now() + 8) == .timedOut { print("FAIL 시간 초과") }
exit(ok ? 0 : 1)
