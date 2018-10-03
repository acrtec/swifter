//
//  HTTPServerNonblocking.swift
//  Swifter
//
//  Created by Ronaldo Junior on 8/10/17.
//  Copyright © 2017 Damian Kołakowski. All rights reserved.
//

import Foundation

public class HTTPServerNonblocking: HttpServer {
    
    private let ProxyDidRestart = Notification.Name("ProxyDidRestart")

    private var isFirstTime = true
    private var shouldRestart = false
    private var timeoutErrorCounter = 0
    
    //Variable for debugging purposes
    private var previousCount = 0
    
    public override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc func didBecomeActive(){
        //Restart the socket every time the app comes back from background, as it might be "dead" for staying too long in background state.
        if isFirstTime {
            //Don't restart the socket the very first time, as that will be when the user is opening the app
            isFirstTime = false
            return
        }
        
        shouldRestart = true
    }
    
    public override func start(_ port: in_port_t = 8080, forceIPv4: Bool = false, priority: DispatchQoS.QoSClass = DispatchQoS.QoSClass.background) throws {
        guard !self.operating else { return }
        stop()
        self.state = .starting
        let address = forceIPv4 ? listenAddressIPv4 : listenAddressIPv6
        self.socket = try Socket.tcpSocketForListen(port, forceIPv4, SOMAXCONN, address, true)
        
        self.timeoutErrorCounter = 0
        self.shouldRestart = false
        
        let restartBlock = {
            self.stop()
            DispatchQueue.global().asyncAfter(
                deadline: DispatchTime.now() + Double(Int64(1 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC), execute: {
                    do {
                        try self.start(port, forceIPv4: forceIPv4, priority: priority)
                        DispatchQueue.global().async {
                            NotificationCenter.default.post(name: self.ProxyDidRestart, object: nil)
                        }
                    } catch {}
            })
        }
        
        DispatchQueue.global(qos: priority).async { [weak self] in
            guard let `self` = self else { return }
            guard self.operating else { return }
            
            var poll_set : [pollfd] = []
            
            poll_set.append(pollfd())
            poll_set[0].fd = self.socket.socketFileDescriptor
            poll_set[0].events = Int16(POLLIN)
            
            while true {
                if self.shouldRestart {
                    #if LOGDEBUG
                    print("Restarting after resuming the app")
                    #endif
                    restartBlock()
                    return
                }
                
                #if LOGDEBUG
                print("Waiting for select...")
                #endif
                let result = poll(&poll_set, nfds_t(poll_set.count), 5000)

                //For debugging purposes -> prints the current state of the polling array at every iteration where the count changes
//                if poll_set.count != self.previousCount {
//                    self.previousCount = poll_set.count
//                    print("=== \(poll_set.count) ===")
//                    var s = "["
//                    for poll in poll_set {
//                        s += "\(poll.fd) (\(poll.revents)), "
//                    }
//                    s += "]"
//                    print(s)
//                }
                
//                if result <= 0 {
//                    self.timeoutErrorCounter += 1
//                    if self.timeoutErrorCounter >= 10 {
//                        #if LOGDEBUG
//                        print("Had 10 consecutive timeout or errors, so will restart")
//                        #endif
//                        restartBlock()
//                        return
//                    }
//                } else {
//                    self.timeoutErrorCounter = 0
//                }
                
                if result == 0 {
                    #if LOGDEBUG
                    print("Poll did timeout")
                    #endif
                    continue
                } else if result < 0 {
                    #if LOGDEBUG
                    print("Poll failed with error - \(errno)")
                    #endif
                    continue
                }
                
                // run through the existing connections looking for data to read
                for i in 0 ..< poll_set.count {
                    if poll_set[i].revents != 0 && poll_set[i].revents == Int16(POLLIN) {
                        if poll_set[i].fd == self.socket.socketFileDescriptor {
                            // handle new connections
                            var addr = sockaddr()
                            var len: socklen_t = 0
                            let newfd = accept(self.socket.socketFileDescriptor, &addr, &len)
                            
                            if newfd == -1 {
                                #if LOGDEBUG
                                print("Accept Failed - \(newfd) - \(errno)")
                                #endif
                                restartBlock()
                                return
                            } else {
                                var poll = pollfd()
                                poll.fd = newfd
                                poll.events = Int16(POLLIN)
                                poll_set.append(poll)
                                #if LOGDEBUG
                                print("\tSelected new connection: \(newfd)")
                                #endif
                            }
                            
                        } else {
                            #if LOGDEBUG
                            print("\tHandle data from the client on \(poll_set[i].fd)")
                            #endif
                            let socket = Socket(socketFileDescriptor: poll_set[i].fd)
                            
                            let position = i
                            poll_set[position].fd = -1
                            self.handleConnection(socket: socket) { socket, keepConnection in
                                #if LOGDEBUG
                                print("\tReturned from the client on \(socket.socketFileDescriptor) - keep connection: \(keepConnection)")
                                #endif
                                if !keepConnection {
                                    socket.close()
                                }
                            }
                            
                        } // END handle data from client
                    } // END got new incoming connection
                } // END looping through file descriptors
                
                var i = 0
                while i < poll_set.count {
                    if poll_set[i].fd == -1 || poll_set[i].revents == POLLIN+POLLHUP {
                        poll_set.remove(at: i)
                        i -= 1
                    }
                    i += 1
                }
            } // END for(;;)--and you thought it would never end!
        }
        self.state = .running
    }
    
    private func handleConnection(socket: Socket, completion: @escaping ((_ socket : Socket, _ keepConnection: Bool) -> Void)) {
        
        let parser = HttpParser()
        
        if self.operating, let request = try? parser.readHttpRequest(socket) {
            request.address = try? socket.peername()
            dispatch(request: request, completion: { (params, handler) in
                request.params = params
                let response = handler(request)
                DispatchQueue.global().async {
                    let range = response.headers()["Range"]
                    var keepConnection = parser.supportsKeepAlive(request.headers)
                    do {
                        if self.operating {
                            #if LOGDEBUG
                            print("\t\tResponse on - \(socket.socketFileDescriptor) - \(request.path) - \(range ?? "") - \(response.statusCode())")
                            #endif
                            keepConnection = try self.respond(socket, response: response, keepAlive: keepConnection)
                        }
                    } catch {
                        self.cancel(request: request)
                        completion(socket, false)
                        return
                    }
                    
                    if let session = response.socketSession() {
                        session(socket)
                        completion(socket, keepConnection)
                    }
                    
                    if keepConnection || response.statusCode() == 206 {
                        completion(socket, true)
                    } else {
                        completion(socket, false)
                    }
                }
            })
        } else {
            completion(socket, false)
        }
    }
}

////////////////////////////////////////////////////////////////////////////////////////////////
//Information: code for manually reading socket data instead of using handleConnection method:
////////////////////////////////////////////////////////////////////////////////////////////////
//
//                            // handle data from a client
//                            var buffer = [UInt8](repeating: 0, count: 1)
//                            let nbytes = recv(i as Int32, &buffer, Int(buffer.count), 0)
//                            if nbytes <= 0 {
//                                // got error or connection closed by client
//                                if (nbytes == 0) {
//                                    // connection closed
//                                    print("Connection closed on \(i)")
//                                } else {
//                                    print("Recv failed")
//                                }
//                                close(i) // bye!
//                                fdClr(i, set: &master)
//                            } else {
//                                // we got some data from a client
//                                for j in 0 ..< fdmax {
//                                    // send to everyone!
//                                    if fdIsSet(j, set: &master) {
//                                        // except the listener and ourselves
//                                        if j != self.socket.socketFileDescriptor && j != i {
//                                            if send(j, buffer, nbytes, 0) == -1 {
//                                                print("Send failed");
//                                            }
//                                        }
//                                    }
//                                }
//                            }
