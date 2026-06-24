//
//  MockDataSanitizer.swift
//  SLT Usage Meter
//

import Foundation

#if DEBUG
struct MockDataSanitizer {
    private static var mockMappings: [String: String] {
        get { UserDefaults(suiteName: AppConstants.suiteName)?.dictionary(forKey: "MockMappingsV3") as? [String: String] ?? [:] }
        set { UserDefaults(suiteName: AppConstants.suiteName)?.set(newValue, forKey: "MockMappingsV3") }
    }
    
    // MARK: - Screenshot Configuration
    
    // Change these indices to determine which dummy accounts appear as THROTTLED.
    // For example, [1] throttles the first account, [3] throttles the third.
    private static let throttledAccountIndices = [3]
    
    private static func isThrottled(dummyPhone: String) -> Bool {
        for index in throttledAccountIndices {
            if dummyPhone.hasSuffix(String(index)) {
                return true
            }
        }
        return false
    }
    
    private static func mockValue(for original: String?, base: String, keyType: String) -> String {
        guard let original = original else { return base }
        if let existing = mockMappings[original] { return existing }
        
        // Dynamically find the highest suffix currently used for this exact base
        var maxIndex = 0
        for val in mockMappings.values {
            if val.hasPrefix(base) {
                let suffix = val.dropFirst(base.count)
                // Ensure the suffix is purely numeric to avoid cross-contamination (e.g. 123456789_BB1 matching 1234567891)
                if let num = Int(suffix), num > maxIndex {
                    maxIndex = num
                }
            }
        }
        
        let mocked = "\(base)\(maxIndex + 1)"
        
        var mappings = mockMappings
        mappings[original] = mocked
        mockMappings = mappings
        
        return mocked
    }
    
    static func sanitizeRequest(_ request: URLRequest) -> URLRequest {
        var newRequest = request
        guard let urlString = request.url?.absoluteString else { return request }
      
        var updatedUrlString = urlString
        for (original, mocked) in mockMappings {
            updatedUrlString = updatedUrlString.replacingOccurrences(of: mocked, with: original)
            
            if mocked.hasPrefix("0") && original.hasPrefix("0") {
                let internationalMocked = "94" + mocked.dropFirst()
                let internationalOriginal = "94" + original.dropFirst()
                updatedUrlString = updatedUrlString.replacingOccurrences(of: internationalMocked, with: internationalOriginal)
            }
        }
        
        if let newUrl = URL(string: updatedUrlString) {
            newRequest.url = newUrl
        }
        return newRequest
    }

    static func sanitize(_ data: Data, requestUrl: String? = nil) -> Data {
        do {
            if let json = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String: Any] {
                let sanitizedJson = traverseAndMock(json, url: requestUrl)
                return try JSONSerialization.data(withJSONObject: sanitizedJson, options: [])
            } else if let jsonArray = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [[String: Any]] {
                let sanitizedArray = jsonArray.map { traverseAndMock($0, url: requestUrl) }
                return try JSONSerialization.data(withJSONObject: sanitizedArray, options: [])
            }
        } catch {
            print("MockDataSanitizer failed to parse JSON: \(error)")
        }
        return data
    }
    
    private static func traverseAndMock(_ dict: [String: Any], url: String?) -> [String: Any] {
        var mocked = dict
        for (key, value) in mocked {
            if let nestedDict = value as? [String: Any] {
                mocked[key] = traverseAndMock(nestedDict, url: url)
            } else if let nestedArray = value as? [Any] {
                mocked[key] = nestedArray.map { item -> Any in
                    if let dictItem = item as? [String: Any] {
                        return traverseAndMock(dictItem, url: url)
                    }
                    return item
                }
            } else {
                switch key {
                case "telephoneno":
                    mocked[key] = mockValue(for: value as? String, base: "011234567", keyType: "phone")
                case "accountno", "accountNo":
                    mocked[key] = mockValue(for: value as? String, base: "123456789", keyType: "account")
                case "contactNamewithInit":
                    mocked[key] = "John Doe"
                case "userId", "user_id":
                    mocked[key] = "john.doe"
                case "serviceID":
                    mocked[key] = mockValue(for: value as? String, base: "123456789_BB", keyType: "service")
                default:
                    break
                }
            }
        }
        
        if mocked["status"] != nil {
            if let originalPhone = dict["telephoneno"] as? String, let dummyPhone = mockMappings[originalPhone] {
                if isThrottled(dummyPhone: dummyPhone) {
                    mocked["status"] = "THROTTLED"
                }
            } else if let urlStr = url {
                for (originalPhone, dummyPhone) in mockMappings {
                    let internationalReal = "94" + originalPhone.dropFirst()
                    if urlStr.contains(internationalReal) || urlStr.contains(originalPhone) {
                        if isThrottled(dummyPhone: dummyPhone) {
                            mocked["status"] = "THROTTLED"
                        }
                    }
                }
            }
        }
        
        return mocked
    }
}

class MockDataURLProtocol: URLProtocol {
    private var dataTask: URLSessionDataTask?
    
    override class func canInit(with request: URLRequest) -> Bool {
        guard AppConstants.isScreenshotMode else { return false }
        if URLProtocol.property(forKey: "MockDataURLProtocolHandled", in: request) != nil {
            return false
        }
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        guard let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        
        URLProtocol.setProperty(true, forKey: "MockDataURLProtocolHandled", in: mutableRequest)
        
        let sanitizedRequest = MockDataSanitizer.sanitizeRequest(mutableRequest as URLRequest)
        
        let session = URLSession(configuration: .default)
        dataTask = session.dataTask(with: sanitizedRequest) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }
            if let response = response {
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            if let data = data {
                let sanitizedData = MockDataSanitizer.sanitize(data, requestUrl: sanitizedRequest.url?.absoluteString)
                self.client?.urlProtocol(self, didLoad: sanitizedData)
            }
            self.client?.urlProtocolDidFinishLoading(self)
        }
        dataTask?.resume()
    }
    
    override func stopLoading() {
        dataTask?.cancel()
    }
}
#endif
