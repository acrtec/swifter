//
//  ProxyLog.swift
//  AcromaxMediaPlayer
//
//  Created by Ronaldo Junior on 10/5/17.
//

import Foundation

public class ProxyLog {
    
    //Singleton pattern
    fileprivate init() { }
    public static let shared: ProxyLog = ProxyLog()
    
    public private(set) var logString : String = ""
    
    private let accessQueue = DispatchQueue(label: "ProxyLog")
    private let semaphore = DispatchSemaphore(value: 1)
    
    public func log(string : String) {
        accessQueue.async {
            self.semaphore.wait()
            self.logString += string + "\n"
            self.semaphore.signal()
        }
    }
    
}
