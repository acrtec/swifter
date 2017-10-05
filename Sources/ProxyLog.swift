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
    static let shared: ProxyLog = ProxyLog()
    
    private(set) var logString : String = ""
    
    private let accessQueue = DispatchQueue(label: "ProxyLog")
    private let semaphore = DispatchSemaphore(value: 1)
    
    func log(string : String) {
        accessQueue.async {
            self.semaphore.wait()
            self.logString += string + "\n"
            self.semaphore.signal()
        }
    }
    
}
